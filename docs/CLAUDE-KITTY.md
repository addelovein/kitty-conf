# Claude Code × kitty

How Claude Code and kitty work together in this setup. Requires kitty with
`allow_remote_control` + `listen_on` (already in `base.conf`). Docked windows
and tab status need **kitty >= 0.50** (`brew upgrade --cask kitty`, then quit
and reopen kitty).

## 1. Session status in the tab bar (kitty 0.50+, no hooks)

Claude Code 2.1.295+ reports working / blocked-on-you / done / failed through
the Program Status Protocol (OSC 7501). `base.conf` puts it in every tab title
via `{tab.program_status}` in `tab_title_template`. Nothing to configure in
Claude. Claude checks for support at startup, so restart running sessions
after upgrading kitty. Not shown for background sessions, inside tmux, or with
`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`.

## 1b. Right-hand column per tab (`scripts/session-layout.sh`)

A `SessionStart` hook gives the tab (splits layout) one right-hand column,
shared by every Claude session in that tab:

```
┌──────────────────────┬─────────┐
│ Claude               │ STATUS  │  one section per session + its subagents
│                      ├─────────┤
├──────┬───────┬───────┤ TEMP    │  shell; below it splits for images, GH runs,
│ agent│ agent │ agent │         │  and any command Claude waits on
└──────┴───────┴───────┴─────────┘
```

- Windows carry user vars `claude_role=status|temp` and
  `claude_role_owner=<Claude window that created them>`. They are found per
  tab: a second session started in a split of the same tab, or a resumed or
  cleared one, reuses them; a missing one is recreated. A lock
  (`$TMPDIR/claude-kitty-agents/.lock-layout`) stops two sessions starting at
  once from both building a column. Skipped for `claude -p`.
- STATUS runs `scripts/status-view.py` and lists every window in its tab that
  runs `claude` (sorted by window id, separated by a rule). Per session:
  state + current action (kitty Program Status), model, effort,
  thinking/fast, context bar + tokens, prompt-cache hit rate and warm time,
  cost, duration, lines +/−, dir, git branch, session name, and its
  running/finished subagents. With two or more sessions each section is
  tagged `#<window id> <session name>`. The account-wide 5h/7d rate limits
  (with resets) and the version sit once in a footer pinned to the bottom.
  It stays open when a session ends; close it by hand if the tab no longer
  runs Claude.
  Everything except state and agents comes from the status-line payload,
  which `~/.claude/statusline-command.sh` saves per kitty window (add to the
  top of any status-line script, right after `input=$(cat)`):

  ```bash
  if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    _ksd="${TMPDIR:-/tmp}/claude-kitty-status"; mkdir -p "$_ksd" 2>/dev/null
    printf '%s\n' "$input" > "$_ksd/$KITTY_WINDOW_ID.json.$$" 2>/dev/null \
      && mv -f "$_ksd/$KITTY_WINDOW_ID.json.$$" "$_ksd/$KITTY_WINDOW_ID.json" 2>/dev/null
  fi
  ```

  STATUS restarts itself when `status-view.py` changes, and clears its
  screen and scrollback on start and resize (a window scrolled up one line
  otherwise shows a stale top row and hides the footer).
- TEMP is your bash shell and every session's: `ktemp <cmd>` types a command
  into it (falls back to a split when it is busy).
- `ktemp --split [--title T] <cmd>` and every `kshow` call open a NEW split of
  the column (the tallest window there is halved), tagged `claude_role=view`.
  It stays until you press a key in it, so several images and GH deploy logs
  can be open at once. `kshow --close` closes all of them in the tab.
- **Everything Claude waits on shows up live** (`scripts/wait-watch.sh` +
  `wait-view.py`, Bash PreToolUse hook). Claude Code writes a foreground
  command's output to `<tmp>/claude-<uid>/<project>/<session>/tasks/<id>.output`
  and deletes it when the command ends. If that file still exists
  `KITTY_WAIT_AFTER` s (default 3) after the call started, a split titled
  `⏳ <description>` follows it. When it ends the title turns `✔` and the
  split closes after `KITTY_WAIT_LINGER` s (default 10; a key keeps it, `0`
  always keeps). Quick commands never open one; `run_in_background` calls
  and `gh run watch` (below) are skipped. Claude's commands are not changed.
  `KITTY_WAIT_SPLIT=0` turns it off.
- **Every image Claude looks at or mentions is shown** (`scripts/image-show.sh`)
  in a floating panel in the middle of the screen (`kfloat`, below).
  PostToolUse on Read: an image file Claude opens is shown right away. Stop:
  image paths in Claude's reply that exist on disk (absolute, `~/`, relative
  to the session dir, markdown links) and https image URLs are shown together
  when the turn ends. URLs only when they end in an image extension with no
  `?query` or `#fragment` and are not localhost or an IP address, so a reply
  cannot be used to send data out through a URL. Each file (path + mtime) or
  URL once per session, at most `KITTY_IMAGE_MAX` (6) per turn.
  `KITTY_IMAGE_SHOW=0` turns it off, `KITTY_IMAGE_FLOAT=0` uses a column
  split (`kshow`, local files only) instead of the panel.
- **GitHub runs open by themselves** (`scripts/gh-watch.sh`, Bash Pre/PostToolUse
  hooks). When Claude runs `gh workflow run …` (the run URL in its output, or
  the workflow's newest run) or `gh run watch <id>`, a split titled
  `▶ <workflow> #<id>` runs `gh run watch <id>` so you can follow it live.
  Claude's own command is untouched. One split per run id (window var
  `claude_run`), kept until a key. `KITTY_GH_WATCH=0` turns it off.
- Splits get the caller's `PATH` (`ktemp` passes `--env PATH=…`); a window
  launched over remote control otherwise gets kitty's own environment.
- Tunables: `KITTY_CLAUDE_LAYOUT=0` disables, `KITTY_CLAUDE_COL` (width %,
  default 30), `KITTY_CLAUDE_STATUS_LINES` (default 12).
- Adopt existing windows by hand:
  `kitten @ set-user-vars --match id:N claude_role=temp claude_role_owner=<claude window id>`.

## 2. A live window per subagent (`claude/kitty-plugin`)

Plugin `addekitty` adds `SubagentStart` / `SubagentStop` hooks
(`scripts/agent-dock.sh`). Each subagent gets a kitty window that follows its
transcript (`scripts/agent-view.py`): the task, every tool call on one line,
results, and text.

- The first subagent opens in a **strip below the Claude window** (30% of its
  height). Each further subagent splits that strip side by side (the widest
  strip window is halved). Needs the tab in the `splits` layout.
- More than 4 at once, or a tab in another layout: a shared **Agents** tab in
  grid layout.
- Parallel subagents start at the same instant; a per-window lock
  (`$TMPDIR/claude-kitty-agents/.lock-<window>`) makes them queue so they land
  in one row instead of stacking.
- When the subagent finishes its title turns `✔` and it closes after 8 s.
- Stopping a subagent by hand does **not** fire `SubagentStop`. The viewer
  catches it instead: the transcript ends with `[Request interrupted by user]`,
  so it shows `✖ stopped by user`, retitles itself `✖` and exits after the
  same linger.
- Internal helper agents (empty agent type) are skipped.

Install (pick one):

```bash
claude-work --plugin-dir ~/Source/AddeKitty/claude/kitty-plugin   # one session
# or permanently (done for claude-work and claude-personal):
claude plugin marketplace add ~/Source/AddeKitty
claude plugin install addekitty@addekitty
```

The full setup (status line, `env.PATH`, per profile) is in the README,
section *Claude Code setup*; `kdoctor` checks all of it.

The installed copy lives in `<config dir>/plugins/cache/addekitty/`. After
editing the plugin here, bump `version` in `.claude-plugin/plugin.json` and run
`claude plugin marketplace update addekitty` + `claude plugin update
addekitty@addekitty` in each profile. Don't combine `--plugin-dir` with the
installed plugin: every hook would run twice.

Tunables (environment of the Claude process):

| Variable | Default | Effect |
|---|---|---|
| `KITTY_AGENT_WINDOWS` | `1` | `0` disables the windows |
| `KITTY_AGENT_STRIP_SIZE` | `30` | strip height, % of the Claude window |
| `KITTY_AGENT_MAX_STRIP` | `4` | windows in the strip before using the Agents tab |
| `KITTY_AGENT_LINGER` | `8` | seconds to keep a finished window; `0` keeps it |
| `KITTY_WAIT_SPLIT` | `1` | `0` stops long Bash commands opening a live split |
| `KITTY_WAIT_AFTER` | `3` | seconds a command must run before it gets a split |
| `KITTY_WAIT_LINGER` | `10` | seconds a finished split stays; `0` keeps it until a key |
| `KITTY_IMAGE_SHOW` | `1` | `0` stops showing images Claude opens or mentions |
| `KITTY_IMAGE_MAX` | `6` | images shown per turn at most |
| `KITTY_IMAGE_FLOAT` | `1` | `0` shows images in a column split instead of the floating panel |
| `KITTY_IMAGE_URLS` | `1` | `0` stops fetching image URLs from Claude's replies |
| `KFLOAT_TIMEOUT` | `12` | seconds per image in the floating panel; `0` waits for a key |
| `KFLOAT_COLS` / `KFLOAT_LINES` | `100` / `32` | floating panel size in cells |
| `KITTY_GH_WATCH` | `1` | `0` stops GitHub runs opening a watch split |
| `KITTY_AGENT_DEBUG` | `0` | `1` logs hook payloads to `$TMPDIR/claude-kitty-agents/debug.log` |

Errors go to `$TMPDIR/claude-kitty-agents.err`. Hooks never print to stdout and
always exit 0, so they cannot disturb Claude.

## 3. Images: `kshow` + the `kitty-show` skill

Claude's Bash tool captures output (no tty), so `kitten icat` run there draws
nothing. `kshow` runs icat in a new kitty window: a split of the right column
when there is one (each call adds a split), otherwise one viewer beside the
calling window that the next call replaces:

```bash
kshow plot.png [more.png ...]   # one split showing these images
kshow --close                   # close all of them
KSHOW_SIZE=60% kshow big.png    # viewer width without the column (default 45%)
```

The plugin's `kitty-show` skill tells Claude to use it whenever it should show
you an image. Press any key in the viewer to close it.

### Floating panel: `kfloat`

```bash
kfloat shot.png https://example.org/chart.png   # files and http(s) image URLs
kfloat --focus pic.png    # take keyboard focus (what a link click does)
```

A `kitten panel` centered over everything (`--layer=overlay`). It shows one
image at a time: any key shows the next one, `q`/Esc closes, and each image
moves on by itself after `KFLOAT_TIMEOUT` seconds. Started from the hook it
does not take focus, so typing to Claude is not interrupted; click it to
focus it. URLs are downloaded with curl (https-only redirects, 10 MB, 15 s)
to `~/Library/Caches/kfloat` (kept 7 days) and shown only if `file` says the
content is an image.

`~/.config/kitty/open-actions.conf` makes clicking (Cmd+click) an image URL
or a hyperlinked image file anywhere in kitty open it in `kfloat`; other
links still go to the browser. kitty reads the file on the next click, no
restart needed.

## 4. Notifications

`preferredNotifChannel: "kitty"` in Claude settings sends kitty desktop
notifications (OSC 99). For click-to-act notifications from a hook:
`kitten notify -w -b Approve -b Deny "Claude" "Run tests?"` prints the button
number.

## Facts verified while building this (2026-11-12)

- Hooks and the Bash tool inherit `KITTY_WINDOW_ID` / `KITTY_LISTEN_ON` from the
  window Claude runs in, so `kitten @` works from both.
- `SubagentStart` payload: `session_id`, `transcript_path`, `cwd`, `agent_id`
  (no `agent-` prefix), `agent_type`. The live transcript is
  `dirname(transcript_path)/<session_id>/subagents/agent-<agent_id>.jsonl`;
  `SubagentStop` confirms it as `agent_transcript_path`.
- `kitten @ launch --match` selects a **tab**: use `window_id:N`, not `id:N`.
  `kitten @ ls --match id:N` lists only that window; use `--match-tab window_id:N`
  for its tab-mates.
- kitty < 0.50 does not reject `--type=window-dock`; it opens a plain split in
  the target tab (a fine fallback). The scripts still check which tab the window
  landed in rather than trusting the exit code.
- Several `window-dock`s on one edge nest inside each other (stacked), and a
  dock cannot be split, so the agent strip uses plain splits instead.
- Claude's agent-teams split panes (`teammateMode`) support only tmux and
  iTerm2, not kitty. This plugin covers the subagent case instead.

## Security

`allow_remote_control yes` lets any process in any kitty window drive kitty
(type into windows, read screens), including a prompt-injected agent. A tighter
setup is `allow_remote_control socket-only` plus `remote_control_password`
limited to the actions in use. Not applied yet: test `ksave`/`kload`, the
watchers and these hooks against it first. kitty 0.50.0 also fixes a password
bypass in remote control.
