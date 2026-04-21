#!/usr/bin/env python3
"""
merge.py — Interactive file merger for LLM/Claude context

Usage:
    python merge.py [root_dir] [output_file]

Defaults: current directory → merged_output.md

Requires:
    pip install textual
"""

import sys
from pathlib import Path

try:
    from textual.app import App, ComposeResult
    from textual.widgets import Tree, Header, Footer, Static
    from textual.widgets.tree import TreeNode
    from textual.binding import Binding
    from textual.containers import Vertical
except ImportError:
    print("❌  Please install textual first:  pip install textual")
    sys.exit(1)


# ── Skip rules ────────────────────────────────────────────────────────────────

SKIP_DIRS: set[str] = {
    "node_modules", "__pycache__", ".git", "dist", "build",
    ".next", "out", ".nuxt", "venv", ".venv", "env", ".tox",
    "coverage", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "target", ".cargo", "vendor", ".idea", ".vscode",
}

SKIP_FILES: set[str] = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
    "poetry.lock", "Pipfile.lock", "composer.lock", "Gemfile.lock",
    ".DS_Store", "Thumbs.db", "desktop.ini",
}

SKIP_EXTENSIONS: set[str] = {
    # Images
    ".ico", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif",
    ".bmp", ".tiff", ".raw", ".heic", ".svg",
    # Fonts
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    # Media
    ".mp3", ".mp4", ".wav", ".ogg", ".avi", ".mov", ".mkv", ".webm",
    # Archives
    ".zip", ".tar", ".gz", ".bz2", ".rar", ".7z", ".xz",
    # Binaries / compiled
    ".exe", ".dll", ".so", ".dylib", ".bin", ".o", ".a",
    ".pyc", ".pyo", ".class", ".wasm",
    # Documents
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    # Data
    ".db", ".sqlite", ".sqlite3",
    # Source maps
    ".map",
}

LANG_MAP: dict[str, str] = {
    ".py": "python", ".pyi": "python",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".ts": "typescript", ".mts": "typescript",
    ".jsx": "jsx", ".tsx": "tsx",
    ".html": "html", ".htm": "html", ".css": "css",
    ".scss": "scss", ".sass": "sass", ".less": "less",
    ".json": "json", ".jsonc": "jsonc", ".json5": "json5",
    ".md": "markdown", ".mdx": "mdx",
    ".sh": "bash", ".bash": "bash", ".zsh": "bash", ".fish": "fish",
    ".yaml": "yaml", ".yml": "yaml",
    ".toml": "toml", ".ini": "ini", ".cfg": "ini", ".conf": "nginx",
    ".env": "bash",
    ".rs": "rust", ".go": "go", ".java": "java",
    ".c": "c", ".h": "c", ".cpp": "cpp", ".cc": "cpp", ".hpp": "cpp",
    ".cs": "csharp", ".rb": "ruby", ".php": "php",
    ".swift": "swift", ".kt": "kotlin", ".kts": "kotlin",
    ".lua": "lua", ".r": "r", ".R": "r",
    ".sql": "sql", ".graphql": "graphql", ".gql": "graphql",
    ".xml": "xml",
    ".tf": "hcl", ".hcl": "hcl",
    ".dockerfile": "dockerfile",
    ".vim": "vim", ".el": "elisp",
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def is_binary(path: Path) -> bool:
    """Detect binary by sniffing the first 8 KB for null bytes."""
    try:
        with open(path, "rb") as f:
            return b"\x00" in f.read(8192)
    except OSError:
        return True


def estimate_tokens(path: Path) -> int:
    """Rough token count: ~4 chars per token (GPT-style)."""
    try:
        return max(1, len(path.read_text(errors="replace")) // 4)
    except OSError:
        return 0


def load_gitignore(root: Path) -> list[str]:
    """Return non-comment, non-empty lines from .gitignore."""
    gi = root / ".gitignore"
    if not gi.exists():
        return []
    return [
        ln.strip().rstrip("/")
        for ln in gi.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]


def is_gitignored(path: Path, root: Path, patterns: list[str]) -> bool:
    """Basic name/rel-path matching (no glob wildcards)."""
    rel = str(path.relative_to(root))
    return any(pat == path.name or pat in rel for pat in patterns)


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}k"
    return str(n)


# ── Node data class ───────────────────────────────────────────────────────────

class FileNode:
    __slots__ = ("path", "is_dir", "included", "tokens")

    def __init__(self, path: Path, is_dir: bool, included: bool, tokens: int = 0):
        self.path = path
        self.is_dir = is_dir
        self.included = included
        self.tokens = tokens


# ── Custom Tree — owns all key handling ──────────────────────────────────────

class FileTree(Tree):
    """
    Intercepts every key we care about before Textual's default tree
    behaviour (expand/collapse on Space/Enter) can fire.
    """

    def on_key(self, event) -> None:  # noqa: ANN001
        app: MergeApp = self.app  # type: ignore[assignment]
        key = event.key

        if key == "space":
            event.prevent_default()
            event.stop()
            app.do_toggle()

        elif key == "enter":
            event.prevent_default()
            event.stop()
            app.do_confirm()

        elif key == "l" or key == "right":
            event.prevent_default()
            event.stop()
            app.do_expand_right()

        elif key == "h" or key == "left":
            event.prevent_default()
            event.stop()
            app.do_collapse_left()

        elif key == "o":
            event.prevent_default()
            event.stop()
            app.do_expand_right()

        elif key == "j" or key == "down":
            event.prevent_default()
            event.stop()
            self.action_cursor_down()

        elif key == "k" or key == "up":
            event.prevent_default()
            event.stop()
            self.action_cursor_up()

        elif key == "g":
            event.prevent_default()
            event.stop()
            self.action_scroll_home()

        elif key == "G":
            event.prevent_default()
            event.stop()
            self.action_scroll_end()

        elif key == "ctrl+d":
            event.prevent_default()
            event.stop()
            for _ in range(10):
                self.action_cursor_down()

        elif key == "ctrl+u":
            event.prevent_default()
            event.stop()
            for _ in range(10):
                self.action_cursor_up()

        elif key == "a":
            event.prevent_default()
            event.stop()
            app.do_toggle_all()

        elif key == "q":
            event.prevent_default()
            event.stop()
            app.do_quit()


# ── TUI App ───────────────────────────────────────────────────────────────────

class MergeApp(App[list[Path]]):
    """
    Keys:
      ↑ / ↓   navigate
      Space   toggle file or whole folder
      A       select / deselect all
      Enter   generate merged output
      Q       quit without generating
    """

    CSS = """
    Screen { layout: vertical; background: $background; }

    #tree-panel {
        height: 1fr;
        border: solid $primary;
        padding: 0 1;
        overflow-y: scroll;
    }

    #status {
        height: 4;
        padding: 0 2;
        border: solid $accent;
        background: $surface;
        content-align: left middle;
        color: $text;
    }
    """

    BINDINGS = [
        Binding("space", "noop", "Toggle select", show=True),
        Binding("l/h", "noop", "Open/close dir", show=True),
        Binding("a", "noop", "Select all", show=True),
        Binding("enter", "noop", "Generate ✓", show=True),
        Binding("q", "noop", "Quit", show=True),
    ]

    def action_noop(self) -> None:
        pass  # bindings above are display-only; FileTree.on_key does the real work

    def __init__(self, root: Path, output: Path) -> None:
        super().__init__()
        self.root = root
        self.output = output
        self.gitignore = load_gitignore(root)
        self._file_map: dict[int, FileNode] = {}

    # ── Layout ────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        with Vertical(id="tree-panel"):
            yield FileTree(f"📁  {self.root.resolve()}", id="tree")
        yield Static("", id="status")
        yield Footer()

    def on_mount(self) -> None:
        tree = self.query_one("#tree", FileTree)
        tree.root.expand()
        self._populate(tree.root, self.root)
        self._refresh_status()

    # ── Tree building ─────────────────────────────────────────────────────

    def _skip_dir(self, p: Path) -> bool:
        return (
            p.name in SKIP_DIRS
            or is_gitignored(p, self.root, self.gitignore)
        )

    def _skip_file(self, p: Path) -> bool:
        return (
            p.name in SKIP_FILES
            or p.suffix.lower() in SKIP_EXTENSIONS
            or p == self.output
            or is_binary(p)
            or is_gitignored(p, self.root, self.gitignore)
        )

    def _populate(self, node: TreeNode, directory: Path) -> None:
        try:
            entries = sorted(
                directory.iterdir(),
                key=lambda p: (p.is_file(), p.name.lower()),
            )
        except PermissionError:
            return

        for entry in entries:
            if entry.name.startswith(".") and entry.name not in {".env", ".env.example"}:
                continue

            if entry.is_dir():
                if self._skip_dir(entry):
                    continue
                child = node.add(f"📂  {entry.name}", expand=False)
                fn = FileNode(entry, is_dir=True, included=True)
                self._file_map[id(child)] = fn
                self._populate(child, entry)

            else:
                if self._skip_file(entry):
                    continue
                tokens = estimate_tokens(entry)
                label = self._file_label(entry.name, True, tokens)
                child = node.add_leaf(label)
                self._file_map[id(child)] = FileNode(
                    entry, is_dir=False, included=True, tokens=tokens
                )

    @staticmethod
    def _file_label(name: str, included: bool, tokens: int) -> str:
        box = "☑" if included else "☐"
        tok = f"  [{fmt_tokens(tokens)} tok]" if included and tokens else ""
        return f"{box}  {name}{tok}"

    # ── Status bar ────────────────────────────────────────────────────────

    def _refresh_status(self) -> None:
        files = [fn for fn in self._file_map.values() if not fn.is_dir and fn.included]
        total_tok = sum(fn.tokens for fn in files)
        ctx_pct = min(100, round(total_tok / 2000))
        self.query_one("#status", Static).update(
            f"  ✅  {len(files)} files  •  ~{fmt_tokens(total_tok)} tokens  ({ctx_pct}% of 200k ctx)\n"
            f"  j/k move   l/h open·close dir   Space toggle   A select all   Enter generate   Q quit"
        )

    # ── Public methods called by FileTree ─────────────────────────────────

    def do_toggle(self) -> None:
        cursor = self._tree().cursor_node
        if cursor is None:
            return
        fn = self._file_map.get(id(cursor))
        if fn is None:
            return
        self._set_subtree(cursor, not fn.included)
        self._refresh_status()

    def do_toggle_all(self) -> None:
        file_nodes = [fn for fn in self._file_map.values() if not fn.is_dir]
        new = not all(fn.included for fn in file_nodes)
        self._set_subtree(self._tree().root, new)
        self._refresh_status()

    def do_confirm(self) -> None:
        selected = [
            fn.path for fn in self._file_map.values()
            if not fn.is_dir and fn.included
        ]
        self.exit(selected)

    def do_quit(self) -> None:
        self.exit([])

    def do_expand_right(self) -> None:
        """l / right — expand dir, or step into it if already open."""
        cursor = self._tree().cursor_node
        if cursor is None:
            return
        fn = self._file_map.get(id(cursor))
        if fn and fn.is_dir:
            if not cursor.is_expanded:
                cursor.expand()
            else:
                self._tree().action_cursor_down()

    def do_collapse_left(self) -> None:
        """h / left — collapse dir if open, otherwise jump to parent."""
        tree = self._tree()
        cursor = tree.cursor_node
        if cursor is None:
            return
        fn = self._file_map.get(id(cursor))
        if fn and fn.is_dir and cursor.is_expanded:
            cursor.collapse()
        else:
            parent = cursor.parent
            if parent is not None and parent != tree.root:
                tree.move_cursor(parent)

    def _tree(self) -> FileTree:
        return self.query_one("#tree", FileTree)

    def _set_subtree(self, node: TreeNode, included: bool) -> None:
        fn = self._file_map.get(id(node))
        if fn is not None:
            fn.included = included
            if not fn.is_dir:
                node.set_label(self._file_label(fn.path.name, included, fn.tokens))
        for child in node.children:
            self._set_subtree(child, included)


# ── Merge writer ──────────────────────────────────────────────────────────────

def merge_files(files: list[Path], root: Path, output: Path) -> None:
    files = sorted(files, key=lambda p: str(p.relative_to(root)))
    total_tokens = 0

    with open(output, "w", encoding="utf-8") as out:
        out.write("# Merged Context\n\n")
        out.write(
            "> Generated by merge.py — paste this file into Claude or any LLM.\n\n"
        )

        out.write("## Files\n\n")
        for i, f in enumerate(files, 1):
            rel = f.relative_to(root)
            out.write(f"{i}. `{rel}`\n")
        out.write("\n---\n\n")

        for f in files:
            rel = f.relative_to(root)
            lang = LANG_MAP.get(f.suffix.lower(), "")
            try:
                content = f.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                content = f"[Error reading file: {e}]"

            tok = max(1, len(content) // 4)
            total_tokens += tok

            out.write(f"## `{rel}`\n\n")
            out.write(f"```{lang}\n")
            out.write(content)
            if not content.endswith("\n"):
                out.write("\n")
            out.write("```\n\n")

    size_kb = output.stat().st_size / 1024
    print(f"\n✅  Merged {len(files)} files  →  {output}")
    print(f"    ~{fmt_tokens(total_tokens)} tokens  •  {size_kb:.1f} KB")


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(".").resolve()
    output = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "merged_output.md"

    if not root.is_dir():
        print(f"❌  Not a directory: {root}")
        sys.exit(1)

    app = MergeApp(root=root, output=output)
    selected: list[Path] = app.run()  # type: ignore[assignment]

    if not selected:
        print("Aborted — nothing written.")
        sys.exit(0)

    merge_files(selected, root, output)


if __name__ == "__main__":
    main()
