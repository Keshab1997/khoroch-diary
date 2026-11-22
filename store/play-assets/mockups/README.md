# Khoroch Diary — AI-polished Google Play mockups

This is the presentation-ready mockup set, built around genuine Khoroch Diary screen captures. Each original app screen remains intact inside the framed mockup; only the surroundings, border, brand header and short accurate feature copy have been added. The portrait backdrop is AI-generated, text-free artwork. It contains no generated UI.

## Files

- `feature-graphic.jpg` — 1024 × 500, opaque JPEG.
- `phone/` — 4 phone listing screenshots, 1080 × 1920 each: home, calculator, counter and add-entry.
- `tablet/` — 4 tablet listing screenshots, 1200 × 2134 each: home, calculator, counter and add-entry. These use a simple frame and no extra copy over the large-screen capture.
- `ALT_TEXT.md` — accessible descriptions for the graphic and screenshots.

All images are JPEG/RGB with no alpha channel, below 8 MB, and within the screenshot aspect-ratio limits. The feature graphic has the required exact dimensions. The phone designs use the app's English UI and a generic illustrative frame; the tablet designs keep the app screen prominent without headlines over it.

The home screenshot's ledger name, amounts, dates and entries are fictional sample data. The note counter shows its real default zero-count state; the add-entry form is blank. See the parent `README.md` for notes on the current tablet layout and tablet review.

To rebuild after changing the plain screen captures, run:

```bash
python3 tool/local_screenshots.py --shot home_play_phone,calculator_play_phone,counter_play_phone,add_entry_play_phone,home_tablet,calculator_tablet,counter_tablet,add_entry_tablet
python3 tool/build_play_assets.py
python3 tool/design_play_mockups.py
```

Google Play requirements reference: <https://support.google.com/googleplay/android-developer/answer/9866151?hl=en>
