#!/usr/bin/env bash
# Claude Code status line — account · dir · rate-limits · git · bg
input=$(cat)

# kitty: save the full payload per kitty window for the STATUS pane
# (AddeKitty claude/kitty-plugin/scripts/status-view.py). Atomic write.
if [ -n "${KITTY_WINDOW_ID:-}" ]; then
  _ksd="${TMPDIR:-/tmp}/claude-kitty-status"; mkdir -p "$_ksd" 2>/dev/null
  printf '%s\n' "$input" > "$_ksd/$KITTY_WINDOW_ID.json.$$" 2>/dev/null \
    && mv -f "$_ksd/$KITTY_WINDOW_ID.json.$$" "$_ksd/$KITTY_WINDOW_ID.json" 2>/dev/null
fi

# Cache rate limits per profile so `ai-limits` can read them from any shell (atomic write).
_rl=$(printf '%s' "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
if [ -n "$_rl" ]; then
  _rlf="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rate-limits.json"
  printf '%s\n' "$_rl" > "$_rlf.$$" 2>/dev/null && mv -f "$_rlf.$$" "$_rlf" 2>/dev/null
fi

# ── helpers ──────────────────────────────────────────────────────────────────

# Build a compact 8-char usage bar with colour.
# Usage: make_bar <label> <float_pct>
# Thresholds: green <60, yellow 60-80, red >=80
make_bar() {
  local label="$1"
  local pct_raw="$2"
  local width=10
  local pct_int filled bar="" ch color
  pct_int=$(printf "%.0f" "$pct_raw")
  filled=$(echo "$pct_raw" | awk -v w="$width" '{printf "%d", int($1/100 * w + 0.5)}')
  [ "$filled" -gt "$width" ] && filled=$width
  local f1=(65 71 107 143 179 173 167 131 95 88)
  for i in $(seq 1 $width); do
    if [ "$i" -le "$filled" ]; then
      ch="●"
      color="\033[38;5;${f1[$((i-1))]}m"
    else
      ch="○"
      color="\033[38;5;238m"
    fi
    bar="${bar}$(printf "${color}${ch}\033[0m")"
  done
  printf "%s %s %d%%" "$label" "$bar" "$pct_int"
}

# Format time until a reset timestamp (Unix epoch seconds) as "Xh Ym", "Xd Yh", or "Xm".
fmt_reset() {
  local ts="$1"
  [ -z "$ts" ] && return
  local now diff
  now=$(date -u +%s)
  diff=$(( ts - now ))
  [ "$diff" -le 0 ] && { printf "now"; return; }
  local d=$(( diff / 86400 ))
  local h=$(( (diff % 86400) / 3600 ))
  local m=$(( (diff % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then
    printf "%dd %dh" "$d" "$h"
  elif [ "$h" -gt 0 ]; then
    printf "%dh %dm" "$h" "$m"
  else
    printf "%dm" "$m"
  fi
}

# ── data extraction ───────────────────────────────────────────────────────────

# Account label derived from $CLAUDE_CONFIG_DIR (set by claude-work / claude-personal aliases).
# Falls back to "default" if unset (bare `claude`, which the alias normally blocks).
case "${CLAUDE_CONFIG_DIR:-}" in
  */.claude-work)     account_part=$(printf "\033[33m$(printf '') work\033[0m") ;;    # amber + user icon
  */.claude-personal) account_part=$(printf "\033[96m$(printf '') personal\033[0m") ;; # cyan + user icon
  "")                 account_part=$(printf "\033[90mdefault\033[0m") ;;
  *)                  account_part=$(printf "\033[33m%s\033[0m" "$(basename "${CLAUDE_CONFIG_DIR}")") ;;
esac

# Working directory (basename)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir=$(basename "$cwd")
# If cwd is inside a git repo whose root differs from cwd, show repo name instead
git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$git_root" ] && [ "$git_root" != "$cwd" ]; then
  dir=$(basename "$git_root")
fi

# Model display name
model=$(echo "$input" | jq -r '.model.display_name // empty')
model_part=""
if [ -n "$model" ]; then
  model_part=$(printf "\033[38;5;111m%s\033[0m" "$model")
fi

# Context window usage (pre-calculated field)
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Effort level
effort_level=$(echo "$input" | jq -r '.effort.level // empty')

# Rate limits (only present for Claude.ai subscribers after first response)
five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_reset=$(echo "$input"| jq -r '.rate_limits.seven_day.resets_at // empty')


# Background process count — probe plausible field paths; omit when zero/absent
bg_count=$(echo "$input" | jq -r '
  (.background_tasks
   // .bg_tasks
   // .background_processes
   // .tasks
   // empty)
  | if type == "number" then . else empty end
')

# Git branch + dirty indicator with a per-character truecolor gradient on icon+name.
git_part=""
render_gradient() {
  # render_gradient <r1> <g1> <b1> <r2> <g2> <b2> <text>
  # Emits each char of <text> in a truecolor interpolated from (r1,g1,b1) → (r2,g2,b2).
  local r1=$1 g1=$2 b1=$3 r2=$4 g2=$5 b2=$6 text=$7
  local n=${#text}
  local i ch r g b
  for (( i=0; i<n; i++ )); do
    if (( n > 1 )); then
      r=$(( r1 + (r2 - r1) * i / (n - 1) ))
      g=$(( g1 + (g2 - g1) * i / (n - 1) ))
      b=$(( b1 + (b2 - b1) * i / (n - 1) ))
    else
      r=$r1 g=$g1 b=$b1
    fi
    ch="${text:$i:1}"
    printf "\033[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "$ch"
  done
  printf "\033[0m"
}
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | head -1)
    suffix=""
    [ -n "$dirty" ] && suffix="*"
    label=" ${branch}${suffix}"
    case "$branch" in
      main|master)         git_part=$(render_gradient  255  80  80   80   0   0 "$label") ;;
      develop|development) git_part=$(render_gradient    80 255 120    0  60 200 "$label") ;;
      *)                   git_part=$(render_gradient 255 230  80  140  80   0 "$label") ;;
    esac
  fi
fi

# ── build parts ───────────────────────────────────────────────────────────────

if [ -n "$ctx_pct" ]; then
  ctx_int=$(printf "%.0f" "$ctx_pct")
  ctx_filled=$(echo "$ctx_pct" | awk '{printf "%d", int($1/10 + 0.5)}')
  [ "$ctx_filled" -gt 10 ] && ctx_filled=10
  ctx_bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$ctx_filled" ]; then
      ch="●"
      case "$i" in
        1|2)  color="\033[38;5;153m" ;;
        3|4)  color="\033[38;5;159m" ;;
        5|6)  color="\033[38;5;195m" ;;
        7|8)  color="\033[38;5;231m" ;;
        9|10) color="\033[97m"       ;;
      esac
    else
      ch="○"
      color="\033[38;5;238m"
    fi
    ctx_bar="${ctx_bar}$(printf "${color}${ch}\033[0m")"
  done
  ctx_part="ctx ${ctx_bar} ${ctx_int}%"
else
  ctx_part="ctx --"
fi

# 5-hour session limit bar
five_part=""
if [ -n "$five_pct" ] && [ "$(printf "%.0f" "$five_pct")" -gt 0 ]; then
  five_part=$(make_bar "5h" "$five_pct")
  five_eta=$(fmt_reset "$five_reset")
  [ -n "$five_eta" ] && five_part="${five_part} ↺${five_eta}"
fi

# 7-day weekly limit bar
seven_part=""
if [ -n "$seven_pct" ] && [ "$(printf "%.0f" "$seven_pct")" -gt 0 ]; then
  seven_part=$(make_bar "7d" "$seven_pct")
  seven_eta=$(fmt_reset "$seven_reset")
  [ -n "$seven_eta" ] && seven_part="${seven_part} ↺${seven_eta}"
fi

# ── assemble ──────────────────────────────────────────────────────────────────

append_part() {
  local part="$1"
  [ -z "$part" ] && return
  if [ -n "$line" ]; then
    line="${line} · ${part}"
  else
    line="${part}"
  fi
}

line=""

# account (work / personal / default)
append_part "$account_part"

# dir — folder icon blue, text gradient blue→white
if [ -n "$dir" ]; then
  dir_blues=(75 81 117 153 159 195 189 231 255 231)
  dir_len=${#dir}
  dir_colored=""
  for j in $(seq 1 $dir_len); do
    dir_ch="${dir:$((j-1)):1}"
    dir_idx=$(( (j - 1) * 9 / (dir_len > 1 ? dir_len - 1 : 1) ))
    [ "$dir_idx" -gt 9 ] && dir_idx=9
    dir_colored="${dir_colored}$(printf "[38;5;${dir_blues[$dir_idx]}m${dir_ch}[0m")"
  done
  append_part "$(printf "[38;5;75m󰉋[0m") ${dir_colored}"
fi

append_part "$five_part"
append_part "$seven_part"
append_part "$git_part"

# background process count — only shown when > 0
if [ -n "$bg_count" ] && [ "$bg_count" -gt 0 ] 2>/dev/null; then
  append_part "bg:${bg_count}"
fi

printf "%b" "$line"

# ── row 2: kitty watchers ─────────────────────────────────────────────────────
line2=""

# full-auto indicator — render red when watcher is running AND this window is not paused.
# "paused" = sticky banner latch from claude-approve.sh (shift-tab mode visible).
if [ -f "/tmp/claude-approve.pid" ] && kill -0 "$(cat /tmp/claude-approve.pid)" 2>/dev/null; then
  fa_state="active"
  if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -f "/tmp/claude-fullauto-status.${KITTY_WINDOW_ID}" ]; then
    fa_state="$(cat "/tmp/claude-fullauto-status.${KITTY_WINDOW_ID}" 2>/dev/null)"
  fi
  if [ "$fa_state" != "paused" ]; then
    line2="$(printf "\033[33m\033[31m full-auto\033[0m")"
  fi
fi

# rate-limit / auto-resume indicator
if [ -f "/tmp/claude-limit.txt" ]; then
  reset_epoch="$(cut -d'|' -f1 /tmp/claude-limit.txt)"
  now="$(date +%s)"
  remaining=$(( reset_epoch - now ))
  if [ "$remaining" -gt 0 ]; then
    h=$(( remaining / 3600 ))
    m=$(( (remaining % 3600) / 60 ))
    [ "$h" -gt 0 ] && timer_str="${h}h ${m}m" || timer_str="${m}m"
    [ -n "$line2" ] && line2="${line2}  "
    line2="${line2}$(printf "\033[33mauto-resume ↺%s\033[0m" "$timer_str")"
  fi
fi

# model + effort at end of row 2
if [ -n "$model" ]; then
  [ -n "$line2" ] && line2="${line2}  "
  line2="${line2}${model}"
fi

if [ -n "$effort_level" ]; then
  case "$effort_level" in
    low)    effort_filled=1; effort_color="\033[90m" ;;
    medium) effort_filled=2; effort_color="\033[90m" ;;
    high)   effort_filled=3; effort_color="\033[90m" ;;
    xhigh)  effort_filled=4; effort_color="\033[90m" ;;
    max)    effort_filled=5; effort_color="\033[90m" ;;
    *)      effort_filled=0; effort_color="\033[90m" ;;
  esac
  vbars=("▁" "▂" "▄" "▅" "▆" "█")
  effort_bar=""
  for i in 1 2 3 4 5; do
    if [ "$i" -le "$effort_filled" ]; then
      effort_bar="${effort_bar}$(printf "${effort_color}${vbars[$i]}\033[0m")"
    else
      effort_bar="${effort_bar}$(printf "\033[38;5;238m▁\033[0m")"
    fi
  done
  effort_part="$(printf "\033[0m")effort ${effort_bar}"
  [ -n "$line2" ] && line2="${line2}  "
  line2="${line2}${effort_part}"
fi

# ctx bar at end of row 2
if [ -n "$ctx_part" ]; then
  [ -n "$line2" ] && line2="${line2}  "
  line2="${line2}${ctx_part}"
fi

[ -n "$line2" ] && printf "\n%b" "$line2"
