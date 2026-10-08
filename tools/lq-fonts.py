#!/usr/bin/env python3
"""Builds the letter-quality (LQ) dot tables of the NABU Setup virtual printer.

The virtual printer (nabu-print.py, embedded in nabu-setup-es.sh and
nabu-setup-en.sh) draws its "serif" and "sans" typefaces from two tables of
dot matrices, stored in the LQ dictionary as zlib-compressed, base64-encoded
text. This program produces those tables from two freely licensed typefaces
(see NOTICE.md):

    serif   Courier 10 Pitch       Debian package xfonts-scalable
    sans    DejaVu Sans Mono       Debian package fonts-dejavu-core

Each character becomes a matrix of 36 x 36 positions, like those of a 24-pin
printer: 1/360 inch across and 1/180 inch down, in a cell 600 x 1200 units
(thousandths of a 12-point type size). A dot is fired wherever a printed dot
centered there would be covered by the letter at least THRESHOLD of the way.

It is a maintenance tool: it is not installed on the Pi. It needs Python 3
with Pillow and NumPy.

Usage:
    python3 tools/lq-fonts.py                     print the LQ = {...} block
    python3 tools/lq-fonts.py --check SCRIPT...   compare with the tables in
                                                  the given nabu-setup scripts

Things to tune are at the top: THRESHOLD (higher is lighter), SCALE (width
and height of a typeface inside the cell) and SOURCES (the font files).
"""
import base64, re, sys, textwrap, unicodedata, zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SOURCES = {
    "serif": "/usr/share/fonts/X11/Type1/c0419bt_.pfb",              # Courier 10 Pitch
    "sans": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",   # DejaVu Sans Mono
}
THRESHOLD = 0.6             # fraction of a dot that the letter must cover
SCALE = {"sans": (0.95, 0.88)}   # (width, height): DejaVu is too tall for the cell
COLS, ROWS = 36, 36
DX, DY = 600 / COLS, 1200 / ROWS    # distance between dot positions, in units
BELOW = 8                   # rows below the baseline
RADIUS = 23                 # radius of a printed dot, in units
ACCENTS = [chr(c) for c in (0x301, 0x300, 0x302, 0x303, 0x308, 0x327)]


def charset():
    """ASCII 33 to 126, then the Latin-1 letters made of a letter and one of the
    accents the printer composes. Same order as LQ_CHARS in nabu-print.py."""
    chars = [chr(c) for c in range(33, 127)]
    chars += [chr(c) for c in range(0xC0, 0x100)
              if unicodedata.normalize("NFD", chr(c))[1:] in ACCENTS]
    return chars


def raster(font, ch, scale):
    """ROWS x COLS matrix of 0/1 for one character."""
    pad = 100
    img = Image.new("L", (600 + 2 * pad, 1200 + 2 * pad), 0)
    baseline = pad + 1200 - BELOW * DY
    ImageDraw.Draw(img).text((pad + (600 - font.getlength(ch)) / 2, baseline), ch,
                             font=font, fill=255, anchor="ls")
    if scale != (1.0, 1.0):     # resize around the center of the cell and the baseline
        sx, sy = scale
        cx = pad + 300
        img = img.transform(img.size, Image.AFFINE,
                            (1 / sx, 0, cx * (1 - 1 / sx), 0, 1 / sy, baseline * (1 - 1 / sy)),
                            Image.BICUBIC)
    ink = np.asarray(img, dtype=float) / 255
    r = int(np.ceil(RADIUS))
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    disc = (x * x + y * y <= RADIUS * RADIUS).astype(float)
    out = np.zeros((ROWS, COLS), dtype=np.uint8)
    for row in range(ROWS):
        cy = int(round(pad + (row + 0.5) * DY))
        for col in range(COLS):
            cx = int(round(pad + (col + 0.5) * DX))
            window = ink[cy - r:cy + r + 1, cx - r:cx + r + 1]
            if (window * disc).sum() / disc.sum() >= THRESHOLD:
                out[row, col] = 1
    return out


def build():
    """Returns {typeface: base64 text}, ready for the LQ dictionary."""
    tables = {}
    for name, path in SOURCES.items():
        font = ImageFont.truetype(path, 1000)
        glyphs = []
        for ch in charset():
            m = raster(font, ch, SCALE.get(name, (1.0, 1.0)))
            if ch == "_":           # an unbroken underline from cell to cell
                rows = np.flatnonzero(m.any(axis=1))
                assert len(rows), "empty underscore in " + name
                m[rows, :] = 1
            assert m.any(), "empty character %r in %s" % (ch, name)
            glyphs.append(m)
        raw = np.packbits(np.array(glyphs).reshape(-1)).tobytes()   # 162 bytes each
        tables[name] = base64.b64encode(zlib.compress(raw, 9)).decode("ascii")
    return tables


def block(tables):
    """The LQ = {...} block, laid out as in nabu-print.py."""
    out = ["LQ = {"]
    for name in SOURCES:
        out.append('    "%s": (' % name)
        lines = textwrap.wrap(tables[name], 68)
        out += ['        "%s"' % line for line in lines[:-1]]
        out.append('        "%s"),' % lines[-1])
    return "\n".join(out + ["}"])


def embedded(script, name):
    """Table of one typeface as found in a nabu-setup script."""
    with open(script, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r'"%s": \(\n((?:\s+"[A-Za-z0-9+/=]+"\)?,?\n)+)' % name, src)
    return "".join(re.findall(r'"([A-Za-z0-9+/=]+)"', m.group(1))) if m else None


if __name__ == "__main__":
    tables = build()
    if len(sys.argv) > 2 and sys.argv[1] == "--check":
        same = True
        for script in sys.argv[2:]:
            for name in SOURCES:
                ok = embedded(script, name) == tables[name]
                same &= ok
                print("%s  %-5s  %s" % (script, name, "same" if ok else "DIFFERENT"))
        sys.exit(0 if same else 1)
    print(block(tables))
