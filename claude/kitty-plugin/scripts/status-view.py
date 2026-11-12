#!/usr/bin/env python3
"""STATUS window: every Claude Code session in this kitty tab.

Usage: status-view.py            (run inside the STATUS window; older
                                  versions passed a window id, now ignored)

Per session (a window in this tab running `claude`), refreshed every second:
- state + current action: kitty Program Status (OSC 7501) of that window
- model, effort, context, prompt cache, cost, time, lines, dir, branch: the
  status-line payload ~/.claude/statusline-command.sh saves to
  $TMPDIR/claude-kitty-status/<window id>.json
- its subagents: windows opened by agent-dock.sh (claude_agent_owner var)
Account-wide rate limits are shown once at the bottom.
Restarts itself when this file changes.
"""
import json
import os
import shutil
import subprocess
import sys
import time

KITTEN = "/Applications/kitty.app/Contents/MacOS/kitten"
if not os.path.exists(KITTEN):
    KITTEN = shutil.which("kitten") or "kitten"
SELF = os.environ.get("KITTY_WINDOW_ID", "")
PAYLOAD_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "claude-kitty-status")
DONE_KEEP = 120  # seconds a finished subagent stays listed

R, DIM, B = "\033[0m", "\033[2m", "\033[1m"
GREEN, YELLOW, RED, MAGENTA, BLUE, CYAN = (
    "\033[32m", "\033[33m", "\033[31m", "\033[35m", "\033[38;5;111m", "\033[36m")
STATE_COLORS = {"working": YELLOW, "done": GREEN, "idle": GREEN, "failed": RED, "error": RED}


def kitty_ls():
    try:
        out = subprocess.run([KITTEN, "@", "ls"], capture_output=True, text=True, timeout=5)
        return json.loads(out.stdout) if out.returncode == 0 else None
    except Exception:
        return None


def load_payload(wid):
    path = os.path.join(PAYLOAD_DIR, f"{wid}.json")
    try:
        with open(path) as f:
            return json.load(f), os.stat(path).st_mtime
    except Exception:
        return {}, 0.0


_git = {}


def git_branch(cwd):
    """Branch + '*' when dirty; cached 5 s per directory."""
    if not cwd:
        return ""
    now = time.time()
    hit = _git.get(cwd)
    if hit and now - hit[0] < 5:
        return hit[1]
    val = ""
    try:
        br = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--short", "HEAD"],
                            capture_output=True, text=True, timeout=2).stdout.strip()
        if br:
            dirty = subprocess.run(["git", "-C", cwd, "status", "--porcelain"],
                                   capture_output=True, text=True, timeout=3).stdout.strip()
            val = br + ("*" if dirty else "")
    except Exception:
        pass
    _git[cwd] = (now, val)
    return val


def dur(sec):
    sec = max(0, int(sec))
    d, h, m, s = sec // 86400, sec % 86400 // 3600, sec % 3600 // 60, sec % 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m {s:02d}s" if m < 10 else f"{m}m"
    return f"{s}s"


def mmss(sec):
    sec = max(0, int(sec))
    return f"{sec // 60}:{sec % 60:02d}"


def tokens(n):
    n = n or 0
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M".replace(".0M", "M")
    if n >= 1000:
        return f"{n / 1000:.0f}k"
    return str(n)


def bar(pct, width=10):
    pct = max(0.0, min(100.0, float(pct or 0)))
    color = GREEN if pct < 60 else YELLOW if pct < 80 else RED
    filled = int(pct / 100 * width + 0.5)
    return f"{color}{'●' * filled}{DIM}{'○' * (width - filled)}{R} {color}{pct:3.0f}%{R}"


def visible_len(s):
    out, i = 0, 0
    while i < len(s):
        if s[i] == "\033":
            j = s.find("m", i)
            i = j + 1 if j != -1 else len(s)
            continue
        out += 1
        i += 1
    return out


def fit(s, cols):
    if visible_len(s) <= cols:
        return s
    out, n, i = [], 0, 0
    while i < len(s) and n < cols - 1:
        if s[i] == "\033":
            j = s.find("m", i)
            j = j if j != -1 else len(s) - 1
            out.append(s[i:j + 1])
            i = j + 1
            continue
        out.append(s[i])
        n += 1
        i += 1
    return "".join(out) + "…" + R


def lr(left, right, cols):
    gap = cols - visible_len(left) - visible_len(right)
    return left + " " * gap + right if gap >= 1 else left


def is_claude(w):
    uv = w.get("user_vars") or {}
    if uv.get("claude_role") or uv.get("claude_agent"):
        return False
    for p in w.get("foreground_processes") or []:
        cmd = (p.get("cmdline") or [""])[0]
        if os.path.basename(cmd) == "claude":
            return True
    return False


def session_lines(cols, w, p, agents_running, agents_done, now, multi):
    out = []
    claude = None
    for ps in w.get("program_status") or []:
        if ps.get("app") == "claude-code":
            claude = ps
    state = (claude or {}).get("state") or "running"
    head = f"{STATE_COLORS.get(state, MAGENTA)}● {state}{R}"
    model = (p.get("model") or {}).get("display_name", "")
    effort = (p.get("effort") or {}).get("level", "")
    extras = [x for x in (effort,
                          "thinking" if (p.get("thinking") or {}).get("enabled") else "",
                          "fast" if p.get("fast_mode") else "") if x]
    if model:
        head += f"  {BLUE}{model}{R}"
    if extras:
        head += f" {DIM}· {' · '.join(extras)}{R}"
    name = p.get("session_name") or ""
    tag = f"{B}#{w['id']}{R}"
    room = cols - visible_len(head) - visible_len(tag) - 3
    if multi and name and room > 3:
        tag += f" {DIM}{name if len(name) <= room else name[:room - 1] + '…'}{R}"
    out.append(lr(head, tag if multi else f"{DIM}{time.strftime('%H:%M:%S')}{R}", cols))

    msg = ((claude or {}).get("msg") or "").strip()
    if msg:
        out.append(f"  {DIM}{msg}{R}")
    if p:
        cw = p.get("context_window") or {}
        if cw:
            left = (f"{B}CTX{R} {bar(cw.get('used_percentage'))}  "
                    f"{DIM}{tokens(cw.get('total_input_tokens'))}/{tokens(cw.get('context_window_size'))}{R}")
            pc = p.get("prompt_cache") or {}
            right = ""
            if pc:
                hit, exp = pc.get("hit_ratio"), pc.get("expires_at")
                st = (f"{GREEN}warm {dur(exp - now)}{R}" if pc.get("warm") and exp and exp > now
                      else f"{YELLOW}cold{R}")
                right = f"{DIM}cache{R} {f'{hit * 100:.0f}% ' if hit is not None else ''}{st}"
            out.append(lr(left, right, cols))
        c = p.get("cost") or {}
        cwd = (p.get("workspace") or {}).get("current_dir") or p.get("cwd") or ""
        br = git_branch(cwd)
        parts = []
        if c:
            parts.append(f"{GREEN}${c.get('total_cost_usd', 0):.2f}{R}")
            if c.get("total_duration_ms") is not None:
                parts.append(dur(c["total_duration_ms"] / 1000))
            parts.append(f"{GREEN}+{c.get('total_lines_added', 0)}{R} {RED}−{c.get('total_lines_removed', 0)}{R}")
        loc = f"{CYAN}{os.path.basename(cwd)}{R}" + (f" {YELLOW} {br}{R}" if br else "")
        out.append(f" {DIM}·{R} ".join(parts + [loc]))
        if not multi and name:
            out[-1] = lr(out[-1], f"{DIM}{name}{R}", cols)
    else:
        out.append(f"  {DIM}(no status-line data yet){R}")
    wd = max(1, cols - 10)
    for a in agents_running:
        out.append(f"  {YELLOW}⚙{R} {a['name'][:wd]:<{wd}} {mmss(now - a['start'])}")
    for a in agents_done:
        out.append(f"  {DIM}✔ {a['name'][:wd]:<{wd}} {mmss(a['end'] - a['start'])}{R}")
    return out


def main():
    seen = {}       # agent id -> {"owner", "name", "start", "end"}
    me = os.path.abspath(__file__)
    mtime = os.stat(me).st_mtime
    sys.stdout.write("\033[?25l")
    last_size = None
    while True:
        try:   # restart in place when this script is edited
            if os.stat(me).st_mtime != mtime:
                os.execv(sys.executable, [sys.executable, me])
        except OSError:
            pass
        data = kitty_ls() or []
        now = time.time()
        tabs = [t for osw in data for t in osw.get("tabs", [])]
        all_wins = [w for t in tabs for w in t.get("windows", [])]
        mytab = next((t for t in tabs if any(str(w.get("id")) == SELF for w in t.get("windows", []))), None)
        sessions = sorted((w for w in (mytab or {}).get("windows", []) if is_claude(w)), key=lambda w: w["id"])
        owners = {str(w["id"]) for w in sessions}

        present = set()
        for w in all_wins:
            uv = w.get("user_vars") or {}
            aid, owner = uv.get("claude_agent"), uv.get("claude_agent_owner")
            if not aid or owner not in owners:
                continue
            present.add(aid)
            title = w.get("title", "")
            a = seen.setdefault(aid, {"owner": owner, "name": title[2:] if len(title) > 2 else aid[:7],
                                      "start": now, "end": None})
            if title[:1] in ("✔", "✖") and a["end"] is None:
                a["end"] = now
        for aid in list(seen):
            a = seen[aid]
            if aid not in present and a["end"] is None:
                a["end"] = now
            if a["end"] is not None and now - a["end"] > DONE_KEEP:
                del seen[aid]

        cols, rows = shutil.get_terminal_size((60, 14))
        cols -= 1   # never fill the last column: kitty then treats the line as wrapped
        multi = len(sessions) > 1
        lines, latest = [], ({}, 0.0)
        for w in sessions:
            p, mt = load_payload(w["id"])
            if p.get("rate_limits") and mt > latest[1]:
                latest = (p, mt)
            mine = [a for a in seen.values() if a["owner"] == str(w["id"])]
            run = sorted((a for a in mine if a["end"] is None), key=lambda a: a["start"])
            done = sorted((a for a in mine if a["end"] is not None), key=lambda a: -a["end"])
            if lines:
                lines.append(f"{DIM}{'─' * cols}{R}")
            lines.extend(session_lines(cols, w, p, run, done, now, multi))
        if not sessions:
            lines.append(f"{DIM}○ no Claude session in this tab{R}  {DIM}{time.strftime('%H:%M:%S')}{R}")

        # Account-wide rate limits, once, pinned to the bottom.
        footer = []
        rl = latest[0].get("rate_limits") or {}
        bits = []
        for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
            r = rl.get(key)
            if r:
                reset = r.get("resets_at")
                bits.append(f"{B}{label}{R} {bar(r.get('used_percentage'), 8)}"
                            + (f" {DIM}{dur(reset - now)}{R}" if reset else ""))
        if bits:
            ver = latest[0].get("version", "")
            line = "  ".join(bits)
            footer.append(lr(line, f"{DIM}{time.strftime('%H:%M:%S') if multi else 'v' + ver}{R}", cols)
                          if visible_len(line) + 10 < cols else line)
        room = max(0, rows - len(footer))
        lines = lines[:room] + [""] * max(0, room - len(lines)) + footer
        lines = [fit(line, cols) for line in lines[:rows]]
        # At start and on resize: clear screen AND scrollback. With scrollback
        # left over, a window scrolled up (wheel, resize) shows a stale top
        # row and hides the footer.
        clear = "\033[r\033[2J\033[3J" if (cols, rows) != last_size else ""
        last_size = (cols, rows)
        sys.stdout.write(clear + "\033[H" + "\n".join(line + "\033[K" for line in lines) + "\033[J")
        sys.stdout.flush()
        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h")
