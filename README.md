# AddeKitty

Portable Kitty + shell workflow bundle (macOS-first) from this setup.

## What is included

- Kitty config entry + themed base config
- Profile commands: `kgreen`, `kblue`, `kprofiles`
- Remote helpers: `krc`, `kctl`, `kensure`
- Utility commands: `khelp`, `s`, `qat`, `nrun`
- Background images used by this setup
- Quick-access + ssh kitten configs
- tmux starter config (optional)

## Folder layout

- `myconfig/` -> goes to `~/.config/myconfig`
- `kitty/` -> goes to `~/.config/kitty`
- `docs/KITTY.md` -> reference notes
- `setup.sh` -> installer/bootstrap script

## Prerequisites (macOS)

- Kitty installed at `/Applications/kitty.app`
- `jq` installed (`brew install jq`)
- Recommended: `tmux` (`brew install tmux`)
- Recommended font: Fira Code Nerd Font

Optional install commands:

```bash
brew install jq tmux bash
brew install --cask kitty
brew tap homebrew/cask-fonts
brew install --cask font-fira-code-nerd-font
```

## Install

From inside this folder:

```bash
./setup.sh
```

Install into a different home path:

```bash
./setup.sh /Users/otheruser
```

What `setup.sh` does:

- Copies configs into `~/.config/myconfig` and `~/.config/kitty`
- Rewrites hardcoded `/Users/addelovein` paths to target home
- Normalizes bash binary path if `/opt/homebrew/bin/bash` is unavailable
- Appends required source/PATH lines to `~/.zshrc` and `~/.bashrc` (idempotent)
- Installs `~/.tmux.conf` only if missing

## After install

```bash
source ~/.zshrc
source ~/.bashrc
```

Then in Kitty:

- `Cmd+Shift+R` to reload config
- Run `khelp` for commands + hotkeys

## Notes

- This setup is tuned for macOS keybindings (`cmd+...`).
- `kblue`/`kgreen` depend on Kitty remote control (`listen_on unix:/tmp/kitty-main`).
- For long-running remote work, use `tmux` on the remote host.
