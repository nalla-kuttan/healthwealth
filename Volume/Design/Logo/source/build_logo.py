#!/usr/bin/env python3
"""Builds the Volume logo kit ("Engraved Pulse") as filled-outline SVGs.

One heartbeat, engraved in three parallel lines, whose deep dip is the V of Volume.
The top line carries the heartbeat spike and is the "live" line (rose); the engraved
lines below are intaglio blue. All geometry is computed here, so edit numbers, not files.

Run:  python3 build_logo.py            (writes ../final/*.svg)
Wordmark outlines come from volume-wordmark.json, made by outline_wordmark.swift from
Archivo (SIL OFL) at weight 900, width 125, tracking 0.02 em:
  swiftc -O outline_wordmark.swift -o outline_wordmark
  ./outline_wordmark Archivo.ttf VOLUME 100 900 125 0.02 > volume-wordmark.json
"""
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "final"
OUT.mkdir(exist_ok=True)
WORD = json.loads((HERE / "volume-wordmark.json").read_text())

# Palette (matches VolumeUI/Theme.swift)
PAPER, INK = "#EEF1EC", "#13221F"
PAPER_DARK, INK_DARK = "#0E1614", "#E2E9E4"
ROSE, ROSE_DARK = "#A61E63", "#F2689F"
BLUE, BLUE_DARK = "#2A4896", "#8EA6F2"


# ---------------------------------------------------------------- geometry
def offset(pts, d):
    """Parallel offset of an open polyline by d (positive = right of travel = below for L→R)."""
    segs = []
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        length = math.hypot(x2 - x1, y2 - y1)
        nx, ny = -(y2 - y1) / length * d, (x2 - x1) / length * d
        segs.append(((x1 + nx, y1 + ny), (x2 + nx, y2 + ny)))
    out = [segs[0][0]]
    for (a1, a2), (b1, b2) in zip(segs, segs[1:]):
        (x1, y1), (x2, y2), (x3, y3), (x4, y4) = a1, a2, b1, b2
        den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        out.append((x1 + t * (x2 - x1), y1 + t * (y2 - y1)))  # miter join
    out.append(segs[-1][1])
    return out


def outline(pts, width):
    """Filled outline of a stroked polyline: miter joins, butt caps."""
    upper, lower = offset(pts, -width / 2), offset(pts, width / 2)
    ring = upper + lower[::-1]
    return "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in ring) + "Z"


def pulse_lines(count, spacing, width, spike_half, spike_rise, top_y=50, left=14, right=242,
                shoulder=70, spike_x=49.5, dy=0.0):
    """Returns [top line path, engraved line paths...] for the mark on a 256 canvas."""
    run = 128 - shoulder
    bottom = top_y + run * math.tan(math.radians(60))  # arms at exactly 60°
    base = [(left, top_y), (shoulder, top_y), (128, bottom), (256 - shoulder, top_y), (right, top_y)]
    top = [(left, top_y), (spike_x - spike_half, top_y), (spike_x, top_y - spike_rise),
           (spike_x + spike_half, top_y)] + base[1:]
    lines = [top] + [offset(base, k * spacing) for k in range(1, count)]
    shifted = [[(x, y + dy) for x, y in line] for line in lines]
    paths = [outline(line, width) for line in shifted]
    # Fill the spike's counter so it reads as one solid heartbeat peak, not a letter A.
    spike = [(spike_x - spike_half, top_y + width / 2), (spike_x, top_y - spike_rise),
             (spike_x + spike_half, top_y + width / 2)]
    paths[0] += "M" + "L".join(f"{x:.2f} {y + dy:.2f}" for x, y in spike) + "Z"
    return paths


# Master: three lines, 11 u wide on 20 u centres (gap 9 u ≈ 1/28 of the mark).
MASTER = dict(count=3, spacing=20, width=11, spike_half=7.5, spike_rise=22, dy=2)
# Reversed (light on dark) reads heavier, so the lines are thinned.
REVERSED = dict(MASTER, width=10)
# Small cut (≤ 32 px): two heavier lines and a wider spike so it survives at 16 px.
SMALL = dict(count=2, spacing=34, width=20, spike_half=14, spike_rise=28, top_y=56, left=8, right=248,
             shoulder=72, spike_x=40, dy=4)


def symbol_body(params, live, engraved):
    paths = pulse_lines(**params)
    body = f'<path fill="{live}" d="{paths[0]}"/>'
    body += "".join(f'<path fill="{engraved}" d="{p}"/>' for p in paths[1:])
    return body


def svg(width, height, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:g} {height:g}" '
            f'width="{width:g}" height="{height:g}"><title>{title}</title>{body}</svg>\n')


def write(name, content):
    (OUT / name).write_text(content)
    return name


def wordmark(cap, fill, x=0.0, y=0.0):
    s = cap / WORD["capHeight"]
    return (f'<g transform="translate({x:.2f} {y:.2f}) scale({s:.5f})">'
            f'<path fill="{fill}" d="{WORD["d"]}"/></g>'), WORD["width"] * s


# ---------------------------------------------------------------- outputs
def main():
    written = []
    themes = {"": (ROSE, BLUE, INK, MASTER), "-dark": (ROSE_DARK, BLUE_DARK, INK_DARK, REVERSED)}

    for suffix, (rose, blue, ink, params) in themes.items():
        sym = symbol_body(params, rose, blue)
        written.append(write(f"volume-symbol{suffix}.svg", svg(256, 256, sym, "Volume")))
        written.append(write(f"volume-symbol-small{suffix}.svg",
                             svg(256, 256, symbol_body(SMALL, rose, blue), "Volume (small sizes)")))

        # Horizontal lockup: wordmark cap height = 36 % of symbol height, gap = 2 × line width × 2.5
        cap, gap = 92, 56
        word, ww = wordmark(cap, ink, 256 + gap, (256 - cap) / 2)
        written.append(write(f"volume-horizontal{suffix}.svg",
                             svg(round(256 + gap + ww), 256, f"<g>{sym}</g>{word}", "Volume")))

        # Stacked lockup: symbol centred over the wordmark.
        cap_s, gap_s = 72, 40
        word_s, ww_s = wordmark(cap_s, ink, 0, 256 + gap_s)
        x_sym = (ww_s - 256) / 2
        written.append(write(f"volume-stacked{suffix}.svg",
                             svg(round(ww_s), 256 + gap_s + cap_s,
                                 f'<g transform="translate({x_sym:.2f} 0)">{sym}</g>{word_s}', "Volume")))

        # Wordmark only.
        word_o, ww_o = wordmark(100, ink)
        written.append(write(f"volume-wordmark{suffix}.svg", svg(round(ww_o), 100, word_o, "Volume")))

    # iOS app icon masters: full-bleed 1024 square (iOS applies the corner mask).
    # Mark spans ~64 % of the tile, nudged 2 % above centre for optical balance.
    for suffix, bg, rose, blue, params in (("", PAPER, ROSE, BLUE, MASTER),
                                           ("-dark", PAPER_DARK, ROSE_DARK, BLUE_DARK, REVERSED)):
        scale = 1024 * 0.64 / 228
        tx = 512 - 128 * scale
        ty = 512 - 128 * scale - 1024 * 0.02
        body = (f'<rect width="1024" height="1024" fill="{bg}"/>'
                f'<g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})">{symbol_body(params, rose, blue)}</g>')
        written.append(write(f"volume-app-icon{suffix}.svg", svg(1024, 1024, body, "Volume app icon")))

    print("\n".join(written))


if __name__ == "__main__":
    main()
