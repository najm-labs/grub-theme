#!/usr/bin/env python3
"""Najm GRUB theme generator.

Builds a complete GRUB theme directory (theme.txt, PNG decorations, pixel font)
for any screen resolution, accent colour and pair of Arabic verses.

    ./build.py --all                                  # rebuild themes/ (prebuilt set)
    ./build.py -r 2560x1440 -o out/                   # one resolution
    ./build.py -r 1920x1080 --accent "#3BB4C8" --verse ships -o out/
    ./build.py -r 1920x1080 --vertical "..." --horizontal "..." -o out/

Needs Python 3.8+ and Pillow.  Arabic shaping uses libraqm when Pillow has it,
otherwise the pure-python `arabic-reshaper` + `python-bidi` pair.
"""
import argparse
import math
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
from pf2 import PF2  # noqa: E402

try:
    from PIL import Image, ImageDraw, ImageFont, features
except ImportError:  # pragma: no cover
    sys.exit("build.py needs Pillow:  pip install pillow   (or your distro's python-pillow)")

FONT_DIR = ROOT / "assets" / "fonts"
ARABIC_FONT = FONT_DIR / "amiri.woff"
SS = 4  # supersampling factor for the PNG labels

GRAY = (154, 154, 154)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)

def _read_data(name):
    return [ln for ln in (ROOT / "data" / name).read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")]


ACCENTS = dict(ln.split("\t") for ln in _read_data("accents.tsv"))
# Resolutions shipped pre-built in themes/ (any other WxH can still be built).
PREBUILT = _read_data("resolutions.txt")


# --------------------------------------------------------------------- data
def load_verses():
    verses = {}
    for line in (ROOT / "data" / "verses.tsv").read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            vid, vert, horiz, poet = line.split("\t")
            verses[vid] = dict(vertical=vert, horizontal=horiz, poet=poet)
    return verses


def parse_accent(value):
    value = ACCENTS.get(value.lower(), value)
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", value.strip())
    if not m:
        sys.exit(f"invalid accent '{value}': use a preset ({', '.join(ACCENTS)}) or #RRGGBB")
    hexv = m.group(1).upper()
    return "#" + hexv, tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))


def parse_resolution(value):
    m = re.fullmatch(r"(\d{3,5})x(\d{3,5})", value.strip().lower())
    if not m:
        sys.exit(f"invalid resolution '{value}': expected WxH, e.g. 1920x1080")
    w, h = int(m.group(1)), int(m.group(2))
    if w < 640 or h < 480:
        sys.exit("resolution must be at least 640x480")
    return w, h


# -------------------------------------------------------------- arabic text
_RAQM = features.check("raqm") and not os.environ.get("NAJM_NO_RAQM")


def _shaper():
    if _RAQM:
        return None
    try:
        import arabic_reshaper
        from bidi.algorithm import get_display
    except ImportError:
        sys.exit(
            "Arabic text needs libraqm in Pillow, or:  pip install arabic-reshaper python-bidi"
        )
    return lambda t: get_display(arabic_reshaper.reshape(t))


_SHAPE = _shaper()


def arabic_font(size):
    engine = ImageFont.Layout.RAQM if _RAQM else ImageFont.Layout.BASIC
    return ImageFont.truetype(str(ARABIC_FONT), size, layout_engine=engine)


def label(text, size, color):
    """Right-to-left label as a tight RGB image on black."""
    font = arabic_font(size * SS)
    kw = dict(direction="rtl", language="ar") if _RAQM else {}
    if _SHAPE:
        text = _SHAPE(text)
    box = font.getbbox(text, anchor="ls", **kw)
    pad = SS * 2
    width = box[2] - box[0] + pad * 2
    height = round(size * 1.7 * SS)
    img = Image.new("RGB", (width, height), BLACK)
    ImageDraw.Draw(img).text((width - pad, round(height * 0.68)), text, font=font,
                             fill=color, anchor="rs", **kw)
    return img.resize((max(1, width // SS), height // SS), Image.LANCZOS)


def vertical_label(text, size, color):
    return label(text, size, color).rotate(90, expand=True)


# ------------------------------------------------------------- hints strip
def hints_row(s):
    key, icon, gap = round(18 * s), round(12 * s), round(7 * s)
    pitch, height = round(116 * s), round(26 * s)
    width = pitch * 2 + key + gap + icon + round(4 * s)
    k = SS
    img = Image.new("RGB", (width * k, height * k), BLACK)
    d = ImageDraw.Draw(img)
    cy = height * k // 2

    def keycap(x):
        d.rounded_rectangle((x * k, cy - key * k // 2, (x + key) * k, cy + key * k // 2),
                            radius=int(key * k * 0.18), fill=WHITE)
        return x * k, cy - key * k // 2

    def enter_arrow(x0, y0):
        u = key * k / 18
        d.line([(x0 + 13 * u, y0 + 5 * u), (x0 + 13 * u, y0 + 11 * u), (x0 + 5.5 * u, y0 + 11 * u)],
               fill=BLACK, width=max(1, int(1.6 * u)))
        d.polygon([(x0 + 4 * u, y0 + 11 * u), (x0 + 7.5 * u, y0 + 8.6 * u), (x0 + 7.5 * u, y0 + 13.4 * u)],
                  fill=BLACK)

    def letter(x0, y0, ch):
        # drawn geometrically: the bundled Amiri subset has no Latin glyphs
        u = key * k / 18
        cx, cyy = x0 + key * k / 2, y0 + key * k / 2
        lw = max(2, int(1.6 * u))
        hw, hh = 3.4 * u, 4.6 * u
        if ch == "E":
            left = cx - hw
            d.line([(left + lw / 2, cyy - hh), (left + lw / 2, cyy + hh)], fill=BLACK, width=lw)
            for yy in (cyy - hh + lw / 2, cyy, cyy + hh - lw / 2):
                d.line([(left, yy), (cx + hw, yy)], fill=BLACK, width=lw)
        else:
            d.arc((cx - hw - 1.2 * u, cyy - hh, cx + hw + 1.2 * u, cyy + hh), 42, 318, fill=BLACK, width=lw)

    def play_box(x):
        x0, y0, size = x * k, cy - icon * k // 2, icon * k
        d.rounded_rectangle((x0, y0, x0 + size, y0 + size), radius=size // 6, fill=WHITE)
        d.polygon([(x0 + size * 0.38, y0 + size * 0.28), (x0 + size * 0.38, y0 + size * 0.72),
                   (x0 + size * 0.72, y0 + size * 0.5)], fill=BLACK)

    def gear(x):
        cx, cyy, r = x * k + icon * k / 2, cy, icon * k / 2
        pts = []
        for i in range(16):
            ang = math.pi * 2 * i / 16
            rad = r if i % 2 == 0 else r * 0.78
            pts += [(cx + rad * math.cos(ang - 0.12), cyy + rad * math.sin(ang - 0.12)),
                    (cx + rad * math.cos(ang + 0.12), cyy + rad * math.sin(ang + 0.12))]
        d.polygon(pts, fill=GRAY)
        d.ellipse((cx - r * 0.34, cyy - r * 0.34, cx + r * 0.34, cyy + r * 0.34), fill=BLACK)

    def terminal(x):
        x0, y0, size = x * k, cy - icon * k // 2, icon * k
        w = max(1, size // 10)
        d.rounded_rectangle((x0, y0, x0 + size, y0 + size), radius=size // 6, outline=GRAY, width=w)
        d.line([(x0 + size * 0.28, y0 + size * 0.32), (x0 + size * 0.46, y0 + size * 0.48),
                (x0 + size * 0.28, y0 + size * 0.64)], fill=GRAY, width=w)
        d.line([(x0 + size * 0.54, y0 + size * 0.68), (x0 + size * 0.74, y0 + size * 0.68)],
               fill=GRAY, width=w)

    enter_arrow(*keycap(0)); play_box(key + gap)
    letter(*keycap(pitch), "E"); gear(pitch + key + gap)
    letter(*keycap(pitch * 2), "C"); terminal(pitch * 2 + key + gap)
    return img.resize((width, height), Image.LANCZOS)


# --------------------------------------------------------------- font sizing
def font_unit(scale):
    """Pixel-grid unit for the menu font: 2 -> 21px, 3 -> 32px, 4 -> 42px ..."""
    return max(2, int(scale * 2 + 0.5))


def make_font(unit):
    if unit == 2:
        return PF2.load(FONT_DIR / "victor_pixel_21.pf2")
    if unit == 3:
        return PF2.load(FONT_DIR / "victor_pixel_32.pf2")
    return PF2.load(FONT_DIR / "victor_pixel_21.pf2").rescaled(unit)


# ----------------------------------------------------------------- theme.txt
def theme_text(w, h, font, unit, s, sizes, accent_hex, opts):
    px = lambda v: round(v * s)
    m = px(12)
    f = font.name
    out = [f"# Najm GRUB theme - {w}x{h}",
           f"# generated by build.py (scale {s:.3f}, font {font.name}, accent {accent_hex})",
           f'title-text: ""',
           f'title-font: "{f}"',
           'title-color: "#ffffff"',
           f'message-font: "{f}"',
           'message-color: "#ffffff"',
           'message-bg-color: "#000000"',
           'desktop-color: "#000000"',
           f'terminal-font: "{f}"',
           'terminal-left: "0"', 'terminal-top: "0"',
           'terminal-width: "100%"', 'terminal-height: "100%"', 'terminal-border: "0"', ""]

    def image(left, top, key, name):
        iw, ih = sizes[key]
        out.extend(["+ image {", f"left = {left(iw, ih)}", f"top = {top(iw, ih)}",
                    f"width = {iw}", f"height = {ih}", f'file = "{name}"', "}", ""])

    if opts["verses"]:
        image(lambda a, b: m, lambda a, b: m, "vertical", "vertical.png")
        image(lambda a, b: f"100%-{a + m}", lambda a, b: m, "horizontal", "horizontal.png")
        image(lambda a, b: m, lambda a, b: f"100%-{b + m}", "horizontal", "horizontal.png")
        image(lambda a, b: f"100%-{a + m}", lambda a, b: f"100%-{b + m}", "vertical", "vertical.png")
    if opts["hints"]:
        image(lambda a, b: f"50%-{a // 2}", lambda a, b: f"100%-{b + px(14)}", "hints", "hints.png")

    # Menu width is in pixels so ~45 characters always fit (long entries such as
    # "Windows Boot Manager (on /dev/nvme0n1p1)" used to be clipped at low resolutions).
    narrow = w < 1280
    menu_w = max(round(w * (0.60 if narrow else 0.40)), 270 * unit)
    menu_l = min(round(w * (0.20 if narrow else 0.33)), round(w * 0.97) - menu_w)
    out.extend([
        "+ boot_menu {",
        f"left = {menu_l}", "top = 21%",
        f"width = {menu_w}", "height = 50%",
        f'item_font = "{f}"', f'selected_item_font = "{f}"',
        'item_color = "#ffffff"', f'selected_item_color = "{accent_hex}"',
        "icon_width = 0", "icon_height = 0",
        f"item_height = {11 * unit}", "item_padding = 0", "item_icon_space = 0",
        f"item_spacing = {3 * unit}", "scrollbar = false", "}", ""])

    if opts["countdown"]:
        bw = px(260)
        out.extend([
            "+ progress_bar {", 'id = "__timeout__"',
            f"left = 50%-{bw // 2}", "top = 80%", f"width = {bw}", f"height = {px(28)}",
            f'font = "{f}"', f'fg_color = "{accent_hex}"', 'bg_color = "#000000"',
            f'border_color = "{accent_hex}"', 'text_color = "#ffffff"',
            'text = "booting in %d..."', "}", ""])
    return "\n".join(out)


# --------------------------------------------------------------------- build
def build(w, h, out, accent="najm", vertical=None, horizontal=None, verses=True,
          hints=True, countdown=True):
    accent_hex, accent_rgb = parse_accent(accent)
    if vertical is None or horizontal is None:
        d = load_verses()["najm"]
        vertical = vertical or d["vertical"]
        horizontal = horizontal or d["horizontal"]
    s = min(w / 1280, h / 720)
    unit = font_unit(s)
    font = make_font(unit)

    out = Path(out)
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    font.save(out / f"victor_pixel_{font.ptsz}.pf2")

    sizes = {}
    if verses:
        v = vertical_label(vertical, round(20 * s), accent_rgb)
        hz = label(horizontal, round(23 * s), GRAY)
        v.save(out / "vertical.png"); hz.save(out / "horizontal.png")
        sizes.update(vertical=v.size, horizontal=hz.size)
    if hints:
        hr = hints_row(s)
        hr.save(out / "hints.png")
        sizes["hints"] = hr.size
    opts = dict(verses=verses, hints=hints, countdown=countdown)
    (out / "theme.txt").write_text(theme_text(w, h, font, unit, s, sizes, accent_hex, opts))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-r", "--resolution", action="append", help="WxH (repeatable)")
    ap.add_argument("--all", action="store_true", help="rebuild the pre-built set into themes/")
    ap.add_argument("-o", "--out", help="output dir (one resolution) or parent dir (several)")
    ap.add_argument("--accent", default="najm", help=f"preset ({', '.join(ACCENTS)}) or #RRGGBB")
    ap.add_argument("--verse", help="verse preset id (see --list-verses)")
    ap.add_argument("--vertical", help="custom vertical text (Arabic)")
    ap.add_argument("--horizontal", help="custom horizontal text (Arabic)")
    ap.add_argument("--no-verses", action="store_true", help="omit the four corner verses")
    ap.add_argument("--no-hints", action="store_true", help="omit the Enter/E/C key hints")
    ap.add_argument("--no-countdown", action="store_true", help="omit the boot countdown bar")
    ap.add_argument("--list-verses", action="store_true")
    ap.add_argument("--list-accents", action="store_true")
    ap.add_argument("--list-resolutions", action="store_true")
    a = ap.parse_args()

    if a.list_verses:
        for k, v in load_verses().items():
            print(f"{k}\t{v['horizontal']}  /  {v['vertical']}\t({v['poet']})")
        return
    if a.list_accents:
        for k, v in ACCENTS.items():
            print(f"{k}\t{v}")
        return
    if a.list_resolutions:
        print("\n".join(PREBUILT))
        return

    vertical, horizontal = a.vertical, a.horizontal
    if a.verse:
        verses = load_verses()
        if a.verse not in verses:
            sys.exit(f"unknown verse '{a.verse}' ({', '.join(verses)})")
        vertical, horizontal = verses[a.verse]["vertical"], verses[a.verse]["horizontal"]
    kw = dict(accent=a.accent, vertical=vertical, horizontal=horizontal, verses=not a.no_verses,
              hints=not a.no_hints, countdown=not a.no_countdown)

    if a.all:
        for res in PREBUILT:
            w, h = parse_resolution(res)
            build(w, h, ROOT / "themes" / res, **kw)
            print("built", res)
        return
    if not a.resolution:
        ap.error("give --resolution WxH (or --all)")
    if not a.out:
        ap.error("give --out DIR")
    for res in a.resolution:
        w, h = parse_resolution(res)
        target = Path(a.out) if len(a.resolution) == 1 else Path(a.out) / res
        build(w, h, target, **kw)
        print("built", target)


if __name__ == "__main__":
    main()
