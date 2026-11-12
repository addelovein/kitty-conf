# Save & Restore Layouts (`ksave` / `kload` / `kdelete`)

Three small commands to snapshot the active kitty tab — its split tree, per-pane
cwd, and running commands — into a file you can reload later in a fresh OS
window. Useful for project-specific layouts that are richer than the canned
`kgreen` / `kblue` / `kred` templates.

## Commands

- `ksave NAME [--force]`
- Snapshot the **currently focused tab** to `~/.config/kitty/sessions/NAME.conf`.
- `--force` overwrites an existing file, including hand-authored ones.
- `kload NAME`
- Open `NAME.conf` in a new kitty OS-window.
- `kload --list` shows everything saved.
- `kdelete NAME [NAME...] [--force]`
- Delete one or more saved sessions. No confirmation.
- `--force` removes hand-authored files too (otherwise refused).
- `kdelete --list` shows everything saved.

## Files

- Saved sessions: `~/.config/kitty/sessions/<name>.conf`
- Plain kitty session syntax — you can also load them manually:
- `kitty --session ~/.config/kitty/sessions/<name>.conf`
- Scripts: `~/.config/myconfig/bin/{ksave,kload,kdelete}`

## What gets captured

- The **nested split tree** for the focused tab (biases and direction of every
horizontal/vertical split — not just flat tile order).
- Each pane's `cwd` and `title`.
- Each pane's running command, recovered intelligently:
- `claude` → re-emitted as `claude-work` or `claude-personal` based on the
running process's `CLAUDE_CONFIG_DIR`. Any initial prompt args are kept
(e.g. `/sc:load\nWhats next for this project?`).
- `ssh` / `kitten ssh` → emitted as `kitten ssh <user@host>`.
- `./scripts/foo.sh ...` or `bash scripts/foo.sh ...` → emitted verbatim.
- Transient wrappers (`caffeinate`, `sleep`, bare shells) → dropped; the
pane re-opens as a plain login shell in its captured cwd.

## What does NOT get captured

- Commands that have **already exited** before save. If your ssh session timed
out and only `bash` remains in the pane, ksave only sees bash. Reconnect
(`kitten ssh host`) before saving.
- In-process state (open editor buffers, REPL state, scrollback content).
- Tabs other than the focused one. To save another tab, focus it first.

## Typical workflow

```bash
# Build the tab you want (split panes, start commands).
# Make sure every command you want restored is actually running.
# Focus the tab.
ksave red          # writes ~/.config/kitty/sessions/red.conf
kload --list       # confirms it's there
kload red          # opens it in a new OS-window

# Update the file after changing the layout:
ksave red --force

# Remove a no-longer-useful saved layout:
kdelete old-thing
```

## How restore actually works

Each `launch` line in the generated session file runs:

```text
/opt/homebrew/bin/bash -lic 'cd <cwd> 2>/dev/null; <cmd>; exec bash -li'
```

A login + interactive shell is used so `~/.bashrc` loads `~/.config/myconfig/bin`
onto `PATH` (where `s`, `claude-work`, `claude-personal`, etc. live), and the
explicit `cd` is required because kitty's `--cwd` is unreliable for panes that
are created as splits (they otherwise inherit the parent pane's directory).

Claude prompts with embedded newlines are constructed at restore time via
`printf '%s\n%s' ...` so the session file stays single-line, shlex-parseable,
and survives kitty's session parser.

## Geometry preservation

ksave reads `tab.layout_state.pairs` (the real nested split tree from kitty
remote control) and emits launches in the only correct order: split each
secondary subtree off as a **single pane** at the boundary that is still one
window, then subdivide both halves. Building the left side fully before
touching the right would squash the right column into one corner — easy
mistake, the algorithm avoids it.

Biases round to whole percentages, so reloaded geometry matches the original
within ~1% per split.

## Safety

- ksave never silently overwrites a session file whose first line is not
`# kitty session saved by ksave` — use `--force` to override.
- kdelete refuses to delete a file lacking the same marker — use `--force`.
- Both guards exist to protect hand-authored sessions like
`~/.config/kitty/sessions/red.kitty-session`.

## Requirements

- kitty with remote control on (`allow_remote_control yes`,
`listen_on unix:/tmp/kitty-main`) — already set in `myconfig/kitty/base.conf`.
- `jq` and `python3` available on `PATH` (already part of the AddeKitty
prerequisites).
