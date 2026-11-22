#!/usr/bin/env python3
"""Create polished Google Play mockup variants around genuine app screenshots.

The captured UI pixels are never redrawn or passed through image generation.
AI art is used only as a text-free background; typography, device presentation
frames and the existing app mark are composed locally with Pillow. Outputs are
kept separate from the plain screenshots so the user can choose either set.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "store" / "play-assets"
OUT = ASSETS / "mockups"
BG_PATH = ASSETS / "source" / "mockup-background.png"
ICON_PATH = ROOT / "store" / "assets" / "app-icon-512.png"
REGULAR = ROOT / "assets" / "fonts" / "Roboto-Regular.ttf"
BOLD = ROOT / "assets" / "fonts" / "Roboto-Bold.ttf"

PHONE_COPY = {
    "home": ("Your khata, at a glance", "Balances and recent activity together."),
    "calculator": ("Quick calculations, made simple", "Calculate everyday amounts in one place."),
    "counter": ("Count cash, note by note", "Add up denominations and coins."),
    "add_entry": ("Log income and expenses", "Add an amount, date, category and note."),
}


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    image = image.convert("RGB")
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    x = (resized.width - size[0]) // 2
    y = (resized.height - size[1]) // 2
    return resized.crop((x, y, x + size[0], y + size[1]))


def rounded_image(image: Image.Image, size: tuple[int, int], radius: int) -> Image.Image:
    image = image.convert("RGB").resize(size, Image.Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    image.putalpha(mask)
    return image


def make_background(size: tuple[int, int]) -> Image.Image:
    return cover(Image.open(BG_PATH), size).convert("RGBA")


def add_shadow(canvas: Image.Image, box: tuple[int, int, int, int], radius: int, blur: int, opacity: int) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0, y0 + 13, x1, y1 + 13), radius=radius, fill=(9, 44, 24, opacity))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)


def place_screen(canvas: Image.Image, source_path: Path, frame: tuple[int, int, int, int], pad: int, radius: int) -> None:
    x, y, w, h = frame
    add_shadow(canvas, (x, y, x + w, y + h), radius, 30, 85)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=(14, 67, 37, 255), outline=(227, 178, 45, 255), width=4)
    inner_w, inner_h = w - pad * 2, h - pad * 2
    screenshot = rounded_image(Image.open(source_path), (inner_w, inner_h), max(14, radius - pad // 2))
    canvas.alpha_composite(screenshot, (x + pad, y + pad))


def make_phone(name: str) -> None:
    canvas = make_background((1080, 1920))
    d = ImageDraw.Draw(canvas)
    icon = Image.open(ICON_PATH).convert("RGBA").resize((88, 88), Image.Resampling.LANCZOS)
    d.ellipse((78, 49, 174, 145), fill=(255, 252, 239, 250), outline=(230, 177, 32, 255), width=3)
    canvas.alpha_composite(icon, (82, 53))
    title_font = ImageFont.truetype(str(BOLD), 44)
    kicker_font = ImageFont.truetype(str(BOLD), 18)
    headline_font = ImageFont.truetype(str(BOLD), 42)
    sub_font = ImageFont.truetype(str(REGULAR), 25)
    d = ImageDraw.Draw(canvas)
    d.text((194, 59), "Khoroch Diary", font=title_font, fill=(17, 76, 38, 255))
    d.text((198, 115), "PERSONAL LEDGER", font=kicker_font, fill=(38, 111, 55, 255))
    headline, subtitle = PHONE_COPY[name]
    d.text((82, 170), headline, font=headline_font, fill=(20, 67, 36, 255))
    d.text((84, 226), subtitle, font=sub_font, fill=(54, 90, 59, 255))
    place_screen(canvas, ASSETS / "phone" / f"{name}.jpg", (79, 284, 922, 1614), 23, 48)
    canvas.convert("RGB").save(OUT / "phone" / f"{name}.jpg", "JPEG", quality=96, subsampling=0, optimize=True)


def make_tablet(name: str) -> None:
    # A minimal tablet presentation frame; no additional promotional copy is
    # placed over the large-screen capture, keeping the app experience clear.
    canvas = make_background((1200, 2134))
    place_screen(canvas, ASSETS / "tablet" / f"{name}.jpg", (66, 140, 1068, 1854), 25, 52)
    canvas.convert("RGB").save(OUT / "tablet" / f"{name}.jpg", "JPEG", quality=96, subsampling=0, optimize=True)


def make_feature() -> None:
    # The existing AI artwork remains the banner background. A genuine, intact
    # home-screen capture appears inside a floating preview panel, not a fake
    # generated interface or device.
    base_path = ASSETS / "source" / "feature-background.png"
    canvas = cover(Image.open(base_path), (1024, 500)).convert("RGBA")
    icon = Image.open(ICON_PATH).convert("RGBA").resize((86, 86), Image.Resampling.LANCZOS)
    d = ImageDraw.Draw(canvas)
    d.ellipse((54, 191, 150, 287), fill=(255, 252, 239, 250), outline=(230, 177, 32, 255), width=3)
    canvas.alpha_composite(icon, (59, 196))
    d = ImageDraw.Draw(canvas)
    d.text((169, 193), "Khoroch Diary", font=ImageFont.truetype(str(BOLD), 47), fill=(20, 72, 35, 255))
    d.text((172, 253), "Track income, expenses & balances", font=ImageFont.truetype(str(REGULAR), 23), fill=(17, 94, 43, 255))
    d.rounded_rectangle((172, 301, 289, 309), radius=4, fill=(239, 174, 20, 255))
    d.text((172, 329), "YOUR PERSONAL LEDGER", font=ImageFont.truetype(str(BOLD), 16), fill=(20, 72, 35, 255))

    # Slim floating screenshot card with restrained gold/green rim.
    add_shadow(canvas, (731, 13, 1007, 487), 28, 18, 90)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((731, 13, 1007, 487), radius=28, fill=(17, 76, 38, 255), outline=(230, 177, 32, 255), width=3)
    home = rounded_image(Image.open(ASSETS / "phone" / "home.jpg"), (250, 444), 20)
    canvas.alpha_composite(home, (744, 27))
    canvas.convert("RGB").save(OUT / "feature-graphic.jpg", "JPEG", quality=96, subsampling=0, optimize=True)


def main() -> None:
    (OUT / "phone").mkdir(parents=True, exist_ok=True)
    (OUT / "tablet").mkdir(parents=True, exist_ok=True)
    for name in PHONE_COPY:
        make_phone(name)
        make_tablet(name)
    make_feature()
    print(f"Designed mockup set in {OUT}")


if __name__ == "__main__":
    main()
