# Kitty-specific bash helpers

# Colorized file listing in bash (macOS first, GNU fallback).
if ls -G . >/dev/null 2>&1; then
  export CLICOLOR=1
  export LSCOLORS="${LSCOLORS:-ExFxCxDxBxegedabagacad}"
  alias ls='ls -G'
elif ls --color=auto . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
fi
alias l='ls -CF'
alias la='ls -A'
alias ll='ls -lah'

__title_git_branch() {
  command -v git >/dev/null 2>&1 || return
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return
  [[ "$branch" = "HEAD" ]] && branch=""
  [[ -n "$branch" ]] && printf '%s' "$branch"
}

# Set the current kitty tab's title. Usage: ktab <title...>   (no title: back to automatic)
# Talks to this window's kitty when run inside it, else to the newest /tmp/kitty-main* socket.
ktab() {
  local kitty="/Applications/kitty.app/Contents/MacOS/kitty" sock
  if [ -n "${KITTY_WINDOW_ID:-}" ] && "$kitty" @ set-tab-title "$*" 2>/dev/null; then
    return 0
  fi
  for sock in $(ls -t /tmp/kitty-main* 2>/dev/null); do
    [ -S "$sock" ] && "$kitty" @ --to "unix:$sock" set-tab-title "$*" && return 0
  done
  echo "ktab: no kitty to talk to (is kitty running with remote control?)" >&2
  return 1
}
