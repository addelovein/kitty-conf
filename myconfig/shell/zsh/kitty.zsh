# Kitty workflow helpers (SSH/notify/quick-access)
export PATH="/Applications/kitty.app/Contents/MacOS:$PATH"

# Auto-start claude-resume watcher once per Kitty instance
if [ -n "${KITTY_WINDOW_ID:-}" ]; then
  _resume_script="${HOME}/.config/kitty/scripts/claude-resume.sh"
  _resume_pid="/tmp/claude-resume.pid"
  if [ -x "$_resume_script" ]; then
    if ! { [ -f "$_resume_pid" ] && kill -0 "$(cat "$_resume_pid")" 2>/dev/null; }; then
      "$_resume_script" &>/dev/null &
      disown
    fi
  fi
  unset _resume_script _resume_pid
fi
export KITTY_BIN="/Applications/kitty.app/Contents/MacOS/kitty"
export KITTEN_BIN="/Applications/kitty.app/Contents/MacOS/kitten"
export KITTY_LISTEN_ON="unix:/tmp/kitty-main"
# Keep terminal title ownership in our custom hook for stable branch titles.
export DISABLE_AUTO_TITLE=true

# Keep kitty window/tab titles synced to current directory in zsh tabs.
autoload -Uz add-zsh-hook
_kitty_zsh_git_branch() {
  local branch
  branch="$(command git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return
  [[ "$branch" = "HEAD" ]] && return
  printf '%s' "$branch"
}
_kitty_set_zsh_title() {
  local branch title
  branch="$(_kitty_zsh_git_branch)"
  title="%~"
  [[ -n "$branch" ]] && title="${title}   ${branch}"
  print -Pn "\e]2;${title}\a"
}
add-zsh-hook -D precmd _kitty_set_zsh_title 2>/dev/null
add-zsh-hook -D chpwd _kitty_set_zsh_title 2>/dev/null
add-zsh-hook precmd _kitty_set_zsh_title
add-zsh-hook chpwd _kitty_set_zsh_title

# Pick a live kitty socket from existing instances.
kpick_socket() {
  local s n focused best="" best_n=-1
  for s in /tmp/kitty-main*; do
    [ -S "$s" ] || continue
    focused="$("$KITTY_BIN" @ --to "unix:$s" ls 2>/dev/null | jq -r 'any(.[]; .is_focused==true)' 2>/dev/null)"
    if [ "$focused" = "true" ]; then
      printf '%s\n' "$s"
      return 0
    fi
    n="$("$KITTY_BIN" @ --to "unix:$s" ls 2>/dev/null | jq -r '[.[]|.tabs[]|.windows[]]|length' 2>/dev/null)"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > best_n )); then
      best="$s"
      best_n="$n"
    fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
}

# Ensure remote-control has a live kitty target, without spawning extra instances.
kensure() {
  local sock=""
  sock="$(kpick_socket)"
  if [ -n "$sock" ]; then
    export KITTY_LISTEN_ON="unix:$sock"
    return 0
  fi

  # If running inside kitty and no externally addressable socket was found,
  # direct kitty @ control can still work via the controlling terminal.
  if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    return 0
  fi

  # No live instance found, create one canonical instance.
  "$KITTY_BIN" --single-instance --instance-group kitty-main --listen-on unix:/tmp/kitty-main --detach >/dev/null 2>&1
  sleep 0.25
  export KITTY_LISTEN_ON="unix:/tmp/kitty-main"
}

# Run kitty remote-control commands against the main socket.
krc() {
  local target=""
  kensure
  target="${KITTY_LISTEN_ON:-}"

  if [ -n "$target" ] && "$KITTY_BIN" @ --to "$target" ls >/dev/null 2>&1; then
    "$KITTY_BIN" @ --to "$target" "$@"
    return $?
  fi

  target="$(kpick_socket)"
  if [ -n "$target" ]; then
    export KITTY_LISTEN_ON="unix:$target"
    "$KITTY_BIN" @ --to "$KITTY_LISTEN_ON" "$@"
    return $?
  fi

  "$KITTY_BIN" @ "$@"
}

# Run remote control on the current kitty instance when possible.
# Falls back to the shared socket when called outside kitty.
kctl() {
  if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    "$KITTY_BIN" @ "$@" 2>/dev/null || krc "$@"
  else
    krc "$@"
  fi
}

# Start a dedicated kitty OS window with a chosen profile/background.
kitty_profile() {
  if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
    echo "usage: kitty_profile <green|blue|red> [row1_cols(2-5)] [row2_cols(1-2)]"
    return 2
  fi

  local profile="$1"
  local top_cols="${2:-4}"
  local bottom_cols="${3:-2}"
  local tab_title=""
  local bg=""
  local tab_active_bg=""
  local tab_inactive_bg=""
  local tab_active_fg=""
  local tab_inactive_fg=""
  local border_active=""
  local border_inactive=""
  local main_win_id=""
  local tab_id=""
  local -a top_titles=(row1-col1 row1-col2 row1-col3 row1-col4 row1-col5)
  local row2_first_id=""
  local top_rem_id=""
  local new_id=""
  local remaining=""
  local split_bias=""
  local row2_bias="70"
  local i=""
  local title=""
  local role=""
  local bash_bin="/opt/homebrew/bin/bash"

  if [[ ! "$top_cols" =~ ^[0-9]+$ ]] || (( top_cols < 2 || top_cols > 5 )); then
    echo "row1_cols must be an integer in range 2..5"
    return 2
  fi
  if [[ ! "$bottom_cols" =~ ^[0-9]+$ ]] || (( bottom_cols < 1 || bottom_cols > 2 )); then
    echo "row2_cols must be an integer in range 1..2"
    return 2
  fi
  if [ ! -x "$bash_bin" ]; then
    bash_bin="$(command -v bash 2>/dev/null || true)"
  fi
  if [ -z "$bash_bin" ]; then
    echo "bash not found on PATH"
    return 1
  fi

  case "$profile" in
    green)
      tab_title="Green"
      bg="$HOME/.config/kitty/backgrounds/anon-bg-faded-black.jpg"
      tab_active_bg="#1e6b46"
      tab_inactive_bg="#163726"
      tab_active_fg="#dfffe9"
      tab_inactive_fg="#a9d6b8"
      border_active="#56c98a"
      border_inactive="#224734"
      ;;
    blue)
      tab_title="Blue"
      bg="$HOME/.config/kitty/backgrounds/blue-hack-bg.jpg"
      tab_active_bg="#1d4f8a"
      tab_inactive_bg="#15283d"
      tab_active_fg="#e3f0ff"
      tab_inactive_fg="#a8bfd9"
      border_active="#62d6ff"
      border_inactive="#1f2a36"
      ;;
    red)
      tab_title="Red"
      bg="$HOME/.config/kitty/backgrounds/red-hack-bg.jpg"
      tab_active_bg="#7a1f2a"
      tab_inactive_bg="#31161a"
      tab_active_fg="#ffe8eb"
      tab_inactive_fg="#dfb8be"
      border_active="#ff6b86"
      border_inactive="#3a1f24"
      ;;
    *)
      echo "invalid profile: $profile (use green, blue, or red)"
      return 2
      ;;
  esac

  main_win_id="$(kctl launch --type=os-window --tab-title "$tab_title" --title "row1-col1" --var row=top --var role=row1_col1 --var "profile=$profile" "$bash_bin" -i | tail -n1 | tr -d '[:space:]')"
  if [[ ! "$main_win_id" =~ ^[0-9]+$ ]]; then
    echo "failed to create kitty OS window for profile: $profile"
    return 1
  fi

  # Ensure tab title is pinned (Blue/Green) instead of inheriting window title.
  kctl set-tab-title --match "window_id:$main_win_id" "$tab_title" >/dev/null 2>&1
  # Build deterministic two-row layout in splits mode:
  # Row1 = top columns, Row2 = bottom columns.
  kctl goto-layout --match "window_id:$main_win_id" "splits" >/dev/null 2>&1
  kctl set-background-image --match "id:$main_win_id" --layout scaled "$bg" >/dev/null 2>&1
  tab_id="$(kctl ls | jq -r --argjson wid "$main_win_id" '.[] | .tabs[] | select([.windows[].id] | index($wid)) | .id' | head -n1)"
  if [ -n "$tab_id" ] && [ "$tab_id" != "null" ]; then
    kctl set-tab-color --match "id:$tab_id" \
      "active_bg=$tab_active_bg" \
      "active_fg=$tab_active_fg" \
      "inactive_bg=$tab_inactive_bg" \
      "inactive_fg=$tab_inactive_fg" >/dev/null 2>&1
  fi

  # Approximate per-profile darkness by adjusting background color in this OS window.
  case "$profile" in
    green) kctl set-colors --match "id:$main_win_id" background="#0a0d0a" >/dev/null 2>&1 ;;
    red) kctl set-colors --match "id:$main_win_id" background="#0d0808" >/dev/null 2>&1 ;;
    *) kctl set-colors --match "id:$main_win_id" background="#000000" >/dev/null 2>&1 ;;
  esac

  # Create row2-col1 by splitting row1-col1 into top/bottom bands.
  row2_first_id="$(kctl launch \
    --type=window \
    --match "window_id:$main_win_id" \
    --next-to "id:$main_win_id" \
    --location=hsplit \
    --bias "$row2_bias" \
    --title "row2-col1" \
    --var row=bottom \
    --var role=row2_col1 \
    --var "profile=$profile" \
    "$bash_bin" -i 2>/dev/null | tail -n1 | tr -d '[:space:]')"
  if [ -z "$row2_first_id" ]; then
    echo "failed to create row2-col1"
    return 1
  fi
  top_rem_id="$main_win_id"

  # Build equalized top columns by repeatedly carving one column from the left.
  # Example for 4 cols: biases 75, 67, 50 -> widths become ~25/25/25/25.
  for (( i = 1; i < top_cols; i++ )); do
    remaining=$(( top_cols - i + 1 ))
    split_bias=$(( (100 * (remaining - 1) + (remaining / 2)) / remaining ))
    new_id="$(kctl launch \
      --type=window \
      --match "window_id:$main_win_id" \
      --next-to "id:$top_rem_id" \
      --location=vsplit \
      --bias "$split_bias" \
      --title "__row1_rem__$i" \
      --var row=top \
      --var role=row1_rem \
      --var "profile=$profile" \
      "$bash_bin" -i 2>/dev/null | tail -n1 | tr -d '[:space:]')"
    if [ -n "$new_id" ]; then
      title="${top_titles[$i]}"
      role="${title//-/_}"
      kctl set-window-title --match "id:$top_rem_id" "$title" >/dev/null 2>&1
      kctl set-user-vars --match "id:$top_rem_id" "role=$role" "row=top" "profile=$profile" >/dev/null 2>&1
      top_rem_id="$new_id"
    fi
  done
  if [ -n "$top_rem_id" ]; then
    title="${top_titles[$top_cols]}"
    role="${title//-/_}"
    kctl set-window-title --match "id:$top_rem_id" "$title" >/dev/null 2>&1
    kctl set-user-vars --match "id:$top_rem_id" "role=$role" "row=top" "profile=$profile" >/dev/null 2>&1
  fi

  # Optional second bottom column split vertically in bottom band.
  if (( bottom_cols == 2 )); then
    kctl launch \
      --type=window \
      --match "window_id:$main_win_id" \
      --next-to "id:$row2_first_id" \
      --location=vsplit \
      --bias 50 \
      --title "row2-col2" \
      --var row=bottom \
      --var role=row2_col2 \
      --var "profile=$profile" \
      "$bash_bin" -i >/dev/null 2>&1
  fi
  if [ -n "$tab_id" ] && [ "$tab_id" != "null" ]; then
    kctl set-colors \
      --match-tab "id:$tab_id" \
      "active_border_color=$border_active" \
      "inactive_border_color=$border_inactive" >/dev/null 2>&1
  fi
  kctl set-background-image --match "id:$main_win_id" --layout scaled "$bg" >/dev/null 2>&1
}

kprofiles() {
  echo "kgreen [row1_cols 2-5] [row2_cols 1-2]  -> anon-bg-faded-black.jpg (Green)"
  echo "kblue  [row1_cols 2-5] [row2_cols 1-2]  -> blue-hack-bg.jpg (Blue)"
  echo "kred   [row1_cols 2-5] [row2_cols 1-2]  -> red-hack-bg.jpg (Red)"
}

# Run a command and send a desktop notification when done.
nrun() {
  if [ "$#" -eq 0 ]; then
    echo "usage: nrun <command> [args...]"
    return 2
  fi

  local cmd="$*"
  "$@"
  local ec=$?

  if [ $ec -eq 0 ]; then
    "$KITTEN_BIN" notify "Done" "$cmd"
  else
    "$KITTEN_BIN" notify "Failed ($ec)" "$cmd"
  fi

  return $ec
}
