#!/usr/bin/env python3
"""Renders box.png: the StagePlotiphar badge mark shown on the boot splash.

Recreates the plotiphar.com navbar mark (a teal rounded-square badge holding
a ringed dot, evoking a stage-plot floor marker) at boot-splash resolution.
Colors are sampled from the live site's computed styles:
  badge gradient  #0d9488 -> #2dd4bf (135deg)
  dot/ring        white, 90%/40% opacity
"""

import sys
from PIL import Image, ImageDraw

SUPERSAMPLE = 4
SIZE = 256 * SUPERSAMPLE

BADGE_MARGIN = 20 * SUPERSAMPLE
BADGE_RADIUS = 62 * SUPERSAMPLE

TEAL_DARK = (0x0D, 0x94, 0x88)
TEAL_LIGHT = (0x2D, 0xD4, 0xBF)

DOT_RADIUS = 30 * SUPERSAMPLE
RING_RADIUS = 54 * SUPERSAMPLE
RING_WIDTH = 9 * SUPERSAMPLE


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


def main(out_path):
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    badge_box = (BADGE_MARGIN, BADGE_MARGIN, SIZE - BADGE_MARGIN, SIZE - BADGE_MARGIN)
    badge_size = badge_box[2] - badge_box[0]

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(badge_box, radius=BADGE_RADIUS, fill=255)

    gradient = diagonal_gradient(badge_size, TEAL_DARK, TEAL_LIGHT)
    gradient_full = Image.new("RGB", (SIZE, SIZE))
    gradient_full.paste(gradient, (badge_box[0], badge_box[1]))

    canvas = Image.composite(gradient_full.convert("RGBA"), canvas, mask)

    cx = cy = SIZE // 2
    draw = ImageDraw.Draw(canvas)
    draw.ellipse(
        (cx - RING_RADIUS, cy - RING_RADIUS, cx + RING_RADIUS, cy + RING_RADIUS),
        outline=(255, 255, 255, round(255 * 0.4)),
        width=RING_WIDTH,
    )
    draw.ellipse(
        (cx - DOT_RADIUS, cy - DOT_RADIUS, cx + DOT_RADIUS, cy + DOT_RADIUS),
        fill=(255, 255, 255, round(255 * 0.9)),
    )

    final = canvas.resize((SIZE // SUPERSAMPLE, SIZE // SUPERSAMPLE), Image.LANCZOS)
    final.save(out_path)


if __name__ == "__main__":
    main(sys.argv[1])
