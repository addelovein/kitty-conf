# kitty setup reference

Reference for the installed setup (paths assume `setup.sh` defaults). Install
steps: [`README.md`](../README.md). Claude Code integration:
[`CLAUDE-KITTY.md`](CLAUDE-KITTY.md). Layout save/restore: [`KSAVE.md`](KSAVE.md).

## Overview
- OS: macOS
- Main style: dark hacker theme with tinted background image
- Main font: `Fira Code`
- Default wallpaper: `wolf-hacker-bg.jpg`
- Default tab style: gray
- Border colors:
- default/gray tabs: light gray
- `Green` profile tabs: green
- `Blue` profile tabs: blue
- `Red` profile tabs: red
- Main layouts:
- `Green`: 2-row `splits` template, background `anon-bg-faded-black.jpg`, green tab color
- `Blue`: 2-row `splits` template, background `blue-hack-bg.jpg`, blue tab color
- `Red`: 2-row `splits` template, background `red-hack-bg.jpg`, red tab color
- Row model (only):
- `Row1`: `col1`, `col2`, optional `col3`, optional `col4`, optional `col5` (bash)
- `Row2`: `col1`, optional `col2` (bash)
- Row direction:
- `Row1`/`Row2` are top/bottom bands (horizontal split between rows).
- `col1..colN` inside each row are left/right columns (vertical splits).
- Default launch counts: `Row1=4`, `Row2=2`

## Choose Which One To Start
- Load zsh changes (once per shell):
- `source ~/.zshrc`
- Start Green profile:
- `kgreen`
- Start Blue profile:
- `kblue`
- Start Red profile:
- `kred`
- Show available profile commands:
- `kprofiles`
- Optional counts:
- `kgreen <row1_cols 2-5> <row2_cols 1-2>`
- `kblue <row1_cols 2-5> <row2_cols 1-2>`
- `kred <row1_cols 2-5> <row2_cols 1-2>`
- Example:
- `kblue 3 1` (Row1: 3 columns, Row2: 1 column)
- `kblue 4 2` (Row1 small + 4 equalized top columns, Row2 large + 2 equal bottom columns)
- When run from inside Kitty, both launch in that same Kitty instance.
- When run outside Kitty, they use the shared socket instance (`/tmp/kitty-main`).

## Current Startup Behavior
- `kitty.conf` now uses:
- `startup_session none`
- Meaning: opening Kitty normally starts a regular window/shell.
- Use `kgreen`, `kblue`, or `kred` when you want the full 6-pane profile window.

## Key Paths
- Main config: `~/.config/kitty/kitty.conf`
- Main config backend: `~/.config/myconfig/kitty/base.conf`
- Theme: `~/.config/kitty/theme-hacker.conf`
- Quick access config: `~/.config/kitty/quick-access-terminal.conf`
- SSH kitten config: `~/.config/kitty/ssh.conf`
- New tab script: `~/.config/kitty/scripts/new-tab-profile.sh`
- New window script: `~/.config/kitty/scripts/new-window-profile.sh`
- Sessions:
- `~/.config/kitty/sessions/green-five.kitty-session`
- `~/.config/kitty/sessions/blue-five.kitty-session`
- Background folder: `~/.config/kitty/backgrounds`
- Zsh loader: `~/.zshrc`
- Zsh kitty logic: `~/.config/myconfig/shell/zsh/kitty.zsh`
- Bash loader: `~/.bashrc`
- Bash kitty helper: `~/.config/myconfig/shell/bash/kitty.bash`

## Config Layout
- Kitty reads: `~/.config/kitty/kitty.conf`
- That file includes: `~/.config/myconfig/kitty/base.conf`
- Zsh reads: `~/.zshrc` then sources `~/.config/myconfig/shell/zsh/kitty.zsh`
- Bash reads: `~/.bashrc` then sources `~/.config/myconfig/shell/bash/kitty.bash`
- Command shortcuts live in: `~/.config/myconfig/bin`
- Both zsh/bash add that directory to `PATH`

## Bin Commands
- `khelp` (show all commands and hotkeys)
- `kblue`, `kgreen`, `kred`, `kprofiles`
- `krc`, `kctl`, `kensure`
- `kwindows` (list windows across instances + send by unique uid)
- `kcolors` (print 16/256/RGB terminal color samples)
- `icat` (show images inline in Kitty via kitten icat)
- `kshow` (images in a split; works from Claude Code), `ktemp` (run in the Claude column's TEMP shell), `kfloat` (images or image URLs in a floating panel)
- `ksave`, `kload`, `kdelete` (save/restore tab layouts, see [`KSAVE.md`](KSAVE.md))
- `ktabname`, `kwindowname`, `kset` (names, recolor a tab to a profile)
- `kdoctor` (check the setup), `kapprove` (Claude auto-approver), `ksend` (needs yabai)
- `s`, `qat`, `nrun`

## Keyboard Shortcuts
- `Cmd+Enter`: new split window in current directory (profile-aware shell)
- `Cmd+Shift+Enter`: split the current pane side by side (vertical split, current directory)
- `Cmd+T`: profile-aware new tab
- `Cmd+R`: start interactive pane resize mode (keyboard-driven)
- Fast resize (no Alt):
- `Cmd+Ctrl+Left`: wider
- `Cmd+Ctrl+Right`: narrower
- `Cmd+Ctrl+Up`: taller
- `Cmd+Ctrl+Down`: shorter
- `Ctrl+Shift+0`: reset pane sizes
- New tab title: starts from active window title
- Tab title then updates dynamically with the active window title (for `cd`, it follows folder path)
- If current folder is in a git repo, title becomes `folder   branch`
- If active title is a structural pane label (`row1-colX` / `row2-colX`), title uses current folder path instead
- In `Blue` tab: opens Bash tab with blue tab color
- In `Green` tab: opens Bash tab with green tab color
- In `Red` tab: opens Bash tab with red tab color
- In non-gray/profile tabs: new tabs default to Bash
- In gray/default tabs: normal Kitty shell behavior
- `Cmd+Shift+R`: reload kitty config
- `Cmd+,`: edit kitty config
- `Cmd+Ctrl+F`: fullscreen toggle
- `Ctrl+Shift+Z`: active-window zoom toggle (full-size `stack` and restore)
- `Cmd+Shift+J`: quick-access terminal (quake style)
- `Cmd+Shift+O`: create a tab-wide right column (~25%) in `splits` layout, by hand.
  Claude sessions get their own STATUS + TEMP column automatically
  ([`CLAUDE-KITTY.md`](CLAUDE-KITTY.md) §1b); use this one outside Claude.

## Shell Helpers
- `s <host>`: kitty SSH kitten wrapper
- `qat`: quick-access terminal from command line
- `nrun <command>`: run command + notify on finish
- `kgreen`: open Green 6-pane profile
- `kblue`: open Blue 6-pane profile
- `kred`: open Red 6-pane profile
- `kprofiles`: print profile quick reference
- `kensure`: make sure kitty main socket exists (`/tmp/kitty-main`)
- `krc <subcommand...>`: run `kitty @` against main socket
- `kctl <subcommand...>`: run `kitty @` on current kitty instance (fallback to `krc`)
- `kwindows list`: list all windows across `/tmp/kitty-main*` sockets with uid `socket::window_id`
- `kwindows send <uid> <text...>`: send text to that exact window
- `kwindows send-enter <uid> <text...>`: send text and press Enter
- `kcolors [all|16|256|rgb]`: preview terminal color palette
- `icat <image-path> [icat-options...]`: display image inline in terminal
- Example:
- `krc ls`
- `kcolors 256`
- `icat ~/.config/kitty/backgrounds/wolf-hacker-bg.jpg`
- `kwindows list`
- `kwindows send-enter '/tmp/kitty-main-12345::67' 'clear'`
- `krc send-text --match 'title:^row1-col1$' 'clear\n'`
- `krc send-text --match 'var:row=top' 'clear\n'` (targets all top-row bash panes)

## Shell Defaults
- In Blue/Green/Red profile layouts, all row panes default to Bash (`/opt/homebrew/bin/bash`).
- Gray/default (non-profile) windows keep normal shell defaults.
- Non-gray/profile tabs created via `Cmd+T` default to Bash.
- Non-gray/profile splits created via `Cmd+Enter` default to Bash.

## Bash Prompt
- File: `~/.bashrc`
- Login loader: `~/.bash_profile`
- Kitty helper file: `~/.config/myconfig/shell/bash/kitty.bash`
- Style: two-line modern prompt with:
- `user@host`
- current path
- git branch (when inside repo)
- command status (`ok` or `x<code>`)
- Also updates kitty window title to current path (`~`-shortened), so tab names track folder changes
- In git repos, bash title adds the current branch after the path
- Enables colored `ls` in bash (`ls`, `l`, `la`, `ll`)
- Reload in current bash shell:
- `source ~/.bashrc`

## Zsh Title Sync
- Loader file: `~/.zshrc`
- Logic file: `~/.config/myconfig/shell/zsh/kitty.zsh`
- Adds `precmd` + `chpwd` hooks to set kitty window title to `%~`
- In git repos, zsh title adds the current branch after the path
- This keeps tab names in sync with active zsh window path as you move folders

## Quick Access Notes
- Command: `kitten quick-access-terminal`
- It is not the same persistent shell session unless you keep that window alive.
- If closed/recreated, it starts a new shell process.

## Remote Control
- Enabled in kitty config:
- `allow_remote_control yes`
- `listen_on unix:/tmp/kitty-main`
- Test:
- `kitty @ ls`
- Socket-aware test:
- `krc ls`
- List all window IDs across all OS windows in the shared instance:
- `krc ls | jq -r '.[] as $os | $os.tabs[] as $tab | $tab.windows[] | "os=\($os.id) tab=\($tab.id) win=\(.id) title=\(.title)"'`

## Visual Settings (Current Defaults)
- `background_image ~/.config/kitty/backgrounds/wolf-hacker-bg.jpg`
- `background_tint 0.88`
- `background_tint_gaps 0.0`
- `window_padding_width 2`
- `window_border_width 1.0`
- `window_margin_width 4`

## Reload After Edits
- Reload kitty settings: `Cmd+Shift+R`
- Reload zsh helpers: `source ~/.zshrc`

## tmux Quickstart (Remote Reattach)
- Config file: `~/.tmux.conf`
- Start a named session on the machine where job will run:
- `tmux new -s work`
- Run your long job inside tmux:
- `python your_script.py` (example)
- Detach and leave it running:
- `Ctrl+b` then `d`
- Later (from any machine), SSH to the same host and reattach:
- `tmux ls`
- `tmux attach -t work`
- Kill session when done:
- `tmux kill-session -t work`

## tmux Useful Keys
- Prefix: `Ctrl+b`
- New window: `c`
- Next/prev window: `n` / `p`
- Split vertically (top/bottom): `-`
- Split horizontally (left/right): `|`
- Move between panes: arrow keys
- Reload tmux config: `Ctrl+b` then `r`
