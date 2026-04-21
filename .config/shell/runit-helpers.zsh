# THESE MUST BE ONLY USED ON ARTIX LINUX WITH RUNIT!!!! THERE IS ALREADY A COMMENTED OUT LINE IN ZSHRC TO BE UNCOMMENTED IN THIS CASE
# runit-helpers.zsh
# Runit service management helpers for Artix Linux

svstart()   { sudo sv start "$1"; }
svstop()    { sudo sv stop "$1"; }
svrestart() { sudo sv restart "$1"; }
svstatus()  { sv status "/run/runit/service/${1:-}"; }

senable() {
    [ -z "$1" ] && { echo "Usage: senable <service>"; return 1; }
    sudo ln -s "/etc/runit/sv/$1" "/etc/runit/runsvdir/default/" 2>/dev/null \
        || echo "Already enabled at boot"
    sudo ln -s "/etc/runit/sv/$1" "/run/runit/service/" 2>/dev/null \
        || echo "Already running"
    echo "✅ Enabled and started $1"
}

sdisable() {
    [ -z "$1" ] && { echo "Usage: sdisable <service>"; return 1; }
    sudo sv stop "$1" 2>/dev/null
    sudo rm -f "/run/runit/service/$1"
    sudo rm -f "/etc/runit/runsvdir/default/$1"
    echo "❌ Disabled and stopped $1"
}

slist() {
    echo "=== Running services ==="
    ls /run/runit/service/
    echo ""
    echo "=== Enabled at boot ==="
    ls /etc/runit/runsvdir/default/
}

savailable() {
    echo "=== Available services ==="
    ls /etc/runit/sv/
}

# Autocomplete for runit helpers
_runit_running() {
    local services
    services=($(ls /run/runit/service/))
    compadd $services
}

_runit_available() {
    local services
    services=($(ls /etc/runit/sv/))
    compadd $services
}

compdef _runit_available senable savailable
compdef _runit_running sdisable svstart svstop svrestart svstatus
