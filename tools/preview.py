#!/usr/bin/env python3
"""Render a theme with a *real* GRUB inside QEMU and save a PNG screenshot.

    tools/preview.py themes/1920x1080 -r 1920x1080 -o docs/preview/1920x1080.png

Needs: grub-mkrescue (+ grub-pc-bin), xorriso, mtools, qemu-system-x86_64, Pillow.
Debian/Ubuntu:  apt install grub-pc-bin grub-common xorriso mtools qemu-system-x86
"""
import argparse
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image

ENTRIES = [
    "Arch Linux",
    "Advanced options for Arch Linux",
    "Windows Boot Manager (on /dev/nvme0n1p1)",
    "UEFI Firmware Settings",
]

CFG = """\
insmod all_video
insmod gfxterm
insmod gfxmenu
insmod png
set gfxmode={res}x32,{res},auto
set gfxpayload=keep
terminal_output gfxterm
{loadfonts}
set theme=/boot/grub/themes/najm/theme.txt
export theme
set timeout={timeout}
set default={default}
{entries}
"""


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)


def monitor(sock_path, command, wait=0.4):
    s = socket.socket(socket.AF_UNIX)
    for _ in range(50):
        try:
            s.connect(sock_path)
            break
        except OSError:
            time.sleep(0.2)
    s.settimeout(2)
    try:
        s.recv(4096)
    except OSError:
        pass
    s.sendall(command.encode() + b"\n")
    time.sleep(wait)
    s.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme", help="theme directory (contains theme.txt)")
    ap.add_argument("-r", "--resolution", required=True)
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--timeout", type=int, default=12, help="GRUB countdown shown in the shot")
    ap.add_argument("--shot-at", type=float, default=6.0, help="seconds after boot to capture")
    ap.add_argument("--uefi", action="store_true",
                    help="boot via OVMF/GOP (supports ultrawide and other modes BIOS VBE lacks)")
    ap.add_argument("--select", type=int, default=0, help="highlighted entry index")
    ap.add_argument("--entry", action="append", help="custom menu entry (repeatable)")
    a = ap.parse_args()

    for tool in ("grub-mkrescue", "qemu-system-x86_64", "xorriso"):
        if not shutil.which(tool):
            sys.exit(f"missing {tool}")
    w, h = (int(x) for x in a.resolution.lower().split("x"))
    entries = a.entry or ENTRIES
    work = Path(tempfile.mkdtemp(prefix="najm-preview-"))
    try:
        iso_dir = work / "iso"
        shutil.copytree(a.theme, iso_dir / "boot/grub/themes/najm")
        body = "\n".join(f'menuentry "{e}" {{ true }}' for e in entries)
        (iso_dir / "boot/grub").mkdir(parents=True, exist_ok=True)
        # grub-mkconfig's 00_header emits one `loadfont` per *.pf2 in the theme dir
        fonts = "\n".join(f"loadfont /boot/grub/themes/najm/{f.name}"
                          for f in sorted(Path(a.theme).glob("*.pf2")))
        (iso_dir / "boot/grub/grub.cfg").write_text(
            CFG.format(res=a.resolution, timeout=a.timeout, default=0, entries=body,
                       loadfonts=fonts))
        iso = work / "t.iso"
        run(["grub-mkrescue", "-o", str(iso), str(iso_dir)])

        sock = str(work / "mon.sock")
        vram = max(16, (w * h * 4 * 2) // (1024 * 1024) + 8)
        vram = 1 << (vram - 1).bit_length()  # QEMU wants a power of two
        cmd = ["qemu-system-x86_64", "-m", "512", "-display", "none", "-cdrom", str(iso),
               "-boot", "d", "-monitor", f"unix:{sock},server,nowait", "-no-reboot"]
        if a.uefi:
            fw = next((p for p in ("/usr/share/ovmf/OVMF.fd", "/usr/share/OVMF/OVMF.fd",
                                   "/usr/share/edk2/ovmf/OVMF.fd") if os.path.exists(p)), None)
            if not fw:
                sys.exit("--uefi needs OVMF (apt install ovmf)")
            cmd += ["-bios", fw, "-vga", "none",
                    "-device", f"bochs-display,vgamem={vram * 1024 * 1024},xres={w},yres={h}"]
        else:
            cmd += ["-device", f"VGA,vgamem_mb={vram}"]
        qemu = subprocess.Popen(cmd,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(a.shot_at)
            for _ in range(a.select):
                monitor(sock, "sendkey down")
            ppm = work / "shot.ppm"
            monitor(sock, f"screendump {ppm}", wait=1.5)
            img = Image.open(ppm).convert("RGB")
        finally:
            qemu.kill()
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        img.save(a.out, optimize=True)
        print(f"{a.out}: {img.width}x{img.height}" + ("" if img.size == (w, h) else f"  (WARNING: asked {w}x{h})"))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
