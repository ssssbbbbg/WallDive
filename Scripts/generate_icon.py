#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import subprocess
import shutil

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
PNG_PREVIEW = RESOURCES / "AppIcon.png"
ICNS = RESOURCES / "AppIcon.icns"
MASTER = RESOURCES / "WallDive-AppIcon-4K.png"
IOS_ICONSET = ROOT / "iOS" / "W-DLER-iOS" / "WDLERiOS" / "Assets.xcassets" / "AppIcon.appiconset"

BASE_SIZE = 1024
VISIBLE_SIZE = 864
PINK = (255, 74, 186, 255)
PINK_DARK = (143, 22, 92, 255)
PINK_LIGHT = (255, 157, 220, 255)
BLACK = (4, 4, 7, 255)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFCompactRounded.ttf",
        "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
        "/System/Library/Fonts/Avenir Next.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size, index=1)
        except Exception:
            try:
                return ImageFont.truetype(candidate, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def vertical_gradient(top, bottom) -> Image.Image:
    gradient = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(gradient)
    for y in range(BASE_SIZE):
        t = y / (BASE_SIZE - 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(4))
        draw.line((0, y, BASE_SIZE, y), fill=color)
    return gradient


def soft_ellipse(size, box, fill, blur) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse(box, fill=fill)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def text_mask(text: str, font: ImageFont.FreeTypeFont, xy) -> Image.Image:
    mask = Image.new("L", (BASE_SIZE, BASE_SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.text(xy, text, font=font, fill=255)
    return mask


def draw_rounded_text(canvas: Image.Image, text: str, font: ImageFont.FreeTypeFont, xy) -> Image.Image:
    mask = text_mask(text, font, xy)

    # Deep dimensional shadow.
    shadow = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (0, 0, 0, 0))
    shadow_alpha = ImageChops.offset(mask, 22, 34).filter(ImageFilter.GaussianBlur(24))
    shadow.putalpha(shadow_alpha.point(lambda p: int(p * 0.62)))
    canvas = Image.alpha_composite(canvas, shadow)

    # Pink extrusion, slightly down-right, gives the letters body.
    extrusion = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), PINK_DARK)
    extrusion_mask = ImageChops.offset(mask, 12, 16).filter(ImageFilter.GaussianBlur(1.0))
    extrusion.putalpha(extrusion_mask)
    canvas = Image.alpha_composite(canvas, extrusion)

    # Soft neon bloom behind the letter face.
    bloom = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), PINK)
    bloom_alpha = mask.filter(ImageFilter.GaussianBlur(28)).point(lambda p: int(p * 0.55))
    bloom.putalpha(bloom_alpha)
    canvas = Image.alpha_composite(canvas, bloom)

    # Main face with a subtle vertical glassy gradient.
    face = vertical_gradient(PINK_LIGHT, PINK)
    face.putalpha(mask)
    canvas = Image.alpha_composite(canvas, face)

    # Bevel highlight clipped to the top-left of the glyphs.
    highlight_alpha = ImageChops.offset(mask, -7, -9).filter(ImageFilter.GaussianBlur(1.5))
    highlight_alpha = ImageChops.multiply(mask, highlight_alpha).point(lambda p: int(p * 0.32))
    highlight = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (255, 214, 242, 255))
    highlight.putalpha(highlight_alpha)
    canvas = Image.alpha_composite(canvas, highlight)

    # Gentle dark lower edge for depth.
    lower_alpha = ImageChops.offset(mask, 0, 13).filter(ImageFilter.GaussianBlur(2.2))
    lower_alpha = ImageChops.multiply(mask, lower_alpha).point(lambda p: int(p * 0.16))
    lower = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (82, 0, 50, 255))
    lower.putalpha(lower_alpha)
    return Image.alpha_composite(canvas, lower)


def make_base_icon(master: Image.Image) -> Image.Image:
    # macOS uses a padded, pre-masked variant so it matches neighboring icons.
    final = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (0, 0, 0, 0))
    resized = master.convert("RGBA").resize((VISIBLE_SIZE, VISIBLE_SIZE), Image.Resampling.LANCZOS)
    inset = (BASE_SIZE - VISIBLE_SIZE) // 2
    mask = rounded_mask(VISIBLE_SIZE, 192)
    final.paste(resized, (inset, inset), mask)
    return final


def write_ios_icons(master: Image.Image) -> None:
    IOS_ICONSET.mkdir(parents=True, exist_ok=True)
    for size in (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024):
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(IOS_ICONSET / f"AppIcon-{size}.png", optimize=True)


def write_iconset(base: Image.Image) -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, filename in sizes:
        resized = base.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)


def main() -> None:
    RESOURCES.mkdir(exist_ok=True)
    master = Image.open(MASTER).convert("RGB")
    base = make_base_icon(master)
    base.save(PNG_PREVIEW)
    write_ios_icons(master)
    write_iconset(base)
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    shutil.rmtree(ICONSET)
    print(ICNS)


if __name__ == "__main__":
    main()
