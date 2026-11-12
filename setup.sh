#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${1:-$HOME}"
TARGET_CONFIG="$TARGET_HOME/.config"
TARGET_KITTY="$TARGET_CONFIG/kitty"
TARGET_MYCONFIG="$TARGET_CONFIG/myconfig"

ensure_line() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" || printf '\n%s\n' "$line" >> "$file"
}

# Copy a tree over the target. Files that exist only in the target are kept.
# myconfig/claude is the author's Claude settings, kept for reference only.
copy_tree() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  rsync -a --exclude '.DS_Store' --exclude '__pycache__' --exclude '/claude/' "$src"/ "$dst"/
}

echo "Installing AddeKitty into: $TARGET_HOME"

# Requirements: warn, don't stop (the base kitty config works without them).
[ -x /Applications/kitty.app/Contents/MacOS/kitty ] || echo "warn: kitty not in /Applications (brew install --cask kitty)"
[ -x /usr/bin/jq ] || echo "warn: /usr/bin/jq missing (ships with macOS 15+); kshow, ktemp, ksave and the Claude plugin need it"
command -v python3 >/dev/null 2>&1 || echo "warn: python3 missing; ksave/kload and the Claude plugin need it"

# Back up what will be overwritten.
backup_items=()
[ -d "$TARGET_KITTY" ] && backup_items+=(kitty)
[ -d "$TARGET_MYCONFIG" ] && backup_items+=(myconfig)
if [ "${#backup_items[@]}" -gt 0 ]; then
  BACKUP="$TARGET_CONFIG/addekitty-backup-$(date +%Y%m%d-%H%M%S).tgz"
  tar -czf "$BACKUP" -C "$TARGET_CONFIG" "${backup_items[@]}"
  echo "Backed up ${backup_items[*]} to $BACKUP"
fi

mkdir -p "$TARGET_KITTY" "$TARGET_KITTY/scripts" "$TARGET_KITTY/backgrounds" "$TARGET_MYCONFIG"

copy_tree "$ROOT_DIR/myconfig" "$TARGET_MYCONFIG"
copy_tree "$ROOT_DIR/kitty" "$TARGET_KITTY"

# Rewrite package author home paths for target user.
for f in \
  "$TARGET_KITTY/kitty.conf" \
  "$TARGET_KITTY/quick-access-terminal.conf" \
  "$TARGET_MYCONFIG/kitty/base.conf"
  do
    [ -f "$f" ] || continue
    sed -i.bak "s|/Users/addelovein|$TARGET_HOME|g" "$f"
    rm -f "$f.bak"
  done

# Normalize bash binary path for systems without /opt/homebrew/bin/bash.
BASH_BIN="/opt/homebrew/bin/bash"
if [ ! -x "$BASH_BIN" ]; then
  BASH_BIN="$(command -v bash || true)"
fi
if [ -z "$BASH_BIN" ]; then
  BASH_BIN="/bin/bash"
fi

for f in \
  "$TARGET_KITTY/scripts/new-tab-profile.sh" \
  "$TARGET_MYCONFIG/shell/zsh/kitty.zsh"
  do
    [ -f "$f" ] || continue
    sed -i.bak "s|/opt/homebrew/bin/bash|$BASH_BIN|g" "$f"
    rm -f "$f.bak"
  done

chmod +x "$TARGET_MYCONFIG/bin"/* "$TARGET_KITTY/scripts/new-tab-profile.sh" || true

# Ensure shell bootstrap lines exist.
ensure_line "$TARGET_HOME/.zshrc" 'export PATH="$HOME/.config/myconfig/bin:$PATH"'
ensure_line "$TARGET_HOME/.zshrc" '[ -f "$HOME/.config/myconfig/shell/zsh/kitty.zsh" ] && source "$HOME/.config/myconfig/shell/zsh/kitty.zsh"'

ensure_line "$TARGET_HOME/.bashrc" 'export PATH="$HOME/.config/myconfig/bin:$PATH"'
ensure_line "$TARGET_HOME/.bashrc" '[ -f "$HOME/.config/myconfig/shell/bash/kitty.bash" ] && source "$HOME/.config/myconfig/shell/bash/kitty.bash"'
ensure_line "$TARGET_HOME/.bashrc" 'type __title_git_branch >/dev/null 2>&1 || __title_git_branch() { :; }'

# Optional tmux config
if [ -f "$ROOT_DIR/docs/tmux.conf" ] && [ ! -f "$TARGET_HOME/.tmux.conf" ]; then
  cp "$ROOT_DIR/docs/tmux.conf" "$TARGET_HOME/.tmux.conf"
fi

echo
echo "AddeKitty setup complete."
echo "Next steps:"
echo "  1) source ~/.zshrc"
echo "  2) source ~/.bashrc"
echo "  3) Open kitty and press Cmd+Shift+R"
echo "  4) Run: khelp   (commands + hotkeys)"
echo "  5) Run: kdoctor (checks the setup)"
echo "Claude Code integration: see README.md, section 'Claude Code setup'."
