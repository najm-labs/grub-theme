#!/usr/bin/env python3
"""Drive the interactive wizard through a pseudo-terminal on a staged root."""
import os
import pty
import select
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANSWERS = [  # resolution, accent(cyan), verse(2), hints(n), countdown(Enter), timeout, show menu, confirm
    "2560x1440\n", "4\n", "2\n", "n\n", "\n", "8\n", "y\n", "\n",
]


def main():
    tmp = Path(tempfile.mkdtemp())
    try:
        (tmp / "etc/default").mkdir(parents=True)
        (tmp / "boot/grub").mkdir(parents=True)
        (tmp / "etc/default/grub").write_text("GRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT=0\n")
        pid, fd = pty.fork()
        if pid == 0:
            os.execv(str(ROOT / "install.sh"), ["install.sh", "--root", str(tmp)])
        out, i, last = b"", 0, time.time()
        while True:
            ready, _, _ = select.select([fd], [], [], 0.5)
            if ready:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                out, last = out + data, time.time()
            elif i < len(ANSWERS) and time.time() - last > 0.4:
                os.write(fd, ANSWERS[i].encode()); i += 1; last = time.time()
            elif i >= len(ANSWERS) and time.time() - last > 4:
                break
        _, status = os.waitpid(pid, 0)

        grub = (tmp / "etc/default/grub").read_text()
        theme = tmp / "boot/grub/themes/najm"
        checks = {
            "exit status 0": os.waitstatus_to_exitcode(status) == 0,
            "GFXMODE from wizard": 'GRUB_GFXMODE="2560x1440x32,2560x1440,auto"' in grub,
            "timeout 8": "GRUB_TIMEOUT=8" in grub,
            "menu forced visible": "GRUB_TIMEOUT_STYLE=menu" in grub,
            "cyan accent": '"#3BB4C8"' in (theme / "theme.txt").read_text(),
            "hints removed": not (theme / "hints.png").exists(),
            "countdown kept": "__timeout__" in (theme / "theme.txt").read_text(),
            "42px font for 1440p": (theme / "victor_pixel_42.pf2").exists(),
        }
        for name, ok in checks.items():
            print(("  ok   " if ok else "  FAIL ") + name)
        return 0 if all(checks.values()) else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
