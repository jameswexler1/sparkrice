#!/usr/bin/env python3
"""
codedit.py — Edit an entire codebase in a single nvim buffer.

Usage:
    python codedit.py [root_dir]

Opens all text files in one nvim buffer, separated by FILE markers.
On save-and-quit, writes only the changed files back to disk.

Marker lines look like:
    # ════════ FILE: src/main.py ════════
Do NOT edit those lines — they are the boundaries used for parsing.
"""

import os
import re
import sys
import tempfile
import subprocess
from pathlib import Path


# ── Skip rules ─────────────────────────────────────────────────────────────

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

# ── Marker format ───────────────────────────────────────────────────────────
# Uses ═ (U+2550) — unlikely to appear in real code and visually distinct.

MARKER_TMPL = "# ════════ FILE: {} ════════"
MARKER_RE   = re.compile(r"^# ════════ FILE: (.+?) ════════$")


# ── File collection ─────────────────────────────────────────────────────────

def is_binary(path: Path) -> bool:
    """Detect binary by sniffing the first 8 KB for null bytes."""
    try:
        with open(path, "rb") as f:
            return b"\x00" in f.read(8192)
    except OSError:
        return True


def skip_dir(path: Path) -> bool:
    return path.name in SKIP_DIRS or (
        path.name.startswith(".") and path.name not in {".github"}
    )


def skip_file(path: Path) -> bool:
    return (
        path.name in SKIP_FILES
        or path.suffix.lower() in SKIP_EXTENSIONS
        or (path.name.startswith(".") and path.name not in {".env", ".env.example", ".gitignore"})
        or is_binary(path)
    )


def load_gitignore(root: Path) -> list[str]:
    gi = root / ".gitignore"
    if not gi.exists():
        return []
    return [
        ln.strip().rstrip("/")
        for ln in gi.read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]


def is_gitignored(path: Path, root: Path, patterns: list[str]) -> bool:
    rel = str(path.relative_to(root))
    return any(pat == path.name or pat in rel for pat in patterns)


def collect_files(root: Path) -> list[Path]:
    gitignore = load_gitignore(root)
    files: list[Path] = []

    for dirpath, dirnames, filenames in os.walk(root, topdown=True):
        dp = Path(dirpath)

        # Prune directories in-place (os.walk respects this)
        dirnames[:] = sorted(
            d for d in dirnames
            if not skip_dir(dp / d)
            and not is_gitignored(dp / d, root, gitignore)
        )

        for fname in sorted(filenames):
            fpath = dp / fname
            if skip_file(fpath) or is_gitignored(fpath, root, gitignore):
                continue
            files.append(fpath)

    return files


# ── Buffer builder ──────────────────────────────────────────────────────────

def build_buffer(files: list[Path], root: Path) -> str:
    lines: list[str] = []

    lines.append("# codedit — edit any file below, then :wq to write changes back to disk.")
    lines.append("# ⚠  Do NOT modify or delete the FILE marker lines.")
    lines.append("# ✅  Global find/replace, multi-file refactors, etc. all work fine.")
    lines.append("")

    for path in files:
        rel = str(path.relative_to(root))
        lines.append(MARKER_TMPL.format(rel))
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            content = f"# [Error reading file: {e}]\n"
        # Append content, ensuring it ends with exactly one newline
        lines.append(content.rstrip("\n"))
        lines.append("")  # blank line separator between files

    return "\n".join(lines) + "\n"


# ── Buffer parser ───────────────────────────────────────────────────────────

def parse_buffer(content: str, root: Path) -> dict[Path, str]:
    """Split edited buffer back into {absolute_path: file_content}."""
    result: dict[Path, str] = {}
    current_path: Path | None = None
    current_lines: list[str] = []

    for line in content.splitlines():
        m = MARKER_RE.match(line)
        if m:
            # Flush previous file
            if current_path is not None:
                result[current_path] = _flush(current_lines)
            current_path = root / m.group(1)
            current_lines = []
        elif current_path is not None:
            current_lines.append(line)

    # Flush last file
    if current_path is not None:
        result[current_path] = _flush(current_lines)

    return result


def _flush(lines: list[str]) -> str:
    """Join lines, strip trailing blank lines, ensure final newline."""
    return "\n".join(lines).rstrip("\n") + "\n"


# ── Write-back ──────────────────────────────────────────────────────────────

def write_back(
    original_files: list[Path],
    edited: dict[Path, str],
    root: Path,
    dry_run: bool = False,
) -> None:
    changed: list[Path] = []
    removed: list[Path] = []

    for path in original_files:
        if path not in edited:
            removed.append(path)
            continue

        new_content = edited[path]
        try:
            old_content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            old_content = None

        if old_content != new_content:
            changed.append(path)
            if not dry_run:
                path.write_text(new_content, encoding="utf-8")

    # Report
    if changed:
        verb = "Would write" if dry_run else "Wrote"
        print(f"\n✅  {verb} {len(changed)} changed file(s):")
        for p in changed:
            print(f"    ~ {p.relative_to(root)}")
    else:
        print("\n✅  No changes detected.")

    if removed:
        print(
            f"\n⚠️   {len(removed)} file marker(s) were removed from the buffer.\n"
            "    Those files were NOT modified on disk (safe default).\n"
            "    To delete a file, do it manually."
        )
        for p in removed:
            print(f"    - {p.relative_to(root)}")


# ── Entry point ─────────────────────────────────────────────────────────────

def main() -> None:
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    args = [a for a in args if not a.startswith("--")]

    root = Path(args[0]).resolve() if args else Path(".").resolve()

    if not root.is_dir():
        print(f"❌  Not a directory: {root}")
        sys.exit(1)

    print(f"🔍  Scanning {root} ...")
    files = collect_files(root)

    if not files:
        print("No text files found.")
        sys.exit(0)

    print(f"📂  {len(files)} file(s) collected. Opening in nvim...")

    buffer_content = build_buffer(files, root)

    # Write to a temp file and open nvim
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".codedit",
        encoding="utf-8",
        delete=False,
        prefix="codedit_",
    ) as tmp:
        tmp.write(buffer_content)
        tmp_path = Path(tmp.name)

    try:
        subprocess.run(["nvim", str(tmp_path)], check=False)
        edited_content = tmp_path.read_text(encoding="utf-8")
    finally:
        tmp_path.unlink(missing_ok=True)

    edited = parse_buffer(edited_content, root)
    write_back(files, edited, root, dry_run=dry_run)


if __name__ == "__main__":
    main()
