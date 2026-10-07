#!/usr/bin/env python3
"""Minimal GRUB PF2 font reader/writer.

The bundled pixel font is drawn on a coarse "unit" grid (21 px font = 2 px per
unit, 32 px font = 3 px per unit).  That lets us derive crisp copies at any
integer unit size, which is how the theme gets a matching font for every
screen resolution without needing the original TTF.
"""
import struct
import sys
from math import gcd
from pathlib import Path


class Glyph:
    __slots__ = ("w", "h", "xoff", "yoff", "dw", "rows")

    def __init__(self, w, h, xoff, yoff, dw, rows):
        self.w, self.h, self.xoff, self.yoff, self.dw, self.rows = w, h, xoff, yoff, dw, rows


class PF2:
    def __init__(self):
        self.name = self.family = self.weight = self.slant = ""
        self.ptsz = self.maxw = self.maxh = self.asce = self.desc = 0
        self.glyphs = {}

    # ---------------------------------------------------------------- read
    @classmethod
    def load(cls, path):
        d = Path(path).read_bytes()
        if d[:4] != b"FILE" or d[8:12] != b"PFF2":
            raise ValueError(f"{path}: not a PF2 font")
        f = cls()
        p, chix = 12, b""
        s = lambda b: b.rstrip(b"\0").decode()
        while p < len(d):
            tag = d[p:p + 4]
            ln = struct.unpack(">I", d[p + 4:p + 8])[0]
            body = d[p + 8:p + 8 + ln] if tag != b"DATA" else b""
            if tag == b"NAME": f.name = s(body)
            elif tag == b"FAMI": f.family = s(body)
            elif tag == b"WEIG": f.weight = s(body)
            elif tag == b"SLAN": f.slant = s(body)
            elif tag == b"PTSZ": f.ptsz = struct.unpack(">H", body)[0]
            elif tag == b"MAXW": f.maxw = struct.unpack(">H", body)[0]
            elif tag == b"MAXH": f.maxh = struct.unpack(">H", body)[0]
            elif tag == b"ASCE": f.asce = struct.unpack(">H", body)[0]
            elif tag == b"DESC": f.desc = struct.unpack(">H", body)[0]
            elif tag == b"CHIX": chix = body
            if tag == b"DATA":
                break
            p += 8 + ln
        for i in range(len(chix) // 9):
            cp, _flags, off = struct.unpack(">IBI", chix[i * 9:i * 9 + 9])
            w, h, xo, yo, dw = struct.unpack(">HHhhh", d[off:off + 10])
            raw = d[off + 10:off + 10 + (w * h + 7) // 8]
            bits = "".join(f"{b:08b}" for b in raw)[: w * h]
            f.glyphs[cp] = Glyph(w, h, xo, yo, dw, [bits[r * w:(r + 1) * w] for r in range(h)])
        return f

    # --------------------------------------------------------------- write
    def dump(self):
        def sec(tag, body):
            return tag + struct.pack(">I", len(body)) + body

        z = lambda s: s.encode() + b"\0"
        head = b"FILE" + struct.pack(">I", 4) + b"PFF2"
        parts = [
            sec(b"NAME", z(self.name)), sec(b"FAMI", z(self.family)),
            sec(b"WEIG", z(self.weight)), sec(b"SLAN", z(self.slant)),
            sec(b"PTSZ", struct.pack(">H", self.ptsz)),
            sec(b"MAXW", struct.pack(">H", self.maxw)),
            sec(b"MAXH", struct.pack(">H", self.maxh)),
            sec(b"ASCE", struct.pack(">H", self.asce)),
            sec(b"DESC", struct.pack(">H", self.desc)),
        ]
        cps = sorted(self.glyphs)
        data_start = len(head) + sum(map(len, parts)) + 8 + 9 * len(cps) + 8
        chix, blobs, off = b"", [], data_start
        for cp in cps:
            g = self.glyphs[cp]
            bits = "".join(g.rows)
            bits += "0" * (-len(bits) % 8)
            blob = struct.pack(">HHhhh", g.w, g.h, g.xoff, g.yoff, g.dw)
            if bits:
                blob += int(bits, 2).to_bytes(len(bits) // 8, "big")
            chix += struct.pack(">IBI", cp, 0, off)
            blobs.append(blob)
            off += len(blob)
        return (head + b"".join(parts) + sec(b"CHIX", chix)
                + b"DATA" + struct.pack(">I", 0xFFFFFFFF) + b"".join(blobs))

    def save(self, path):
        Path(path).write_bytes(self.dump())

    # -------------------------------------------------------------- scaling
    def unit_size(self):
        """Pixels per grid unit (gcd of all glyph geometry)."""
        g = 0
        for gl in self.glyphs.values():
            for v in (gl.w, gl.h, gl.xoff, gl.yoff, gl.dw):
                g = gcd(g, abs(v))
        return g or 1

    def rescaled(self, unit):
        """Return a copy drawn with `unit` px per grid unit."""
        src = self.unit_size()
        n = PF2()
        n.family, n.weight, n.slant = self.family, self.weight, self.slant
        k = lambda v: v // src * unit
        n.ptsz = round(self.ptsz * unit / src)
        n.maxw, n.maxh, n.asce, n.desc = k(self.maxw), k(self.maxh), k(self.asce), k(self.desc)
        n.name = f"{self.family} Regular {n.ptsz}"
        for cp, g in self.glyphs.items():
            rows = []
            for r in range(0, g.h, src):
                line = "".join(g.rows[r][c] * unit for c in range(0, g.w, src))
                rows += [line] * unit
            n.glyphs[cp] = Glyph(g.w // src * unit, g.h // src * unit,
                                 k(g.xoff), k(g.yoff), k(g.dw), rows)
        return n


if __name__ == "__main__":
    f = PF2.load(sys.argv[1])
    print(f.name, "| unit", f.unit_size(), "| glyphs", len(f.glyphs))
