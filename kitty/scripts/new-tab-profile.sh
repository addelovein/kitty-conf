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
  # If kitty launched us with remote control enabled, prefer that.
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

focused_title="$(printf '%s' "$json" | jq -r '[.[] | .tabs[] | select(.is_focused == true)] | .[0].title // ""')"
focused_window_title="$(printf '%s' "$json" | jq -r '[.[] | .tabs[] | select(.is_focused == true) | .windows[] | select(.is_focused == true)] | .[0].title // ""')"
focused_cwd="$(printf '%s' "$json" | jq -r '[.[] | .tabs[] | select(.is_focused == true) | .windows[] | select(.is_focused == true)] | .[0].cwd // ""')"
[ -z "$focused_window_title" ] && focused_window_title="shell"

path_title_from_cwd() {
  local cwd="$1"
  local home="$HOME"
  local rel=""
  local parent=""
  local base=""
  [ -n "$cwd" ] || { printf 'shell\n'; return; }
  if [ "$cwd" = "$home" ]; then
    printf '~\n'
    return
  fi
  if [[ "$cwd" == "$home/"* ]]; then
    rel="${cwd#$home/}"
    parent="${rel%/*}"
    base="${rel##*/}"
    if [ "$parent" = "$rel" ]; then
      printf '~/%s\n' "$base"
    else
      printf '~/%s/%s\n' "${parent##*/}" "$base"
    fi
    return
  fi
  parent="${cwd%/*}"
  base="${cwd##*/}"
  if [ "$parent" = "$cwd" ]; then
    printf '%s\n' "$base"
  else
    printf '%s/%s\n' "${parent##*/}" "$base"
  fi
}

tab_title_to_use="$focused_window_title"
if [[ "$tab_title_to_use" =~ ^row[12]-col[1-5]$ ]]; then
  tab_title_to_use="$(path_title_from_cwd "$focused_cwd")"
fi

create_colored_tab() {
  local win_title="$1"
  local active_bg="$2"
  local active_fg="$3"
  local inactive_bg="$4"
  local inactive_fg="$5"
  local border_active="$6"
  local border_inactive="$7"
  local win_id=""
  local tab_id=""

  # Do not pin tab-title; let Kitty derive tab title from active window title.
  win_id="$(krc launch --type=tab --title "$win_title" "$BASH_BIN" 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  [[ "$win_id" =~ ^[0-9]+$ ]] || return 1

  tab_id="$(krc ls 2>/dev/null | jq -r --argjson wid "$win_id" '.[] | .tabs[] | select([.windows[].id] | index($wid)) | .id' | head -n1)"
  if [[ "$tab_id" =~ ^[0-9]+$ ]]; then
    krc set-tab-color --match "id:$tab_id" \
      "active_bg=$active_bg" \
      "active_fg=$active_fg" \
      "inactive_bg=$inactive_bg" \
      "inactive_fg=$inactive_fg" >/dev/null 2>&1
    krc set-colors \
      --match-tab "id:$tab_id" \
      "active_border_color=$border_active" \
      "inactive_border_color=$border_inactive" >/dev/null 2>&1
  fi
}

case "$focused_title" in
  Blue)
    create_colored_tab "$tab_title_to_use" "#1d4f8a" "#e3f0ff" "#15283d" "#a8bfd9" "#62d6ff" "#1f2a36"
    ;;
  Green)
    create_colored_tab "$tab_title_to_use" "#1e6b46" "#dfffe9" "#163726" "#a9d6b8" "#56c98a" "#224734"
    ;;
  *)
    # Gray/default tabs keep regular shell behavior; set initial window title only.
    krc launch --type=tab --title "$tab_title_to_use" >/dev/null 2>&1
    ;;
esac
