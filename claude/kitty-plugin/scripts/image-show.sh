#!/usr/bin/env bash
# image-show.sh — Claude Code hook: show every image Claude looks at or
# refers to, in a split of the tab's right column (kshow), or, with
# KITTY_IMAGE_FLOAT=1, in a floating panel (kfloat). Clicking an image link
# opens the floating panel (kitty/open-actions.conf), not this hook.
#
#   read  PostToolUse on Read: Claude opened an image file → show it now
#   stop  Stop: images in Claude's reply text this turn, shown together:
#         - paths (absolute, ~/ or relative to the session cwd, also inside
#           markdown links) that exist on disk
#         - https URLs ending in an image extension, with no query string or
#           fragment and not to localhost/IP hosts (kfloat downloads them:
#           max 10 MB, 15 s, must really be an image). KITTY_IMAGE_URLS=0
#           turns URLs off.
#
# Each file (path + mtime) or URL is shown once per session, at most
# KITTY_IMAGE_MAX (default 6) per turn. KITTY_IMAGE_SHOW=0 disables.
# Never prints to stdout, always exits 0.

set -u
exec >/dev/null 2>>"${TMPDIR:-/tmp}/claude-kitty-agents.err"
[ "${KITTY_IMAGE_SHOW:-1}" = "0" ] && exit 0
[ -n "${KITTY_WINDOW_ID:-}" ] || exit 0
JQ=/usr/bin/jq
KSHOW="$HOME/.config/myconfig/bin/kshow"
KFLOAT="$HOME/.config/myconfig/bin/kfloat"
if [ "${KITTY_IMAGE_FLOAT:-0}" = "1" ] && [ -x "$KFLOAT" ]; then
  VIEW=("$KFLOAT" --nofocus)
else
  VIEW=("$KSHOW")
fi
[ -x "${VIEW[0]}" ] || exit 0
MODE="${1:-}"
MAX="${KITTY_IMAGE_MAX:-6}"
EXT='png|jpe?g|gif|webp|bmp|tiff?'

payload="$(cat)"
sid="$($JQ -r '.session_id // "nosession"' <<<"$payload")"
cwd="$($JQ -r '.cwd // empty' <<<"$payload")"
STATE="${TMPDIR:-/tmp}/claude-kitty-agents/images/$sid"
mkdir -p "$STATE"

candidates=()
case "$MODE" in
  read)
    p="$($JQ -r '.tool_input.file_path // empty' <<<"$payload")"
    shopt -s nocasematch
    [[ "$p" =~ \.($EXT)$ ]] || exit 0
    shopt -u nocasematch
    candidates+=("$p")
    ;;
  stop)
    tp="$($JQ -r '.transcript_path // empty' <<<"$payload")"
    [ -f "$tp" ] || exit 0
    sleep 0.5   # let the last assistant line reach the transcript
    # Assistant text since the last real user prompt (not tool results).
    text="$(tail -n 400 "$tp" | $JQ -rs '
      (map(.type == "user" and ((.message.content | type) == "string"
            or any(.message.content[]?; .type == "text"))) | rindex(true)) as $u
      | .[(($u // -1) + 1):][]
      | select(.type == "assistant") | .message.content[]?
      | select(.type == "text") | .text' 2>/dev/null)"
    [ -n "$text" ] || exit 0
    while IFS= read -r p; do
      [ -n "$p" ] && candidates+=("$p")
    done < <(grep -oiE "(~|\.{0,2}/)?[A-Za-z0-9_@%+=:,.~/-]*[A-Za-z0-9_-]\.($EXT)\b" <<<"$text" \
               | sed -E 's#^file://##' | grep -vE '^//|://' | awk '!seen[$0]++')
    if [ "${KITTY_IMAGE_URLS:-1}" != "0" ] && [ -x "$KFLOAT" ]; then
      # Whole https tokens; one with ?query or #fragment never ends in .png.
      while IFS= read -r u; do
        u="${u%%[].,;:!\']}"
        host="${u#https://}"; host="${host%%/*}"; host="${host%%:*}"
        shopt -s nocasematch
        [[ "$u" =~ \.($EXT)$ ]] || { shopt -u nocasematch; continue; }
        [[ "$host" =~ ^(localhost|[0-9.]+|\[.*)$ || "$host" == *.local || "$host" == *@* ]] && { shopt -u nocasematch; continue; }
        shopt -u nocasematch
        candidates+=("$u")
      done < <(grep -oE "https://[^[:space:]<>\"'\`()]+" <<<"$text" | awk '!seen[$0]++')
    fi
    ;;
  *) exit 0 ;;
esac

show=()
for p in "${candidates[@]}"; do
  [ "${#show[@]}" -ge "$MAX" ] && break
  case "$p" in
    https://*)
      key="url-$(printf '%s' "$p" | md5 -q)"
      mkdir "$STATE/$key" 2>/dev/null || continue
      if [ "${VIEW[0]}" = "$KFLOAT" ]; then
        show+=("$p")
      else                                   # kshow needs a file: download it
        p="$("$KFLOAT" --fetch "$p" 2>/dev/null)" && [ -f "$p" ] && show+=("$p")
      fi
      continue ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) [ -n "$cwd" ] && p="$cwd/$p" ;;
  esac
  [ -f "$p" ] || continue
  key="$(printf '%s:%s' "$p" "$(stat -f %m "$p" 2>/dev/null)" | md5 -q 2>/dev/null || printf '%s' "$p" | cksum | cut -d' ' -f1)"
  mkdir "$STATE/$key" 2>/dev/null || continue                 # shown already
  show+=("$p")
done
[ "${#show[@]}" -gt 0 ] || exit 0
(cd "${cwd:-$HOME}" 2>/dev/null || cd "$HOME"; "${VIEW[@]}" "${show[@]}")
exit 0
