#!/usr/bin/env python3
"""Renders box.png: the StagePlotiphar logo lockup shown on the boot splash.

Recreates the plotiphar.com navbar mark (a teal rounded-square badge holding
a ringed dot, evoking a stage-plot floor marker) plus the "Stage"/"Plotiphar"
wordmark, stacked for a centered splash-screen logo. Colors and the font
weight are sampled from the live site's computed styles:
  badge gradient   #0d9488 -> #2dd4bf (135deg)
  dot/ring         white, 90%/40% opacity
  wordmark         "Stage" white, "Plotiphar" #14b8a6, Inter (site uses
                    GeistSans; Inter is the closest match available in
                    nixpkgs) at variable weight 700
"""

import sys
from PIL import Image, ImageDraw, ImageFont

SUPERSAMPLE = 4

CANVAS_W = 520
CANVAS_H = 300

BADGE_SIZE = 176
BADGE_TOP = 6
BADGE_RADIUS = 44

TEAL_DARK = (0x0D, 0x94, 0x88)
TEAL_LIGHT = (0x2D, 0xD4, 0xBF)
TEAL_ACCENT = (0x14, 0xB8, 0xA6)
WHITE = (0xFF, 0xFF, 0xFF)

DOT_RADIUS = 24
RING_RADIUS = 43
RING_WIDTH = 7

WORDMARK_GAP = 26
WORDMARK_SIZE = 46


def diagonal_gradient(size, start, end):
    """135deg linear gradient (top-left -> bottom-right)."""
    gradient = Image.new("RGB", (size, size))
    pixels = gradient.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(
                round(start[c] + (end[c] - start[c]) * t) for c in range(3)
            )
    return gradient


def draw_badge(canvas, top_left):
    size = BADGE_SIZE * SUPERSAMPLE
    x0, y0 = top_left

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=BADGE_RADIUS * SUPERSAMPLE, fill=255
    )

    gradient = diagonal_gradient(size, TEAL_DARK, TEAL_LIGHT).convert("RGBA")
    badge = Image.composite(gradient, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask)

    draw = ImageDraw.Draw(badge)
    cx = cy = size // 2
    ring_r = RING_RADIUS * SUPERSAMPLE
    dot_r = DOT_RADIUS * SUPERSAMPLE
    draw.ellipse(
        (cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r),
        outline=(*WHITE, round(255 * 0.4)),
        width=RING_WIDTH * SUPERSAMPLE,
    )
    draw.ellipse(
        (cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r),
        fill=(*WHITE, round(255 * 0.9)),
    )

    canvas.alpha_composite(badge, (x0, y0))


def draw_wordmark(canvas, font_path, baseline_top):
    font = ImageFont.truetype(font_path, WORDMARK_SIZE * SUPERSAMPLE)
    if "Weight" in {axis["name"].decode() for axis in font.get_variation_axes()}:
        font.set_variation_by_axes([700])

    draw = ImageDraw.Draw(canvas)

    stage_bbox = draw.textbbox((0, 0), "Stage", font=font)
    plotiphar_bbox = draw.textbbox((0, 0), "Plotiphar", font=font)
    stage_w = stage_bbox[2] - stage_bbox[0]
    total_w = stage_w + (plotiphar_bbox[2] - plotiphar_bbox[0])

    x = (canvas.width - total_w) // 2
    y = baseline_top * SUPERSAMPLE

    draw.text((x - stage_bbox[0], y), "Stage", font=font, fill=(*WHITE, 255))
    draw.text(
        (x + stage_w - plotiphar_bbox[0], y),
        "Plotiphar",
        font=font,
        fill=(*TEAL_ACCENT, 255),
    )


def main(out_path, font_path):
    w, h = CANVAS_W * SUPERSAMPLE, CANVAS_H * SUPERSAMPLE
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    badge_x = (CANVAS_W - BADGE_SIZE) // 2 * SUPERSAMPLE
    draw_badge(canvas, (badge_x, BADGE_TOP * SUPERSAMPLE))
    draw_wordmark(canvas, font_path, BADGE_TOP + BADGE_SIZE + WORDMARK_GAP)

    final = canvas.resize((CANVAS_W, CANVAS_H), Image.LANCZOS)
    final.save(out_path)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
