#!/usr/bin/env python3
"""Live, readable view of a Claude Code subagent transcript (JSONL).

Usage: agent-view.py <agent-XXXX.jsonl> [agent_type]

Waits for the file to appear, then follows it like `tail -f`, printing the
task prompt, assistant text, tool calls (one line each) and tool results.
Stdlib only. Ctrl-C or closing the window ends it.
"""
import json
import os
import shutil
import subprocess
import sys
import textwrap
import time

DIM, BOLD, RESET = "\033[2m", "\033[1m", "\033[0m"
CYAN, GREEN, RED, YELLOW, MAGENTA = (f"\033[{c}m" for c in (36, 32, 31, 33, 35))

# Which input field best summarises each tool call.
SUMMARY_KEYS = ("description", "command", "file_path", "pattern", "query",
                "url", "path", "relative_path", "name_path", "prompt", "skill")


def width() -> int:
    return max(30, shutil.get_terminal_size((80, 24)).columns - 2)


def one_line(s: str, n: int) -> str:
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1] + "…"


def wrap(s: str, indent: str = "  ") -> str:
    w = width()
    out = []
    for para in str(s).strip().splitlines():
        out.extend(textwrap.wrap(para, w - len(indent)) or [""])
    return "\n".join(indent + line for line in out)


def tool_summary(name: str, inp: dict) -> str:
    if not isinstance(inp, dict):
        return ""
    for k in SUMMARY_KEYS:
        if inp.get(k):
            return one_line(inp[k], width() - len(name) - 6)
    return one_line(json.dumps(inp, ensure_ascii=False), width() - len(name) - 6)


def result_text(content) -> str:
    if isinstance(content, list):
        parts = [c.get("text", "") for c in content if isinstance(c, dict)]
        return "\n".join(p for p in parts if p)
    return str(content or "")


def render(entry: dict, first_user: list) -> None:
    kind = entry.get("type")
    msg = entry.get("message") or {}
    content = msg.get("content")
    if kind == "user":
        if isinstance(content, str):
            if entry.get("isMeta"):
                return
            if not first_user:
                first_user.append(True)
                print(f"{BOLD}{MAGENTA}▶ task{RESET}")
                print(wrap(one_line(content, 1200)))
                print()
            return
        for c in content or []:
            if c.get("type") == "text" and c.get("text", "").startswith("[Request interrupted"):
                return "stopped"
            if c.get("type") == "tool_result":
                text = result_text(c.get("content"))
                lines = text.count("\n") + 1 if text else 0
                if c.get("is_error"):
                    print(f"  {RED}✗ {one_line(text, width() - 6)}{RESET}")
                else:
                    print(f"  {DIM}↳ {lines} line{'s' if lines != 1 else ''}{RESET}")
    elif kind == "assistant":
        for c in content or []:
            t = c.get("type")
            if t == "text" and c.get("text", "").strip():
                print(wrap(c["text"]))
            elif t == "tool_use":
                name = c.get("name", "?")
                print(f"{CYAN}⚙ {BOLD}{name}{RESET} {DIM}{tool_summary(name, c.get('input'))}{RESET}")
    sys.stdout.flush()


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else "agent"
    print(f"{BOLD}{YELLOW}{label}{RESET} {DIM}{os.path.basename(path)}{RESET}\n")
    waited = 0.0
    while not os.path.exists(path):
        if waited > 60:
            print(f"{RED}transcript never appeared: {path}{RESET}")
            time.sleep(3600)
            return
        time.sleep(0.25)
        waited += 0.25
    first_user: list = []
    buf = ""
    with open(path, encoding="utf-8", errors="replace") as f:
        while True:
            chunk = f.read()
            if not chunk:
                time.sleep(0.3)
                continue
            buf += chunk
            *lines, buf = buf.split("\n")
            for line in lines:
                if not line.strip():
                    continue
                try:
                    if render(json.loads(line), first_user) == "stopped":
                        return stopped(path, label)
                except (ValueError, AttributeError, TypeError):
                    pass


def stopped(path: str, label: str) -> None:
    """The user stopped the subagent. SubagentStop does not fire in that case,
    so mark the window, drop agent-dock's state file, and close by exiting."""
    print(f"\n{RED}{BOLD}✖ stopped by user{RESET}")
    sys.stdout.flush()
    agent_id = os.path.basename(path)[len("agent-"):-len(".jsonl")]
    kitten = "/Applications/kitty.app/Contents/MacOS/kitten"
    if not os.path.exists(kitten):
        kitten = shutil.which("kitten") or "kitten"
    if os.environ.get("KITTY_WINDOW_ID"):
        subprocess.run([kitten, "@", "set-window-title", "--match", f"id:{os.environ['KITTY_WINDOW_ID']}",
                        f"✖ {label} · {agent_id[:7]}"], capture_output=True, timeout=5)
    try:
        os.remove(os.path.join(os.environ.get("TMPDIR", "/tmp"), "claude-kitty-agents", agent_id))
    except OSError:
        pass
    try:
        linger = float(os.environ.get("KITTY_AGENT_LINGER", "8"))
    except ValueError:
        linger = 8.0
    if linger <= 0:
        time.sleep(10 ** 9)
    time.sleep(linger)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
