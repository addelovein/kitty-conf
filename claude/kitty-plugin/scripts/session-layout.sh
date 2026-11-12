#!/usr/bin/env bash
# session-layout.sh — Claude Code SessionStart hook.
#
# Gives the kitty TAB Claude runs in one right-hand column, shared by every
# Claude session in that tab:
#   STATUS (top)    all sessions in the tab + their subagents (status-view.py)
#   TEMP   (bottom) a shell that `kshow` and `ktemp` use for images, deploy
#                   watches and other short-lived output
# Windows are tagged with user var claude_role=status|temp (plus
# claude_role_owner = the Claude window that created them). A second session
# in the same tab, or a resumed/cleared one, reuses them. Needs the tab in the
# splits layout.
#
# Tunables (env): KITTY_CLAUDE_LAYOUT=0 disables, KITTY_CLAUDE_COL (column
#   width in %, default 30), KITTY_CLAUDE_STATUS_LINES (default 12).
#
# Must never print to stdout (SessionStart stdout goes into Claude's context)
# and must always exit 0.

set -u
exec >/dev/null 2>>"${TMPDIR:-/tmp}/claude-kitty-agents.err"

[ "${KITTY_CLAUDE_LAYOUT:-1}" = "0" ] && exit 0
[ -n "${KITTY_WINDOW_ID:-}" ] || exit 0
cat >/dev/null 2>&1 || true            # drain the hook payload

KITTEN="/Applications/kitty.app/Contents/MacOS/kitten"
command -v "$KITTEN" >/dev/null 2>&1 || KITTEN="$(command -v kitten)" || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="$KITTY_WINDOW_ID"
rc() { "$KITTEN" @ "$@"; }

# Skip non-interactive runs (claude -p / --print): find the claude process.
pid=$PPID
for _ in 1 2 3 4 5 6; do
  args="$(ps -o args= -p "$pid" 2>/dev/null)" || break
  case " $args " in *" -p "*|*" --print "*) exit 0 ;; esac
  case "$args" in *claude*) break ;; esac
  pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  [ -n "$pid" ] && [ "$pid" != "1" ] || break
done

STATE="${TMPDIR:-/tmp}/claude-kitty-agents"
mkdir -p "$STATE"
LOCK="$STATE/.lock-layout"            # two sessions starting in one tab
got=""
for _ in $(seq 1 50); do mkdir "$LOCK" 2>/dev/null && { got=1; break; }; sleep 0.1; done
[ -n "$got" ] || { rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

TAB="$(rc ls --match-tab "window_id:$OWNER" 2>/dev/null)" || exit 0
layout="$(printf '%s' "$TAB" | /usr/bin/jq -r '[.[].tabs[]][0].layout // empty')"
[ "$layout" = "splits" ] || exit 0
role_id() {
  printf '%s' "$TAB" | /usr/bin/jq -r --arg r "$1" \
    '[.[].tabs[].windows[] | select(.user_vars.claude_role == $r) | .id][0] // empty'
}
status_id="$(role_id status)"
temp_id="$(role_id temp)"
[ -n "$status_id" ] && [ -n "$temp_id" ] && exit 0

CWD="$(pwd)"
COL="${KITTY_CLAUDE_COL:-30}"
# Height of the Claude window, to size STATUS in lines.
lines="$(printf '%s' "$TAB" | /usr/bin/jq -r --arg o "$OWNER" '[.[].tabs[].windows[] | select((.id|tostring) == $o) | .lines][0] // 60')"
status_lines="${KITTY_CLAUDE_STATUS_LINES:-12}"
temp_bias=$(( 100 - (status_lines * 100 / (lines > 0 ? lines : 60)) ))
[ "$temp_bias" -lt 50 ] && temp_bias=50
[ "$temp_bias" -gt 95 ] && temp_bias=95

common=(--type=window --keep-focus --cwd "$CWD" --var "claude_role_owner=$OWNER")
status_cmd=(/usr/bin/env python3 "$HERE/status-view.py")

if [ -z "$status_id" ] && [ -z "$temp_id" ]; then
  status_id="$(rc launch --match "window_id:$OWNER" --next-to "id:$OWNER" --location=vsplit \
      --bias="$COL" --title STATUS --var claude_role=status "${common[@]}" "${status_cmd[@]}")"
  [[ "$status_id" =~ ^[0-9]+$ ]] || exit 0
  rc launch --match "window_id:$status_id" --next-to "id:$status_id" --location=hsplit \
      --bias="$temp_bias" --title TEMP --var claude_role=temp "${common[@]}" >/dev/null
elif [ -z "$status_id" ]; then
  # hsplit puts STATUS below TEMP. Launch it with TEMP's share, then rotate
  # that pair 180° (sizes stay with positions): STATUS small on top. The
  # layout action works on the focused window, so focus it for a moment.
  sid="$(rc launch --match "window_id:$temp_id" --next-to "id:$temp_id" --location=hsplit \
      --bias="$temp_bias" --title STATUS --var claude_role=status "${common[@]}" "${status_cmd[@]}")"
  if [[ "$sid" =~ ^[0-9]+$ ]]; then
    rc focus-window --match "id:$sid" && rc action --match "id:$sid" layout_action rotate 180
    rc focus-window --match "id:$OWNER"
  fi
else
  rc launch --match "window_id:$status_id" --next-to "id:$status_id" --location=hsplit \
      --bias="$temp_bias" --title TEMP --var claude_role=temp "${common[@]}" >/dev/null
fi
exit 0
