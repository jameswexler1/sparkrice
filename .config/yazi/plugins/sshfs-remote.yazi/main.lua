local function sh_quote(s)
	return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

local script = [=[
set -euo pipefail

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf 'Missing dependency: %s\n' "$1" >/dev/tty
		printf 'Install it, then try again.\n' >/dev/tty
		printf '\nPress Enter to continue...' >/dev/tty
		IFS= read -r _ </dev/tty || true
		exit 2
	fi
}

need awk
need fzf
need sshfs
need mountpoint

mount_root="${XDG_RUNTIME_DIR:-/tmp}/yazi-sshfs-${USER:-user}"
mkdir -p "$mount_root"

ssh_config_hosts() {
	[ -f "$HOME/.ssh/config" ] || return 0

	awk '
		tolower($1) == "host" {
			for (i = 2; i <= NF; i++) {
				if ($i !~ /[*?%!]/) print $i
			}
		}
	' "$HOME/.ssh/config"
}

known_hosts_hosts() {
	[ -f "$HOME/.ssh/known_hosts" ] || return 0

	awk -F'[ ,]' '
		NF && $1 !~ /^\|/ {
			host = $1
			sub(/^\[/, "", host)
			sub(/\].*/, "", host)
			if (host != "") print host
		}
	' "$HOME/.ssh/known_hosts"
}

candidates="$(
	{
		ssh_config_hosts
		known_hosts_hosts
	} 2>/dev/null | sed '/^$/d' | sort -u
)"

choice="$(
	printf '%s\n%s\n' "[manual]" "$candidates" |
		fzf --prompt='SSH remote > ' --height=40% --reverse
)" || exit 0

if [ "$choice" = "[manual]" ]; then
	printf 'Remote (host, user@host, or SSH alias): ' >/dev/tty
	IFS= read -r host </dev/tty
else
	host="$choice"
fi

[ -n "$host" ] || exit 0

safe="$(printf '%s' "$host" | tr -c 'A-Za-z0-9_.@-' '_')"
mount_dir="$mount_root/$safe"
mkdir -p "$mount_dir"

case "$host" in
	*:*) remote_spec="$host" ;;
	*) remote_spec="$host:" ;;
esac

if ! mountpoint -q "$mount_dir"; then
	printf 'Mounting %s\n' "$remote_spec" >/dev/tty
	sshfs "$remote_spec" "$mount_dir" \
		-o reconnect \
		-o ServerAliveInterval=15 \
		-o ServerAliveCountMax=3 \
		</dev/tty >/dev/tty 2>/dev/tty
fi

printf '%s\n' "$mount_dir"
]=]

return {
	entry = function()
		local permit = ui.hide()
		local handle = io.popen("bash -c " .. sh_quote(script), "r")
		local target = handle and handle:read("*l") or nil
		local ok = handle and handle:close()
		permit:drop()

		if target and target ~= "" then
			ya.emit("cd", { Url(target) })
			return
		end

		if ok == false then
			ya.notify({
				title = "SSHFS remote",
				content = "Mount failed or was cancelled",
				level = "error",
				timeout = 4,
			})
		end
	end,
}
