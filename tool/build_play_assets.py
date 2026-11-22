#!/usr/bin/env python3
"""Package the reviewed real-app screenshots as Google Play listing assets.

Render the phone/tablet shots first with tool/local_screenshots.py; the source
screenshots use only the harness's fictional sample data. This script scales the
captures to Play's requested dimensions, converts to opaque JPEG, and composes
the 1024x500 feature graphic from the AI-created background plus truthful
English copy and the existing app icon. It does not draw or fabricate app UI.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".agent-screens" / "local"
HIRES = ROOT / ".agent-screens" / "play-hires"
OUT = ROOT / "store" / "play-assets"
PHONE_NAMES = ["home", "calculator", "counter", "add_entry"]
TABLET_NAMES = ["home", "calculator", "counter", "add_entry"]


def load_source(stem: str, phone: bool) -> Image.Image:
    candidates = []
    if phone and stem == "home":
        candidates.append(HIRES / "home_play_phone.png")
    candidates.append(LOCAL / f"{stem}_play_phone.png" if phone else LOCAL / f"{stem}_tablet.png")
    for path in candidates:
        if path.is_file():
            return Image.open(path).convert("RGBA")
    raise FileNotFoundError(f"Missing screenshot {stem}: tried {candidates}")


def save_screen(stem: str, phone: bool) -> None:
    image = load_source(stem, phone)
    size = (1080, 1920) if phone else (1200, 2134)
    # Real pixel captures are used when available; other captures are enlarged
    # with a high-quality filter, with subtle edge recovery only (no UI edits).
    image = image.resize(size, Image.Resampling.LANCZOS)
    image = image.filter(ImageFilter.UnsharpMask(radius=1.1, percent=45, threshold=3))
    image.convert("RGB").save(
        OUT / ("phone" if phone else "tablet") / f"{stem}.jpg",
        "JPEG", quality=96, subsampling=0, optimize=True,
    )


def build_feature() -> None:
    art = Image.open(ROOT / "store" / "play-assets" / "source" / "feature-background.png").convert("RGB")
    # Center-crop the generated landscape illustration to the exact Play ratio.
    target_ratio = 1024 / 500
    w, h = art.size
    if w / h > target_ratio:
        nw = round(h * target_ratio)
        x = (w - nw) // 2
        art = art.crop((x, 0, x + nw, h))
    else:
        nh = round(w / target_ratio)
        y = (h - nh) // 2
        art = art.crop((0, y, w, y + nh))
    canvas = art.resize((1024, 500), Image.Resampling.LANCZOS).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    regular = ImageFont.truetype(str(ROOT / "assets/fonts/Roboto-Regular.ttf"), 27)
    bold = ImageFont.truetype(str(ROOT / "assets/fonts/Roboto-Bold.ttf"), 54)
    small = ImageFont.truetype(str(ROOT / "assets/fonts/Roboto-Bold.ttf"), 17)
    green = (17, 94, 43, 255)
    deep = (20, 72, 35, 255)
    gold = (239, 174, 20, 255)

    # The mark is the existing store icon, framed without altering its artwork.
    icon = Image.open(ROOT / "store/assets/app-icon-512.png").convert("RGBA")
    icon.thumbnail((98, 98), Image.Resampling.LANCZOS)
    badge = Image.new("RGBA", (116, 116), (255, 255, 255, 0))
    bd = ImageDraw.Draw(badge)
    bd.ellipse((2, 2, 114, 114), fill=(255, 252, 237, 245), outline=(235, 179, 30, 255), width=3)
    badge.alpha_composite(icon, ((116 - icon.width) // 2, (116 - icon.height) // 2))
    canvas.alpha_composite(badge, (72, 185))

    # Safe central area: brand and feature statement stay clear of the crop edges.
    draw = ImageDraw.Draw(canvas)
    draw.text((216, 190), "Khoroch Diary", font=bold, fill=deep,
              stroke_width=1, stroke_fill=(255, 249, 225, 180))
    draw.text((219, 270), "Track income, expenses & balances", font=regular, fill=green,
              stroke_width=1, stroke_fill=(255, 249, 225, 150))
    draw.rounded_rectangle((219, 324, 339, 332), radius=4, fill=gold)
    draw.text((219, 353), "PERSONAL LEDGER", font=small, fill=deep)

    canvas.convert("RGB").save(OUT / "feature-graphic.jpg", "JPEG", quality=96, subsampling=0, optimize=True)


def main() -> None:
    (OUT / "phone").mkdir(parents=True, exist_ok=True)
    (OUT / "tablet").mkdir(parents=True, exist_ok=True)
    for name in PHONE_NAMES:
        save_screen(name, True)
    for name in TABLET_NAMES:
        save_screen(name, False)
    build_feature()
    print(f"Built Play assets in {OUT}")


if __name__ == "__main__":
    main()
