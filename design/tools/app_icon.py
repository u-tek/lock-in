"""Renders the app icon into the asset catalog.

    python3 design/tools/app_icon.py

A padlock with a face, locked in: the brand's lamp amber on its indigo night, with a soft glow
behind it like a desk lamp in a dark room. One 1024 x 1024 image for every size (the single-size
asset format), fully opaque, because App Store Connect rejects icons with an alpha channel. The
system rounds the corners, so the artwork fills the square. Needs Pillow and NumPy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"
SIZE = 1024
SCALE = 4  # draw large, then downscale: smooth edges without per-shape anti-aliasing

# DesignSystem's tokens (Packages/LKKit/Sources/DesignSystem/Colors.swift).
NIGHT = 0x0D0B17  # background, dark
NIGHT_RAISED = 0x2A2356  # a lighter indigo for the top of the sky
AMBER = 0xFFB23F  # accent, dark
AMBER_LIGHT = 0xFFCF70
AMBER_DEEP = 0xF08F22
INK = 0x1E1405  # onAccent
SHACKLE = 0xD9D3F5  # textPrimary's lavender, a touch deeper so the shackle reads as metal
SHACKLE_SHADE = 0xA79FD0
CHEEK = 0xFF7F5C


def rgb(value):
    return np.array([(value >> 16) & 255, (value >> 8) & 255, value & 255], dtype=np.float64) / 255


def to_image(array):
    return Image.fromarray((np.clip(array, 0, 1) * 255).round().astype(np.uint8), "RGB")


def background(s):
    """The night: indigo at the top to near-black at the bottom, with the lamp's warm glow."""
    ys, xs = np.mgrid[0:s, 0:s] / s
    sky = rgb(NIGHT_RAISED) * (1 - ys[..., None]) + rgb(NIGHT) * ys[..., None]
    # A soft amber glow centred behind the lock's body.
    distance = np.hypot(xs - 0.5, (ys - 0.6) * 1.1)
    glow = np.exp(-(distance / 0.34) ** 2)[..., None] * 0.42
    return sky * (1 - glow) + rgb(AMBER) * glow


def vertical_gradient(s, top, bottom, y0, y1):
    """A top-to-bottom gradient over rows y0..y1 (fractions of the canvas), as an RGB image."""
    ys = np.clip((np.arange(s) / s - y0) / (y1 - y0), 0, 1)[:, None, None]
    column = rgb(top) * (1 - ys) + rgb(bottom) * ys
    return to_image(np.broadcast_to(column, (s, s, 3)).copy())


def mask(s, draw_shape):
    image = Image.new("L", (s, s), 0)
    draw_shape(ImageDraw.Draw(image), s)
    return image


def render():
    s = SIZE * SCALE
    icon = to_image(background(s))

    def px(value):
        return value * s

    # The shackle: a thick upside-down U whose legs disappear into the body. Drawn as an outer
    # arch minus an inner one, so the curve and the legs meet without a seam.
    centre_x, centre_y, bottom = px(0.5), px(0.345), px(0.5)

    def arch(radius):
        def shape(draw, s):
            draw.ellipse([centre_x - radius, centre_y - radius, centre_x + radius, centre_y + radius], fill=255)
            draw.rectangle([centre_x - radius, centre_y, centre_x + radius, bottom], fill=255)
        return shape

    shackle = ImageChops.subtract(mask(s, arch(px(0.158))), mask(s, arch(px(0.09))))
    shackle_shade = vertical_gradient(s, SHACKLE, SHACKLE_SHADE, 0.17, 0.5)
    icon.paste(shackle_shade, (0, 0), shackle)

    # The body: a soft rounded square in lamp amber, lit from above.
    body_box = [px(0.25), px(0.43), px(0.75), px(0.84)]

    def body(draw, s):
        draw.rounded_rectangle(body_box, radius=px(0.13), fill=255)

    # A shadow under the body, so it sits on the glow rather than floating on it.
    shadow = mask(s, body).filter(ImageFilter.GaussianBlur(px(0.02)))
    shadow = shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -px(0.012)))
    dark = Image.new("RGB", (s, s), tuple(int(c * 255) for c in rgb(NIGHT)))
    icon = Image.composite(dark, icon, shadow.point(lambda v: int(v * 0.45)))
    icon.paste(vertical_gradient(s, AMBER_LIGHT, AMBER_DEEP, 0.43, 0.84), (0, 0), mask(s, body))

    # A highlight along the top edge of the body.
    def highlight(draw, s):
        draw.rounded_rectangle([px(0.29), px(0.455), px(0.71), px(0.53)], radius=px(0.04), fill=255)

    glow = mask(s, highlight).filter(ImageFilter.GaussianBlur(px(0.02)))
    icon = Image.composite(Image.new("RGB", (s, s), (255, 236, 196)), icon, glow.point(lambda v: int(v * 0.35)))

    # Rosy cheeks, soft.
    def cheeks(draw, s):
        for cx in (0.355, 0.645):
            draw.ellipse([px(cx - 0.05), px(0.665), px(cx + 0.05), px(0.725)], fill=255)

    blush = mask(s, cheeks).filter(ImageFilter.GaussianBlur(px(0.012)))
    cheek_colour = Image.new("RGB", (s, s), tuple(int(c * 255) for c in rgb(CHEEK)))
    icon = Image.composite(cheek_colour, icon, blush.point(lambda v: int(v * 0.5)))
    draw = ImageDraw.Draw(icon)

    # Eyes: dark ovals, each with a small catchlight.
    ink = tuple(int(c * 255) for c in rgb(INK))
    for cx in (0.415, 0.585):
        draw.ellipse([px(cx - 0.032), px(0.585), px(cx + 0.032), px(0.668)], fill=ink)
        draw.ellipse([px(cx - 0.006), px(0.6), px(cx + 0.014), px(0.622)], fill=(255, 248, 232))

    # A small, content smile.
    smile_box = [px(0.46), px(0.66), px(0.54), px(0.725)]
    draw.arc(smile_box, 20, 160, fill=ink, width=int(px(0.014)))

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
