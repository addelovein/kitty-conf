#!/bin/zsh
# Watcher: auto-Yes Claude Code "Do you want to proceed?" prompts.
#
# Rule: when a shift-tab mode banner (⏵⏵ accept edits / ⏸ plan / ⏵⏵ auto)
# is visible in a window, this watcher MUST NOT press Yes there. The banner
# is the off-switch for full-auto.
#
# The challenge: kitty's `get-text --extent screen` races with Claude's
# redraws. The banner can briefly disappear from the visible viewport mid-
# render even though it's still on. To close that race we use a sticky
# latch: once a banner is seen in a window, we hold "paused" for a generous
# timeout AFTER the banner stops being detected. The user toggling accept-
# edits off cannot also produce a new Yes/No prompt within the latch window,
# so this catches the race without sacrificing safety.
set -u

KITTY_BIN="/Applications/kitty.app/Contents/MacOS/kitty"
POLL_INTERVAL=1
PIDFILE="/tmp/claude-approve.pid"
STATUS_PREFIX="/tmp/claude-fullauto-status"  # per-window: active|paused
PAUSE_HOLD_SECONDS=0  # no sticky latch — resume immediately when banner gone (accepts redraw race)

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

printf '%s' "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

krc() {
  local t
  t="$(resolve_target)" || return 1
  "$KITTY_BIN" @ --to "$t" "$@"
}

typeset -A approved          # hash of the last prompt we successfully pressed Yes on (empty = nothing approved yet)
typeset -A blocked
typeset -A last_banner_ts    # epoch seconds of last banner sighting per window
typeset -A logged_paused     # whether we've logged the PAUSED state already

# Returns 0 if any ⏵⏵ or ⏸ glyph is in the input string. Used against
# kitty's --extent screen capture.
has_banner_glyph() {
  printf '%s' "$1" | grep -qE '⏵⏵|⏸'
}

is_dangerous_screen() {
  local s="$1"
  printf '%s' "$s" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)[a-zA-Z]*[[:space:]]+(/|~|\$HOME|\.|\*)([[:space:]]|$)' && return 0
  printf '%s' "$s" | grep -qE 'find[[:space:]]+[^|]*-delete([[:space:]]|$)' && return 0
  printf '%s' "$s" | grep -qE '(^|[[:space:]])dd[[:space:]]+[a-z=/[:space:]]*if=' && return 0
  printf '%s' "$s" | grep -qE '(^|[[:space:]])mkfs(\.|[[:space:]])' && return 0
  printf '%s' "$s" | grep -qE 'diskutil[[:space:]]+(erase|eraseDisk|eraseVolume|secureErase)' && return 0
  printf '%s' "$s" | grep -qE '>[[:space:]]*/dev/(sd|nvme|disk|rdisk)' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+push[[:space:]][^&|;]*(--force|--force-with-lease|-f)[^&|;]*(main|master)' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+push[[:space:]][^&|;]*(main|master)[^&|;]*(--force|--force-with-lease|-f)' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*x' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*x[a-zA-Z]*d' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+branch[[:space:]]+-D[[:space:]]+(main|master)([[:space:]]|$)' && return 0
  printf '%s' "$s" | grep -qE 'git[[:space:]]+filter-(branch|repo)' && return 0
  return 1
}

write_status() {
  local wid="$1" state="$2" f="$STATUS_PREFIX.$1"
  [ -f "$f" ] && [ "$(cat "$f" 2>/dev/null)" = "$state" ] && return 0
  printf '%s' "$state" > "$f"
}

while true; do
  window_ids=("${(@f)$(krc ls 2>/dev/null | jq -r '.[] | .tabs[] | .windows[] | .id' 2>/dev/null)}")
  now=$(date +%s)

  for wid in "${window_ids[@]}"; do
    [[ -z "$wid" || -n "${wid//[0-9]/}" ]] && continue
    screen="$(krc get-text --match "id:$wid" --extent screen 2>/dev/null)" || continue

    # Banner visible right now → pause this window immediately, no latch needed.
    # Banner gone → flip back to active immediately (within PAUSE_HOLD_SECONDS if >0).
    banner_now=0
    if has_banner_glyph "$screen"; then
      banner_now=1
      last_banner_ts[$wid]=$now
    fi

    last_ts="${last_banner_ts[$wid]:-0}"
    pause_active=0
    if [ "$banner_now" = "1" ]; then
      pause_active=1
    elif [ "$last_ts" -gt 0 ] && [ "$PAUSE_HOLD_SECONDS" -gt 0 ] && [ $(( now - last_ts )) -lt "$PAUSE_HOLD_SECONDS" ]; then
      pause_active=1
    fi

    if [ "$pause_active" = "1" ]; then
      if [[ "${logged_paused[$wid]:-0}" == "0" ]]; then
        printf '[%s] PAUSED  wid=%s — banner detected\n' \
          "$(date '+%Y-%m-%d %H:%M:%S')" "$wid" >&2
        logged_paused[$wid]=1
      fi
      write_status "$wid" paused
      approved[$wid]=0
      blocked[$wid]=0
      continue
    fi

    if [[ "${logged_paused[$wid]:-0}" == "1" ]]; then
      printf '[%s] RESUMED wid=%s — banner cleared\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$wid" >&2
      logged_paused[$wid]=0
    fi
    write_status "$wid" active

    # Look for "❯ 1." / "2." menu shape; if found, find which line has Yes.
    yes_choice=""
    if printf '%s' "$screen" | grep -qE '❯[[:space:]]+[0-9]+\.'; then
      yes_choice="$(printf '%s' "$screen" \
        | grep -E '^[[:space:]]*(❯[[:space:]]+)?[0-9]+\.' \
        | grep -i 'Yes' \
        | grep -oE '[0-9]+' | head -1)"
    fi

    if [ -n "$yes_choice" ]; then
      # Hash the prompt-area lines so we can tell a new prompt from the one we
      # already approved. The "Do you want to proceed?" line plus the menu is
      # specific to this prompt; using just those lines avoids cursor/spinner
      # noise elsewhere on screen.
      prompt_hash="$(printf '%s' "$screen" \
        | grep -E 'Do you want to|❯[[:space:]]+[0-9]+\.|^[[:space:]]*[0-9]+\.[[:space:]]' \
        | shasum -a 1 | cut -d' ' -f1)"

      # Final pre-press guard: re-fetch screen and bail if banner appeared.
      recheck="$(krc get-text --match "id:$wid" --extent screen 2>/dev/null)" || recheck="$screen"
      if has_banner_glyph "$recheck"; then
        last_banner_ts[$wid]=$now
        write_status "$wid" paused
        continue
      fi
      if is_dangerous_screen "$screen"; then
        if [[ "${blocked[$wid]:-0}" == "0" ]]; then
          printf '[%s] BLOCKED wid=%s — dangerous command detected\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$wid" >&2
          blocked[$wid]=1
        fi
      elif [[ "${approved[$wid]:-}" != "$prompt_hash" ]]; then
        if krc send-text --match "id:$wid" "${yes_choice}\r" 2>/dev/null; then
          approved[$wid]="$prompt_hash"
          blocked[$wid]=0
        fi
      fi
    else
      blocked[$wid]=0
    fi
  done

  # Clean up status files for windows that no longer exist.
  setopt NULL_GLOB
  for f in "$STATUS_PREFIX".*; do
    wid="${f##*.}"
    [[ -z "$wid" || -n "${wid//[0-9]/}" ]] && continue
    if ! printf '%s\n' "${window_ids[@]}" | grep -qxF "$wid"; then
      rm -f "$f"
      unset 'last_banner_ts[$wid]' 'logged_paused[$wid]' 'approved[$wid]' 'blocked[$wid]' 2>/dev/null
    fi
  done
  unsetopt NULL_GLOB

  sleep "$POLL_INTERVAL"
done
