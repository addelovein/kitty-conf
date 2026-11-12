#!/usr/bin/env python3
"""Follow one running Claude Bash command in a kitty split.

Usage: wait-view.py <task output file> <description> <command>

Claude Code writes a foreground Bash command's output live to
<tmp>/claude-<uid>/<project>/<session>/tasks/<id>.output and deletes the file
when the command finishes. This prints the output as it grows; once the file
is gone it marks the window done and closes it after KITTY_WAIT_LINGER
seconds (default 10). A key press during the linger keeps it open until the
next key; KITTY_WAIT_LINGER=0 always keeps it.
"""
import os
import select
import shutil
import subprocess
import sys
import termios
import time
import tty

KITTEN = "/Applications/kitty.app/Contents/MacOS/kitten"
if not os.path.exists(KITTEN):
    KITTEN = shutil.which("kitten") or "kitten"
DIM, R, GREEN, YELLOW = "\033[2m", "\033[0m", "\033[32m", "\033[33m"


def title(t):
    subprocess.run([KITTEN, "@", "set-window-title", "--match",
                    f"id:{os.environ.get('KITTY_WINDOW_ID', '')}", t],
                   capture_output=True)


def wait_key(timeout):
    """True if a key was pressed within timeout seconds (None = forever)."""
    fd = sys.stdin.fileno()
    try:
        old = termios.tcgetattr(fd)
    except termios.error:
        time.sleep(timeout or 0)
        return False
    try:
        tty.setcbreak(fd)
        r, _, _ = select.select([fd], [], [], timeout)
        if r:
            os.read(fd, 16)
            return True
        return False
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def main():
    path, desc, cmd = (sys.argv[1:4] + ["", "", ""])[:3]
    label = (desc or cmd.splitlines()[0] if (desc or cmd) else "command")[:50]
    linger = float(os.environ.get("KITTY_WAIT_LINGER", "10"))
    start = time.time()
    print(f"{YELLOW}⏳ {desc or 'Claude is waiting on'}{R}")
    for line in cmd.splitlines()[:6]:
        print(f"{DIM}$ {line[:400]}{R}")
    print()
    try:
        f = open(path, "rb")
    except OSError:
        print(f"{DIM}(finished before the window opened){R}")
        f = None
    out = sys.stdout.buffer
    while f:
        chunk = f.read(65536)
        if chunk:
            out.write(chunk)
            out.flush()
            continue
        if not os.path.exists(path):        # Claude deletes it when done
            rest = f.read()
            if rest:
                out.write(rest)
                out.flush()
            break
        time.sleep(0.3)

    secs = int(time.time() - start)
    print(f"\n{GREEN}✔ done{R} {DIM}· shown for {secs // 60}m {secs % 60:02d}s{R}")
    title(f"✔ {label}")
    if linger <= 0:
        print(f"{DIM}[any key closes]{R}", end="", flush=True)
        wait_key(None)
        return
    print(f"{DIM}[closes in {linger:.0f}s · any key keeps it]{R}", end="", flush=True)
    if wait_key(linger):
        print(f"\r\033[K{DIM}[kept · any key closes]{R}", end="", flush=True)
        wait_key(None)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
