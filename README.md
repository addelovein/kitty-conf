# AddeKitty

Portable kitty + shell setup for macOS, with a Claude Code integration:
themed config, profile windows, layout save/restore, and live kitty windows
for Claude's status, subagents, images and job output.

## What is included

- kitty config entry + themed base config, background images
- Profile commands: `kgreen`, `kblue`, `kred`, `kprofiles`, `kset`
- Remote-control helpers: `krc`, `kctl`, `kensure`, `kwindows`
- Utilities: `khelp`, `kdoctor`, `kcolors`, `icat`, `s`, `qat`, `nrun`
- Naming: `ktabname`, `kwindowname`; single-instance launcher `bin/kitty`
- Layout save/restore: `ksave`, `kload`, `kdelete` ([`docs/KSAVE.md`](docs/KSAVE.md))
- Per-profile border colors that follow focus (`myconfig/kitty/profile_borders.py`)
- Quick-access + ssh kitten configs, optional tmux starter config
- **Claude Code integration** ([`docs/CLAUDE-KITTY.md`](docs/CLAUDE-KITTY.md)):
  session status in tab titles, a right-hand STATUS + TEMP column shared by
  every Claude session in a tab, a live window per subagent, and `kshow` /
  `ktemp` for showing images and live output from Claude

## Requirements

| Need | Why | Install |
|---|---|---|
| macOS, kitty in `/Applications/kitty.app`, **0.50+** | 0.50 for tab status + docked viewer | `brew install --cask kitty` |
| `/usr/bin/jq` | scripts call this path; ships with macOS 15+ | older macOS: `brew install jq`, then replace `/usr/bin/jq` with `jq` in `myconfig/bin` and `claude/kitty-plugin/scripts` |
| `python3` | `ksave`/`kload`, Claude plugin viewers | `xcode-select --install` |
| `rsync` | `setup.sh` | ships with macOS |
| Claude Code CLI (optional) | Claude integration | see claude.com/claude-code |
| Fira Code Nerd Font (recommended) | glyphs in titles and prompts | `brew install --cask font-fira-code-nerd-font` |
| Homebrew bash, tmux (optional) | profile panes use bash; remote work | `brew install bash tmux` |
| yabai (optional) | only for `ksend` | `brew install koekeishiya/formulae/yabai` |

## Install

```bash
cd ~/Source/AddeKitty      # wherever you cloned it
./setup.sh                 # or: ./setup.sh /Users/otheruser
```

What `setup.sh` does:

- Warns about missing requirements (does not stop).
- **Backs up** existing `~/.config/kitty` and `~/.config/myconfig` to
  `~/.config/addekitty-backup-<date>.tgz`, then copies the repo's `kitty/`
  and `myconfig/` over them. Files that exist only on your side are kept;
  files that exist in both are replaced by the repo's version.
- Rewrites `/Users/addelovein` paths to the target home and the bash path if
  `/opt/homebrew/bin/bash` is missing.
- Adds PATH + source lines to `~/.zshrc` and `~/.bashrc` (idempotent).
- Installs `~/.tmux.conf` only if missing.
- Does **not** touch `~/.claude*` (see Claude Code setup below).

Then:

```bash
exec zsh                   # or open a new tab
kdoctor                    # checks the setup, prints ok / warn / FAIL
khelp                      # commands + hotkeys
```

In kitty: `Cmd+Shift+R` reloads the config. Remote control (`listen_on`)
changes need a full kitty restart.

## Claude Code setup

Repeat steps 1–3 for every Claude profile you use. For a profile other than
`~/.claude`, prefix the commands with `CLAUDE_CONFIG_DIR=~/.claude-work` (etc.).

1. **Install the plugin** (adds the column, subagent windows, `kitty-show` skill):

   ```bash
   claude plugin marketplace add ~/Source/AddeKitty
   claude plugin install addekitty@addekitty
   ```

2. **Status line** — STATUS gets model, context, cost and rate limits from
   Claude's status-line payload, which the status-line script must save:
   - No status line yet: use the repo's.

     ```bash
     cp ~/Source/AddeKitty/myconfig/statusline-command.sh ~/.claude/
     ```

     and in `~/.claude/settings.json`:
     `"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}`
   - Own status line: paste the 5-line block from
     [`docs/CLAUDE-KITTY.md`](docs/CLAUDE-KITTY.md) §1b right after `input=$(cat)`.

3. **PATH** — if `settings.json` sets `env.PATH`, add
   `$HOME/.config/myconfig/bin` to it (as an absolute path), or Claude can only
   run `kshow` / `ktemp` by full path. `kdoctor` warns when it is missing.

4. **Restart** Claude in a kitty tab using the **splits** layout. Don't also
   pass `--plugin-dir`, or every hook runs twice.

5. Run `kdoctor`. On the next Claude start the right column appears:
   STATUS on top, TEMP (a bash shell for you and Claude) below.

Any command Claude waits on for more than 3 s, every GitHub run it starts, and
every image it opens or mentions in a reply (paths and https image URLs) are
shown: commands and runs in their own split below TEMP, images in a floating
panel in the middle of the screen (`kfloat`). Cmd+clicking an image URL
anywhere in kitty opens the same panel (`kitty/open-actions.conf`).

Turn the column off with `KITTY_CLAUDE_LAYOUT=0`, the subagent windows with
`KITTY_AGENT_WINDOWS=0`, the live command splits with `KITTY_WAIT_SPLIT=0`, the images with
`KITTY_IMAGE_SHOW=0` (or `KITTY_IMAGE_FLOAT=0` for a column split instead of the panel). All tunables: [`docs/CLAUDE-KITTY.md`](docs/CLAUDE-KITTY.md).

## Update

```bash
cd ~/Source/AddeKitty && git pull && ./setup.sh
# plugin, in each profile (bump "version" in plugin.json first if you edited it):
claude plugin marketplace update addekitty
claude plugin update addekitty@addekitty
```

## Uninstall

1. `claude plugin uninstall addekitty@addekitty` (each profile), and
   `claude plugin marketplace remove addekitty`.
2. Remove the AddeKitty lines (`myconfig/bin` PATH, `kitty.zsh` / `kitty.bash`
   source, `__title_git_branch`) from `~/.zshrc` and `~/.bashrc`.
3. Delete `~/.config/myconfig` and `~/.config/kitty`, or restore what you had
   before: `tar -xzf ~/.config/addekitty-backup-<date>.tgz -C ~/.config`.

## Folder layout

| Path | Goes to | What |
|---|---|---|
| `kitty/` | `~/.config/kitty` | `kitty.conf` (includes base.conf), theme, scripts, backgrounds, `open-actions.conf` (image links → kfloat) |
| `myconfig/kitty/` | `~/.config/myconfig/kitty` | `base.conf` (main settings, hotkeys), border watcher |
| `myconfig/bin/` | `~/.config/myconfig/bin` | all `k*` commands |
| `myconfig/shell/` | `~/.config/myconfig/shell` | zsh/bash prompt + title logic |
| `myconfig/statusline-command.sh` | (copy by hand, step 2) | Claude status line |
| `myconfig/claude/` | not installed | the author's Claude settings, for reference only |
| `claude/kitty-plugin/` | via `claude plugin install` | Claude Code plugin |
| `.claude-plugin/marketplace.json` | — | makes this repo a local plugin marketplace |
| `docs/` | — | [`KITTY.md`](docs/KITTY.md) reference, [`KSAVE.md`](docs/KSAVE.md), [`CLAUDE-KITTY.md`](docs/CLAUDE-KITTY.md), `tmux.conf` |

## Notes

- Tuned for macOS keybindings (`cmd+...`).
- Remote control is on (`allow_remote_control yes`, `listen_on unix:/tmp/kitty-main`);
  kitty appends its pid to the socket name. See the security note in
  [`docs/CLAUDE-KITTY.md`](docs/CLAUDE-KITTY.md).
- For long-running remote work, use `tmux` on the remote host.
