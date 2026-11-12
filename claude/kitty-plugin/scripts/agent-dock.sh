#!/usr/bin/env bash
# agent-dock.sh start|stop — Claude Code SubagentStart/SubagentStop hook.
#
# start: opens a kitty window that live-renders the subagent's transcript, in a
#        strip below the Claude window that spawned it (splits layout). More
#        agents split the strip side by side. If the tab is not in the splits
#        layout, or KITTY_AGENT_MAX_STRIP windows are already in the strip: a
#        window in a shared "Agents" tab (grid layout).
# stop:  marks the window finished and closes it after KITTY_AGENT_LINGER seconds
#        (0 = leave it open).
#
# Tunables (env): KITTY_AGENT_WINDOWS=0 disables everything,
#   KITTY_AGENT_STRIP_SIZE (strip height in %, default 30),
#   KITTY_AGENT_MAX_STRIP (default 4), KITTY_AGENT_LINGER (default 8),
#   KITTY_AGENT_DEBUG=1 logs payloads.
#
# Must never print to stdout (hook output can leak into the conversation) and
# must always exit 0 so it never disturbs Claude.

set -u
exec >/dev/null 2>>"${TMPDIR:-/tmp}/claude-kitty-agents.err"

MODE="${1:-}"
[ "${KITTY_AGENT_WINDOWS:-1}" = "0" ] && exit 0
[ -n "${KITTY_WINDOW_ID:-}" ] || exit 0            # not running inside kitty

KITTEN="/Applications/kitty.app/Contents/MacOS/kitten"
command -v "$KITTEN" >/dev/null 2>&1 || KITTEN="$(command -v kitten)" || exit 0
STATE="${TMPDIR:-/tmp}/claude-kitty-agents"
mkdir -p "$STATE"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD="$(cat)"
[ "${KITTY_AGENT_DEBUG:-0}" = "1" ] && {
  printf '%s %s %s\n' "$(date +%T)" "$MODE" "$PAYLOAD"
  env | grep -E '^(KITTY_WINDOW_ID|KITTY_LISTEN_ON|TERM)=' | sed 's/^/    /'
} >>"$STATE/debug.log"

j() { printf '%s' "$PAYLOAD" | /usr/bin/jq -r "$1 // empty" 2>/dev/null; }
AGENT_ID="$(j .agent_id)"; AGENT_ID="${AGENT_ID#agent-}"
AGENT_TYPE="$(j .agent_type)"
[ -n "$AGENT_ID" ] || exit 0
# Internal helper agents (prompt suggestions, /btw) have an empty type: skip.
[ -n "$AGENT_TYPE" ] || exit 0

rc() { "$KITTEN" @ "$@"; }
SHORT="${AGENT_ID:0:7}"

case "$MODE" in
start)
  SESSION="$(j .session_id)"
  TRANSCRIPT="$(j .transcript_path)"
  [ -n "$SESSION" ] && [ -n "$TRANSCRIPT" ] || exit 0
  AGENT_FILE="$(dirname "$TRANSCRIPT")/$SESSION/subagents/agent-$AGENT_ID.jsonl"
  TITLE="⚙ $AGENT_TYPE · $SHORT"
  OWNER="$KITTY_WINDOW_ID"
  CWD="$(j .cwd)"; [ -d "$CWD" ] || CWD=current
  VIEW=(/usr/bin/env python3 "$HERE/agent-view.py" "$AGENT_FILE" "$AGENT_TYPE")
  COMMON=(--keep-focus --title "$TITLE" --var "claude_agent=$AGENT_ID"
          --var "claude_agent_owner=$OWNER" --cwd "$CWD")

  # Parallel subagents start at the same instant: serialize per Claude window,
  # or every hook sees an empty strip and makes its own row. mkdir is atomic;
  # a lock older than ~5 s is treated as stale.
  LOCK="$STATE/.lock-$OWNER"
  got=""
  for _ in $(seq 1 50); do mkdir "$LOCK" 2>/dev/null && { got=1; break; }; sleep 0.1; done
  [ -n "$got" ] || { rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null; }
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT

  # Bottom strip (needs the tab in the splits layout): the first agent is an
  # hsplit below the Claude window; each further agent splits the widest strip
  # window side by side. jq prints "count widest-id layout".
  read -r n widest layout < <(rc ls --match-tab "window_id:$OWNER" 2>/dev/null | /usr/bin/jq -r --arg o "$OWNER" '
      [.[].tabs[]][0] as $t
      | [$t.windows[] | select(.user_vars.claude_agent_owner == $o and .user_vars.claude_agent_kind == "strip")]
      | sort_by(-.columns)
      | "\(length) \(.[0].id // "-") \($t.layout)"' 2>/dev/null)
  WID=""
  if [ "${layout:-}" = "splits" ] && [ "${n:-0}" -lt "${KITTY_AGENT_MAX_STRIP:-4}" ]; then
    if [ "${widest:--}" = "-" ]; then
      WID="$(rc launch --match "window_id:$OWNER" --next-to "id:$OWNER" --type=window \
              --location=hsplit --bias="${KITTY_AGENT_STRIP_SIZE:-30}" \
              --var claude_agent_kind=strip "${COMMON[@]}" "${VIEW[@]}" 2>/dev/null)"
    else
      WID="$(rc launch --match "window_id:$widest" --next-to "id:$widest" --type=window \
              --location=vsplit --var claude_agent_kind=strip "${COMMON[@]}" "${VIEW[@]}" 2>/dev/null)"
    fi
  fi
  if ! [[ "$WID" =~ ^[0-9]+$ ]]; then
    # Shared "Agents" tab in the same OS window, grid layout.
    anchor="$(rc ls --match "var:claude_agent_kind=tab" 2>/dev/null \
              | /usr/bin/jq -r '[.[].tabs[].windows[].id][0] // empty' 2>/dev/null)"
    if [ -n "$anchor" ]; then
      WID="$(rc launch --match "window_id:$anchor" --type=window --var claude_agent_kind=tab \
              "${COMMON[@]}" "${VIEW[@]}")"
    else
      WID="$(rc launch --match "window_id:$OWNER" --type=tab --tab-title "Agents" \
              --var claude_agent_kind=tab "${COMMON[@]}" "${VIEW[@]}")"
      [[ "$WID" =~ ^[0-9]+$ ]] && rc goto-layout --match "id:$WID" grid
    fi
  fi
  [[ "$WID" =~ ^[0-9]+$ ]] && printf '%s\n' "$WID" >"$STATE/$AGENT_ID"
  ;;
stop)
  WID="$(cat "$STATE/$AGENT_ID" 2>/dev/null)"; rm -f "$STATE/$AGENT_ID"
  [ -n "$WID" ] || exit 0
  rc set-window-title --match "id:$WID" "✔ $AGENT_TYPE · $SHORT"
  LINGER="${KITTY_AGENT_LINGER:-8}"
  if [ "$LINGER" != "0" ]; then
    nohup sh -c "sleep $LINGER; '$KITTEN' @ close-window --match id:$WID --ignore-no-match" \
      >/dev/null 2>&1 </dev/null &
  fi
  ;;
esac
exit 0
