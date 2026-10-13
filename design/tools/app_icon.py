"""Renders the app icon into the asset catalog.

    python3 design/tools/app_icon.py

A white padlock with a small face, locked in, on a soft indigo-to-purple gradient: the shape of
an Apple icon (one simple glyph on a quiet gradient, no text) in the app's tint family
(design/SYSTEM.md). The face makes the lock a little friendly without becoming a mascot; the
creatures arrive in M1 with their own original art.

One 1024 x 1024 image for every size (the single-size asset format), fully opaque RGB, because
App Store Connect rejects icons with an alpha channel. The system rounds the corners, so the
gradient fills the square. Needs Pillow and NumPy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"
SIZE = 1024
SCALE = 4  # draw large, then downscale: smooth edges without per-shape anti-aliasing

# Near the system's indigo and purple (Apple's colour guidelines, iOS 26 values: indigo
# #6155F5 / #6D7CFF, purple #CB30E0), softened so the two ends sit close in lightness and the
# gradient reads as one colour turning, not as two colours meeting.
TOP = 0x6F73FA  # a light indigo
BOTTOM = 0x8E44E0  # an indigo-leaning purple
GLYPH = 0xFFFFFF
SHADOW = 0x2A1670  # a deep indigo, for the glyph's faint shadow


def rgb(value):
    return np.array([(value >> 16) & 255, (value >> 8) & 255, value & 255], dtype=np.float32) / 255


def to_image(array):
    return Image.fromarray((np.clip(array, 0, 1) * 255).round().astype(np.uint8), "RGB")


def background(s):
    """Top to bottom, light indigo to purple, with a faint glow from above like Apple's icons."""
    ys = (np.arange(s, dtype=np.float32) / s)[:, None]
    xs = (np.arange(s, dtype=np.float32) / s)[None, :]
    # Ease the blend so the middle isn't a muddy halfway colour for long.
    t = (ys * ys * (3 - 2 * ys))[..., None]
    base = rgb(TOP) * (1 - t) + rgb(BOTTOM) * t
    base = np.broadcast_to(base, (s, s, 3))
    glow = np.exp(-(((xs - 0.5) / 0.55) ** 2 + ((ys + 0.05) / 0.45) ** 2))[..., None] * 0.14
    return base * (1 - glow) + 1.0 * glow


def mask(s, draw_shape):
    image = Image.new("L", (s, s), 0)
    draw_shape(ImageDraw.Draw(image), s)
    return image


def glyph_mask(s):
    """The padlock with its face knocked out, as a mask: white where the glyph is."""

    def px(value):
        return value * s

    # The body: a rounded rectangle, a little wider than tall, like SF Symbols' lock. Its
    # corners end before the shackle's legs begin, so the legs meet a straight edge.
    body_box = [px(0.275), px(0.455), px(0.725), px(0.79)]

    def body(draw, s):
        draw.rounded_rectangle(body_box, radius=px(0.08), fill=255)

    # The shackle: an upside-down U whose legs run into the body. An outer arch minus an inner
    # one, so the curve and the legs meet without a seam.
    centre_x, centre_y, legs_end = px(0.5), px(0.36), px(0.5)

    def arch(radius):
        def shape(draw, s):
            draw.ellipse([centre_x - radius, centre_y - radius, centre_x + radius, centre_y + radius], fill=255)
            draw.rectangle([centre_x - radius, centre_y, centre_x + radius, legs_end], fill=255)

        return shape

    shackle = ImageChops.subtract(mask(s, arch(px(0.142))), mask(s, arch(px(0.08))))
    lock = ImageChops.lighter(shackle, mask(s, body))

    # The face, cut out of the body so the gradient shows through: two tall eyes and a smile.
    def face(draw, s):
        for cx in (0.43, 0.57):
            draw.ellipse([px(cx - 0.026), px(0.555), px(cx + 0.026), px(0.627)], fill=255)
        draw.arc([px(0.445), px(0.6), px(0.555), px(0.69)], 25, 155, fill=255, width=int(px(0.022)))
        # Round the smile's ends, as a pen would. Pillow draws an arc's width inwards from its
        # box, so the stroke's centre line runs half a width inside it.
        for angle in (25, 155):
            theta = np.radians(angle)
            x = px(0.5) + px(0.055 - 0.011) * np.cos(theta)
            y = px(0.645) + px(0.045 - 0.011) * np.sin(theta)
            r = px(0.011)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=255)

    return ImageChops.subtract(lock, mask(s, face))


def render():
    s = SIZE * SCALE
    icon = to_image(background(s))
    glyph = glyph_mask(s)

    # A faint shadow under the glyph, so it sits on the gradient rather than being printed on it.
    shadow = glyph.filter(ImageFilter.GaussianBlur(s * 0.018))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -s * 0.012))
    shade = Image.new("RGB", (s, s), tuple(int(c * 255) for c in rgb(SHADOW)))
    icon = Image.composite(shade, icon, shadow.point(lambda v: int(v * 0.28)))

    white = Image.new("RGB", (s, s), tuple(int(c * 255) for c in rgb(GLYPH)))
    icon = Image.composite(white, icon, glyph)

    return icon.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


CONTENTS = """{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    render().save(OUT / "AppIcon.png", optimize=True)
    (OUT / "Contents.json").write_text(CONTENTS)


if __name__ == "__main__":
    main()
