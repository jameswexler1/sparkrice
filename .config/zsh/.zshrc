# Luke's config for the Zoomer Shell

# Enable colors and change prompt:
autoload -U colors && colors	# Load colors
# Pywal colors (updates with wallpaper)

# Powerline prompt
SEP=$'\ue0b0'
setopt PROMPT_SUBST

precmd() {
    if [ -z "$FIRST_PROMPT" ]; then
        FIRST_PROMPT=1
    else
        print ""
    fi

    # Split current path into segments
    local dir="${(%):-%~}"
    local parts=("${(@s:/:)dir}")
    local seg_colors=(4 5 6 2 3)
    local path_prompt=""
    local prev_col=0
    local i=1

    for part in "${parts[@]}"; do
        [[ -z "$part" ]] && part="/"
        local col=${seg_colors[$(( (i-1) % ${#seg_colors} + 1 ))]}
        path_prompt+="%K{${col}}%F{${prev_col}}${SEP}%F{0} ${part} "
        prev_col=$col
        (( i++ ))
    done
    path_prompt+="%k%F{${prev_col}}${SEP}%f"
    PATH_PROMPT="$path_prompt"
}

PS1='%K{0}%F{1} %n@%M ${PATH_PROMPT} '
setopt autocd		# Automatically cd into typed directory.
stty stop undef		# Disable ctrl-s to freeze terminal.
setopt interactive_comments

# The prompt experiment finishes here.

# History in cache directory:
HISTSIZE=10000000
SAVEHIST=10000000
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history"
setopt inc_append_history

# Load aliases and shortcuts if existent.
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutrc"
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutenvrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/shortcutenvrc"
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/aliasrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/aliasrc"
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/shell/zshnameddirrc" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/zshnameddirrc"

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.

# vi mode
bindkey -v
export KEYTIMEOUT=1

# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -v '^?' backward-delete-char

# Change cursor shape for different vi modes.
function zle-keymap-select () {
    case $KEYMAP in
        vicmd) echo -ne '\e[1 q';;      # block
        viins|main) echo -ne '\e[5 q';; # beam
    esac
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.

# Use lf to switch directories and bind it to ctrl-o
lfcd () {
    tmp="$(mktemp -uq)"
    trap 'rm -f $tmp >/dev/null 2>&1 && trap - HUP INT QUIT TERM PWR EXIT' HUP INT QUIT TERM PWR EXIT
    lf -last-dir-path="$tmp" "$@"
    if [ -f "$tmp" ]; then
        dir="$(cat "$tmp")"
        [ -d "$dir" ] && [ "$dir" != "$(pwd)" ] && cd "$dir"
    fi
}

# Use nv as an interactive way of opening files directly with nvim

nv() {
  local file
  file=$(fzf --preview='cat {}')
  if [[ -n "$file" ]]; then
    nvim "$file"
  fi
}

bindkey -s '^o' '^ulfcd\n'

bindkey -s '^a' '^ubc -lq\n'

bindkey -s '^f' '^ucd "$(dirname "$(fzf)")"\n'

bindkey '^[[P' delete-char

# Edit line in vim with ctrl-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^e' edit-command-line
bindkey -M vicmd '^[[P' vi-delete-char
bindkey -M vicmd '^e' edit-command-line
bindkey -M visual '^[[P' vi-delete

# Load syntax highlighting; should be last.
source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 2>/dev/null

# Load zoxide for a smarter cd (EXPERIMENTAL. COMMENT OUT IF UNSURE)
eval "$(zoxide init zsh)"

# Load the beautiful terminal name thing (EXPERIMENTAL. COMMENT OUT IF UNSURE)
# export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
# eval "$(starship init zsh)"
