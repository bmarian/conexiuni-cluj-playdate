#!/usr/bin/env python3
"""Rasterize the vendored pixelarticons SVGs into 1-bit PNGs for the .pdx.

    python tools/icons.py

Writes source/images/icons/<name>-<size>.png, which pdc compiles to .pdi. The
icons are axis-aligned rectangles on a 24x24 grid, so a scanline fill sampled
at pixel centers reproduces them exactly, with no SVG renderer needed.
"""

import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVG_DIR = ROOT / "tools" / "pixelarticons"
OUT_DIR = ROOT / "source" / "images" / "icons"

# 24 is the pack's native grid. 12 is a half-scale point sample: it thins the
# 2px strokes to 1px, which works for outlines but collapses solid shapes.
ICONS = {
    "bus": (24,),
    "map-pin": (24,),
    "heart": (24, 12),
    "reload": (24,),
    "clock": (24, 12),
    "square-alert": (24, 12),
    "calendar": (24,),
    "chevron-left": (12,),
    "chevron-right": (12,),
    "chevron-up": (12,),
    "chevron-down": (12,),
}

TOKEN = re.compile(r"([MmLlHhVvZz])|(-?\d*\.?\d+)")


def parse_path(d):
    """Return a list of closed subpaths (lists of (x, y) points).

    Only M/L/H/V/Z, absolute and relative, which is all pixelarticons uses.
    Anything else raises rather than producing a wrong icon.
    """
    tokens = [(cmd, num) for cmd, num in TOKEN.findall(d)]
    subpaths, current = [], []
    x = y = 0.0
    start_x = start_y = 0.0
    cmd = None
    i = 0

    def take():
        nonlocal i
        c, n = tokens[i]
        if c:
            raise ValueError(f"expected a number, got command {c!r} in {d!r}")
        i += 1
        return float(n)

    while i < len(tokens):
        c, n = tokens[i]
        if c:
            cmd = c
            i += 1
        elif cmd in ("M", "m"):
            # A repeated coordinate pair after a moveto is an implicit lineto.
            cmd = "L" if cmd == "M" else "l"
            continue
        elif cmd is None:
            raise ValueError(f"path data starts with a number: {d!r}")

        if cmd in ("Z", "z"):
            if current:
                subpaths.append(current)
                current = []
            x, y = start_x, start_y
            continue

        if cmd in ("M", "m"):
            if current:
                subpaths.append(current)
                current = []
            dx, dy = take(), take()
            x, y = (dx, dy) if cmd == "M" else (x + dx, y + dy)
            start_x, start_y = x, y
            current.append((x, y))
        elif cmd in ("L", "l"):
            dx, dy = take(), take()
            x, y = (dx, dy) if cmd == "L" else (x + dx, y + dy)
            current.append((x, y))
        elif cmd in ("H", "h"):
            dx = take()
            x = dx if cmd == "H" else x + dx
            current.append((x, y))
        elif cmd in ("V", "v"):
            dy = take()
            y = dy if cmd == "V" else y + dy
            current.append((x, y))
        else:
            raise ValueError(f"unsupported path command {cmd!r} in {d!r}")

    if current:
        subpaths.append(current)
    return subpaths


def winding_at(subpaths, px, py):
    """Nonzero winding number of the point (px, py), SVG's default fill rule."""
    winding = 0
    for points in subpaths:
        for j in range(len(points)):
            x0, y0 = points[j]
            x1, y1 = points[(j + 1) % len(points)]
            if y0 == y1:
                continue
            if y0 <= py < y1:
                direction = 1
            elif y1 <= py < y0:
                direction = -1
            else:
                continue
            # x of the edge at height py; only edges to the right count.
            cross = x0 + (py - y0) * (x1 - x0) / (y1 - y0)
            if cross > px:
                winding += direction
    return winding


def rasterize(svg_text, size):
    """Sample the path at `size`x`size`, returning a row-major list of bools."""
    view = re.search(r'viewBox="([^"]+)"', svg_text)
    _, _, view_w, view_h = (float(v) for v in view.group(1).split())

    subpaths = []
    for d in re.findall(r'\sd="([^"]+)"', svg_text):
        subpaths.extend(parse_path(d))

    # One sample per output pixel, at its center: exact at 24, every other
    # source pixel at 12.
    pixels = []
    for row in range(size):
        for col in range(size):
            px = (col + 0.5) * view_w / size
            py = (row + 0.5) * view_h / size
            pixels.append(winding_at(subpaths, px, py) != 0)
    return pixels


def write_png(path, pixels, size):
    """Write RGBA: opaque black where inked, transparent elsewhere.

    pdc turns the alpha channel into the image's mask.
    """
    raw = bytearray()
    for row in range(size):
        raw.append(0)  # PNG filter type: none
        for col in range(size):
            if pixels[row * size + col]:
                raw += b"\x00\x00\x00\xff"
            else:
                raw += b"\x00\x00\x00\x00"

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def preview(pixels, size):
    return "\n".join(
        "".join("#" if pixels[r * size + c] else "." for c in range(size))
        for r in range(size)
    )


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, sizes in ICONS.items():
        svg_text = (SVG_DIR / f"{name}.svg").read_text(encoding="utf-8")
        for size in sizes:
            write_png(OUT_DIR / f"{name}-{size}.png", rasterize(svg_text, size), size)
        print(f"{name}: {' '.join(str(s) for s in sizes)}")


if __name__ == "__main__":
    main()
