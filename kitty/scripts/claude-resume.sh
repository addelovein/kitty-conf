#!/bin/zsh
# Always-on watcher: handles Claude rate-limit prompts, tracks reset time, auto-resumes.
set -u

KITTY_BIN="/Applications/kitty.app/Contents/MacOS/kitty"
POLL_INTERVAL=5
PIDFILE="/tmp/claude-resume.pid"
LIMIT_FILE="/tmp/claude-limit.txt"  # format: "reset_epoch|time_str"

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
[ -n "$TARGET" ] || { print "claude-resume: no kitty socket found" >&2; exit 1; }

printf '%s' "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE" "$LIMIT_FILE"' EXIT

krc() { "$KITTY_BIN" @ --to "$TARGET" "$@"; }

parse_reset_time() {
  local raw="$1"
  local time_str tz epoch now
  time_str="$(printf '%s' "$raw" | grep -oE '[0-9]{1,2}:[0-9]{2}(am|pm)')"
  tz="$(printf '%s' "$raw" | grep -oE '\([A-Za-z_/]+\)' | tr -d '()')"
  [ -z "$time_str" ] && return 1
  [ -z "$tz" ] && tz="$(date +%Z)"
  epoch="$(TZ="$tz" date -j -f "%I:%M%p" "$(printf '%s' "$time_str" | tr '[:lower:]' '[:upper:]')" "+%s" 2>/dev/null)" || return 1
  now="$(date +%s)"
  [ "$epoch" -lt "$now" ] && epoch=$(( epoch + 86400 ))
  printf '%s|%s' "$epoch" "$time_str"
}

typeset -A limit_sent
typeset -A resumed

while true; do
  window_ids=("${(@f)$(krc ls 2>/dev/null | jq -r '.[] | .tabs[] | .windows[] | .id' 2>/dev/null)}")

  for wid in "${window_ids[@]}"; do
    [[ -z "$wid" || -z "${wid//[0-9]/}" ]] || continue
    screen="$(krc get-text --match "id:$wid" --extent screen 2>/dev/null)" || continue

    # Interactive rate-limit prompt → pick "Stop and wait"
    if printf '%s' "$screen" | grep -qF 'Stop and wait for limit to reset'; then
      if [[ "${limit_sent[$wid]:-0}" == "0" ]]; then
        krc send-text --match "id:$wid" "1\r" 2>/dev/null
        limit_sent[$wid]=1
        resumed[$wid]=0
      fi

    # Passive limit message → parse reset time
    elif printf '%s' "$screen" | grep -qF "You've hit your limit"; then
      if [[ "${resumed[$wid]:-0}" == "0" ]]; then
        reset_line="$(printf '%s' "$screen" | grep -oE "resets [0-9]{1,2}:[0-9]{2}(am|pm)[^)]*\)")"
        parsed="$(parse_reset_time "$reset_line" 2>/dev/null || true)"
        [ -n "$parsed" ] && printf '%s' "$parsed" > "$LIMIT_FILE"
        resumed[$wid]=1
      fi

    else
      # Screen is clear — check if we should resume
      if [[ "${resumed[$wid]:-0}" == "1" ]]; then
        if [ -f "$LIMIT_FILE" ]; then
          reset_epoch="$(cut -d'|' -f1 "$LIMIT_FILE")"
          now="$(date +%s)"
          if [ "$now" -ge "$reset_epoch" ]; then
            krc send-text --match "id:$wid" "please resume where we left off\r" 2>/dev/null
            rm -f "$LIMIT_FILE"
            limit_sent[$wid]=0
            resumed[$wid]=0
          fi
        else
          # Limit file gone (cleared externally), reset state
          limit_sent[$wid]=0
          resumed[$wid]=0
        fi
      fi
    fi
  done

  # Clean up stale limit file
  if [ -f "$LIMIT_FILE" ]; then
    reset_epoch="$(cut -d'|' -f1 "$LIMIT_FILE")"
    [ "$(date +%s)" -ge "$reset_epoch" ] && rm -f "$LIMIT_FILE"
  fi

  sleep "$POLL_INTERVAL"
done
