# sshfs-remote.yazi

Pick an SSH remote with `fzf`, mount it with `sshfs`, and jump Yazi into the mount.
By default, `sshfs host:` mounts the remote user's home directory.

The plugin discovers remotes from:

- `~/.ssh/config` `Host` entries, excluding wildcard hosts
- non-hashed `~/.ssh/known_hosts` entries
- a manual entry option

It does not store passwords. `sshfs`/SSH prompts normally.

## Dependencies

On Arch:

```sh
sudo pacman -S sshfs fzf
```

## Install

Copy this folder to:

```sh
~/.config/yazi/plugins/sshfs-remote.yazi
```

Add this to `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "r" ]
run = "plugin sshfs-remote"
desc = "Pick SSH remote"
```

Restart Yazi.

## Workflow

```text
local file -> y -> g r -> pick remote -> enter password -> navigate home -> p
remote file -> y -> g h / g d -> p
```

Mounted remotes are placed under:

```text
$XDG_RUNTIME_DIR/yazi-sshfs-$USER
```

or `/tmp/yazi-sshfs-$USER` if `XDG_RUNTIME_DIR` is not set.
