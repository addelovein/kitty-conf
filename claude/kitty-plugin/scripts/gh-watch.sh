#!/usr/bin/env bash
# gh-watch.sh — Claude Code PreToolUse/PostToolUse hook (Bash tool).
#
# When Claude starts or watches a GitHub Actions run, open a split in the
# tab's right column that runs `gh run watch <id>` for the user to follow
# live. Read-only mirror: Claude's own command and output are untouched.
#
#   pre   `gh run watch <id>` about to run: watch that id
#   post  `gh workflow run …` finished: watch the run ids/URLs in its output,
#         or, when it printed none, the newest run of that workflow
#
# One split per run id (window var claude_run=<id>). Needs the column's TEMP
# window (ktemp --id). KITTY_GH_WATCH=0 disables. Never prints to stdout,
# always exits 0.

set -u
exec >/dev/null 2>>"${TMPDIR:-/tmp}/claude-kitty-agents.err"
[ "${KITTY_GH_WATCH:-1}" = "0" ] && exit 0
[ -n "${KITTY_WINDOW_ID:-}" ] || exit 0
MODE="${1:-}"
JQ=/usr/bin/jq
KITTEN="/Applications/kitty.app/Contents/MacOS/kitten"
command -v "$KITTEN" >/dev/null 2>&1 || KITTEN="$(command -v kitten)" || exit 0
KTEMP="$HOME/.config/myconfig/bin/ktemp"
[ -x "$KTEMP" ] || exit 0
command -v gh >/dev/null 2>&1 || exit 0

payload="$(cat)"
cmd="$($JQ -r '.tool_input.command // empty' <<<"$payload")"
cwd="$($JQ -r '.cwd // empty' <<<"$payload")"
case "$cmd" in *"gh "*) ;; *) exit 0 ;; esac
"$KTEMP" --id >/dev/null 2>&1 || exit 0

# `-R owner/repo` / `--repo owner/repo` in Claude's command, if any.
repo="$(grep -oE -- '(-R|--repo)[ =][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' <<<"$cmd" | head -1 | sed -E 's/^(-R|--repo)[ =]//')"

ids=()
case "$MODE" in
  pre)
    while read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(
      grep -oE 'gh run watch[^|;&]*' <<<"$cmd" | grep -oE '[0-9]{6,}' | sort -u)
    ;;
  post)
    grep -q 'gh workflow run' <<<"$cmd" || exit 0
    out="$($JQ -r '.tool_response | tostring' <<<"$payload")"
    while read -r url; do
      [ -n "$url" ] || continue
      ids+=("${url##*/}")
      [ -n "$repo" ] || repo="$(sed -E 's#https://github.com/([^/]+/[^/]+)/.*#\1#' <<<"$url")"
    done < <(grep -oE 'https://github.com/[^/ "]+/[^/ "]+/actions/runs/[0-9]+' <<<"$out" | sort -u)
    if [ "${#ids[@]}" -eq 0 ]; then
      # Older gh prints no URL: take the newest run of that workflow.
      wf="$(grep -oE 'gh workflow run [^ ;&|]+' <<<"$cmd" | head -1 | awk '{print $4}')"
      [ -n "$wf" ] || exit 0
      sleep 4
      id="$(cd "${cwd:-.}" && gh run list ${repo:+-R "$repo"} --workflow "$wf" -L 1 \
              --json databaseId -q '.[0].databaseId' 2>/dev/null)"
      [ -n "$id" ] && ids+=("$id")
    fi
    ;;
  *) exit 0 ;;
esac
[ "${#ids[@]}" -gt 0 ] || exit 0

# Skip ids that already have a split in this tab.
open_ids="$("$KITTEN" @ ls --match-tab "window_id:$KITTY_WINDOW_ID" 2>/dev/null \
  | $JQ -r '.[].tabs[].windows[].user_vars.claude_run // empty')"

for id in "${ids[@]}"; do
  grep -qx "$id" <<<"$open_ids" && continue
  name="$(cd "${cwd:-.}" && gh run view "$id" ${repo:+-R "$repo"} --json workflowName -q .workflowName 2>/dev/null)"
  line="GH_NO_UPDATE_NOTIFIER=1 gh run watch $id ${repo:+-R $repo} --exit-status"
  (cd "${cwd:-$HOME}" && "$KTEMP" --split --title "▶ ${name:-GH run} #$id" --var "claude_run=$id" "$line")
  open_ids="$open_ids"$'\n'"$id"
done
exit 0
