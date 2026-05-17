#!/bin/zsh
# Watches all Kitty windows for Claude Code prompts and auto-responds.
set -u

KITTY_BIN="/Applications/kitty.app/Contents/MacOS/kitty"
POLL_INTERVAL=1
PIDFILE="/tmp/claude-approve.pid"
LIMIT_FILE="/tmp/claude-limit.txt"  # written: "reset_epoch|display_str"

pick_socket() {
  local s
  for s in /tmp/kitty-main*; do
    [ -S "$s" ] && printf '%s\n' "unix:$s" && return 0
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
[ -n "$TARGET" ] || { print "claude-approve: no kitty socket found" >&2; exit 1; }

printf '%s' "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

krc() { "$KITTY_BIN" @ --to "$TARGET" "$@"; }

typeset -A approved

while true; do
  window_ids=("${(@f)$(krc ls 2>/dev/null | jq -r '.[] | .tabs[] | .windows[] | .id' 2>/dev/null)}")

  for wid in "${window_ids[@]}"; do
    [[ -z "$wid" || -z "${wid//[0-9]/}" ]] || continue
    screen="$(krc get-text --match "id:$wid" --extent screen 2>/dev/null)" || continue

    if printf '%s' "$screen" | grep -qF 'Do you want to proceed?'; then
      if [[ "${approved[$wid]:-0}" == "0" ]]; then
        krc send-text --match "id:$wid" "1\r" 2>/dev/null && approved[$wid]=1
      fi
    elif printf '%s' "$screen" | grep -qF 'Do you want to make this edit'; then
      if [[ "${approved[$wid]:-0}" == "0" ]]; then
        krc send-text --match "id:$wid" "2\r" 2>/dev/null && approved[$wid]=1
      fi
    else
      approved[$wid]=0
    fi
  done

  sleep "$POLL_INTERVAL"
done
