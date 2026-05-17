#!/bin/zsh
set -u

KITTY_BIN="/Applications/kitty.app/Contents/MacOS/kitty"
BASH_BIN="/opt/homebrew/bin/bash"

pick_socket() {
  local s focused
  for s in /tmp/kitty-main*; do
    [ -S "$s" ] || continue
    focused="$("$KITTY_BIN" @ --to "unix:$s" ls 2>/dev/null | jq -r 'any(.[]; .is_focused==true)' 2>/dev/null)"
    [ "$focused" = "true" ] && { printf '%s\n' "unix:$s"; return 0; }
  done
  return 1
}

resolve_target() {
  if [ -n "${KITTY_LISTEN_ON:-}" ] && "$KITTY_BIN" @ --to "$KITTY_LISTEN_ON" ls >/dev/null 2>&1; then
    printf '%s\n' "$KITTY_LISTEN_ON"
    return 0
  fi
  pick_socket || return 1
}

TARGET="$(resolve_target || true)"
[ -n "$TARGET" ] || exit 1

krc() {
  "$KITTY_BIN" @ --to "$TARGET" "$@"
}

json="$(krc ls 2>/dev/null)" || exit 1
focused_tab_title="$(printf '%s' "$json" | jq -r '[.[] | .tabs[] | select(.is_focused == true)] | .[0].title // ""')"
focused_profile="$(printf '%s' "$json" | jq -r '[.[] | .tabs[] | select(.is_focused == true) | .windows[] | select(.is_focused == true)] | .[0].user_vars.profile // ""')"

if [ -z "$focused_profile" ] || [ "$focused_profile" = "null" ]; then
  case "$focused_tab_title" in
    Blue) focused_profile="blue" ;;
    Green) focused_profile="green" ;;
    Red) focused_profile="red" ;;
    *) focused_profile="gray" ;;
  esac
fi

if [ "$focused_profile" = "gray" ] || [ -z "$focused_profile" ]; then
  krc launch --type=window --cwd=current --var profile=gray >/dev/null 2>&1
  exit 0
fi

if [ ! -x "$BASH_BIN" ]; then
  BASH_BIN="$(command -v bash 2>/dev/null || true)"
fi
[ -n "$BASH_BIN" ] || exit 1

krc launch --type=window --cwd=current --var "profile=$focused_profile" "$BASH_BIN" -i >/dev/null 2>&1
