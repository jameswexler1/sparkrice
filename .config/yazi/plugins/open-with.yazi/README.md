# open-with.yazi

Show the applications registered for the highlighted file in a popup inside
Yazi. Uses the same `File::MimeInfo` and `File::DesktopEntry` Perl libraries as
`mimeopen --ask`, preserving its application ordering and launch behavior.

Tested with Yazi 26.9.1 on Linux. Requires Perl and the libraries supplied with
`mimeopen` (`perl-file-mimeinfo` on Arch).

Add to `init.lua`:

```lua
require("open-with"):setup()
```

Bind in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = "O"
run = "plugin open-with"
desc = "Choose an application for the hovered file"
```

The popup uses Yazi's confirmation input layer with an invisible, zero-size
confirmation. Add these routes to `keymap.toml` as well. They keep ordinary
confirmation scrolling and the `y` binding working when the app picker is closed:

```toml
[confirm]
prepend_keymap = [
  { on = "<Up>",       run = "mgr:plugin open-with -- up" },
  { on = "k",          run = "mgr:plugin open-with -- up" },
  { on = "<Down>",     run = "mgr:plugin open-with -- down" },
  { on = "j",          run = "mgr:plugin open-with -- down" },
  { on = "<Home>",     run = "mgr:plugin open-with -- top" },
  { on = "g",          run = "mgr:plugin open-with -- top" },
  { on = "<End>",      run = "mgr:plugin open-with -- bottom" },
  { on = "G",          run = "mgr:plugin open-with -- bottom" },
  { on = "<PageUp>",   run = "mgr:plugin open-with -- page-up" },
  { on = "<C-u>",      run = "mgr:plugin open-with -- page-up" },
  { on = "<PageDown>", run = "mgr:plugin open-with -- page-down" },
  { on = "<C-d>",      run = "mgr:plugin open-with -- page-down" },
  { on = "q",          run = "mgr:plugin open-with -- cancel" },
  { on = "y",          run = "mgr:plugin open-with -- yes" },
]
```

If `[confirm]` already exists, add `prepend_keymap` to that section; do not add
another `[confirm]` heading. The installed configuration uses the equivalent
`[[confirm.prepend_keymap]]` form at the end of the file.

Controls: Up/Down or k/j move, Enter opens, Esc/Ctrl-C/q cancel. Home/End (or
g/G) jump to the first/last entry; PageUp/PageDown (or Ctrl-U/Ctrl-D) scroll.
The native confirmation layer also accepts `n` to cancel; `y` is ignored in
the application picker so Enter is the only launch key. Other manager shortcuts
are blocked while the popup is open.

The popup uses `th.pick` colors, rounded borders and placement below the hovered
file (above it near the bottom). Defaults match this configuration's native
picker: 50 columns and at most 7 rows. Override with
`setup { width = 60, height = 12 }` if desired. Long lists scroll.

This is a custom Yazi-rendered popup; the built-in picker does not expose an API
for a dynamic application list in this release. The list is queried each time
you open the menu. Only the highlighted file is opened, matching the original
lf binding. Native remote URLs must be downloaded first; local SSHFS paths work
like any other local file. Application associations are only read, never changed.
