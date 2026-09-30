#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a shelf of frosted-glass books in the "Dusk" palette, drawn in
the macOS 26 Liquid Glass style: soft gradients, translucent layers and bright
specular rims.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles). It
is not a superellipse; a whole-shape superellipse looks slightly too round.

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette ("Dusk"): one colour family, violet to pink, so nothing clashes.

BG_TOP = "#A98CFF"
BG_DEEP = "#4B2BD6"
BOOK_COLOURS = ["#FF86C3", "#F6EBFF", "#76A8FF", "#D8A2FF"]

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

# (x, width, height) of each book standing on the shelf; the last one leans.
BOOKS = [(226, 118, 360), (356, 136, 450), (504, 106, 330), (622, 122, 390)]
SHELF_Y = 740


def _hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    ra, rb = _hex2rgb(a), _hex2rgb(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(ra, rb))


def _book(i, x, w, h, colour):
    top = SHELF_Y - h
    gid = f"book{i}"
    grad = (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{_mix(colour, "#FFFFFF", 0.28)}"/>'
            f'<stop offset="0.55" stop-color="{colour}"/>'
            f'<stop offset="1" stop-color="{_mix(colour, BG_DEEP, 0.18)}"/></linearGradient>')
    body = [
        f'<rect x="{x}" y="{top}" width="{w}" height="{h}" rx="22" fill="url(#{gid})"/>',
        # curved-spine sheen on the left, soft shade on the right
        f'<rect x="{x + 10}" y="{top + 12}" width="{w * 0.22:.0f}" height="{h - 24}" '
        f'rx="{w * 0.11:.0f}" fill="#FFFFFF" opacity="0.34"/>',
        f'<rect x="{x + w * 0.78:.0f}" y="{top + 8}" width="{w * 0.18:.0f}" height="{h - 16}" '
        f'rx="{w * 0.09:.0f}" fill="{BG_DEEP}" opacity="0.12"/>',
        # frosted bands
        f'<rect x="{x}" y="{top + 44}" width="{w}" height="14" fill="#FFFFFF" opacity="0.5"/>',
        f'<rect x="{x}" y="{SHELF_Y - 62}" width="{w}" height="14" fill="#FFFFFF" opacity="0.5"/>',
        # glass rim
        f'<rect x="{x + 1.5}" y="{top + 1.5}" width="{w - 3}" height="{h - 3}" rx="21" '
        f'fill="none" stroke="url(#rim)" stroke-width="3"/>',
    ]
    if i == 1:  # label plate on the tallest book
        body.append(f'<rect x="{x + 26}" y="{top + 120}" width="{w - 52}" height="{w - 36}" '
                    f'rx="12" fill="#FFFFFF" opacity="0.62"/>')
    if i == len(BOOKS) - 1:  # the leaning book
        body = [f'<g transform="rotate(15 {x} {SHELF_Y})">'] + body + ["</g>"]
    return grad, body


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.85"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.25"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.55"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        '<linearGradient id="shelf" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.70"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.32"/></linearGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        '<filter id="bookshadow" x="-30%" y="-10%" width="160%" height="130%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="12"/><feOffset dx="6" dy="14"/>'
        f'<feFlood flood-color="{BG_DEEP}" flood-opacity="0.6"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    books = []
    for i, ((x, w, h), colour) in enumerate(zip(BOOKS, BOOK_COLOURS)):
        grad, body = _book(i, x, w, h, colour)
        defs.append(grad)
        books += body
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        f'<ellipse cx="520" cy="{SHELF_Y + 8}" rx="320" ry="30" fill="{BG_DEEP}" opacity="0.45"/>',
        f'<rect x="196" y="{SHELF_Y + 18}" width="632" height="60" rx="30" fill="{BG_DEEP}" opacity="0.30"/>',
        '<g filter="url(#bookshadow)">', *books, '</g>',
        f'<rect x="190" y="{SHELF_Y}" width="644" height="60" rx="30" fill="url(#shelf)"/>',
        f'<rect x="191.5" y="{SHELF_Y + 1.5}" width="641" height="57" rx="28.5" fill="none" '
        'stroke="#FFFFFF" stroke-opacity="0.85" stroke-width="3"/>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
