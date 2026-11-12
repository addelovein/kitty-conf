#!/usr/bin/env bash
# wait-watch.sh — Claude Code PreToolUse hook (Bash tool, async).
#
# Whenever Claude has to wait on a foreground Bash command, show that
# command's live output in a split of the tab's right column.
#
# Claude Code writes a foreground command's output to
#   <tmp>/claude-<uid>/<project>/<session_id>/tasks/<id>.output
# while it runs and deletes it when it finishes. This hook waits
# KITTY_WAIT_AFTER seconds (default 3); if an output file born after the call
# started is still there, the command is still running, so it opens
# wait-view.py on it. Quick commands never get a window.
#
# Skipped: run_in_background calls (Claude isn't waiting), `gh run watch`
# (gh-watch.sh opens a nicer split), no TEMP column. KITTY_WAIT_SPLIT=0
# disables. Never prints to stdout, always exits 0.

set -u
exec >/dev/null 2>>"${TMPDIR:-/tmp}/claude-kitty-agents.err"
[ "${KITTY_WAIT_SPLIT:-1}" = "0" ] && exit 0
[ -n "${KITTY_WINDOW_ID:-}" ] || exit 0
JQ=/usr/bin/jq
KTEMP="$HOME/.config/myconfig/bin/ktemp"
[ -x "$KTEMP" ] || exit 0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat)"
t0=$(( $(date +%s) - 1 ))
[ "$($JQ -r '.tool_input.run_in_background // false' <<<"$payload")" = "true" ] && exit 0
sid="$($JQ -r '.session_id // empty' <<<"$payload")"
cmd="$($JQ -r '.tool_input.command // empty' <<<"$payload")"
desc="$($JQ -r '.tool_input.description // empty' <<<"$payload")"
cwd="$($JQ -r '.cwd // empty' <<<"$payload")"
[ -n "$sid" ] && [ -n "$cmd" ] || exit 0
grep -qE 'gh run watch [0-9]{6,}' <<<"$cmd" && exit 0
"$KTEMP" --id >/dev/null 2>&1 || exit 0

sleep "${KITTY_WAIT_AFTER:-3}"

uid="$(id -u)"
tasks=""
for base in "${CLAUDE_CODE_TMPDIR:-}" /private/tmp /tmp "${TMPDIR%/}"; do
  [ -n "$base" ] || continue
  for d in "$base/claude-$uid"/*/"$sid"/tasks; do
    [ -d "$d" ] && { tasks="$d"; break 2; }
  done
done
[ -n "$tasks" ] || exit 0

STATE="${TMPDIR:-/tmp}/claude-kitty-agents/wait"
mkdir -p "$STATE"
# Newest first: with parallel calls each hook claims one still-running file.
for f in $(ls -t "$tasks"/*.output 2>/dev/null); do
  [ -f "$f" ] && [ ! -L "$f" ] || continue                 # agents are symlinks
  [ "$(stat -f %B "$f" 2>/dev/null || echo 0)" -ge "$t0" ] || continue
  key="$sid-$(basename "$f" .output)"
  mkdir "$STATE/$key" 2>/dev/null || continue               # already shown
  label="${desc:-${cmd%%$'\n'*}}"
  line="$(printf '%q ' /usr/bin/env python3 "$HERE/wait-view.py" "$f" "$desc" "$cmd")"
  (cd "${cwd:-$HOME}" 2>/dev/null || cd "$HOME"; "$KTEMP" --split --no-hold \
     --title "⏳ ${label:0:40}" --var "claude_wait=$key" "$line")
  break
done
# Old claim markers.
find "$STATE" -mindepth 1 -maxdepth 1 -type d -mmin +1440 -exec rmdir {} + 2>/dev/null
exit 0
