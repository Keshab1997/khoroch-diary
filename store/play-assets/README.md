# Khoroch Diary — Google Play graphic assets (English)

## Upload files

- `feature-graphic.jpg` — Google Play feature graphic, 1024 × 500.
- `phone/` — four portrait phone screenshots: home, calculator, counter and add-entry form; each 1080 × 1920.
- `tablet/` — four portrait tablet screenshots of the same app screens; each 1200 × 2134.
- `ALT_TEXT.md` — suggested accessible descriptions for the feature graphic and screenshots.

All upload images are opaque JPEGs, use the app's English UI, and were checked for pixel dimensions and aspect ratio. Each file is below 8 MB. The screenshots show the actual app widgets rendered locally with the app theme; no AI-generated or redrawn UI is used.

**Sample-data note:** The home-screen ledger, khata name, balance, totals and transaction descriptions are fictional screenshot fixtures. They are not real user data. The counter image shows the genuine default zero-count state. The entry form is intentionally blank.

**Tablet note:** The tablet captures are real app screens rendered at a 600 × 1067 logical portrait viewport and exported at 1200 × 2134. The UI currently retains its phone-oriented layout on this portrait size; review large-screen behavior and these previews on target tablets before publishing a tablet-specific listing.

`source/feature-background.png` is the AI-created, text-free background used only to compose the feature graphic. It is not an upload asset. The feature graphic itself adds the existing app icon and truthful English copy. `tool/build_play_assets.py` can rebuild the JPEGs after re-rendering the harness shots with `python3 tool/local_screenshots.py --shot home_play_phone,calculator_play_phone,counter_play_phone,add_entry_play_phone,home_tablet,calculator_tablet,counter_tablet,add_entry_tablet`.

## Google Play specifications checked

- Feature graphic: JPEG or 24-bit PNG without alpha, exactly 1024 × 500.
- Phone screenshots: 2–8 supported; these four are 1080 × 1920 portrait.
- Tablet screenshots: at least four; these four are portrait 9:16 captures at 1200 × 2134.
- Screenshots are individually below 8 MB. The longest side of each standard phone/tablet screenshot is less than 2.3 times the shortest.

Official reference: <https://support.google.com/googleplay/android-developer/answer/9866151?hl=en>

## AI-polished mockup variant

For a more designed, promotional presentation, see `mockups/` or download `store/Khoroch-Diary-AI-Mockup-Assets.zip`. The app screenshot was supplied as a visual reference for its palette and mood to create coordinated AI-generated, text-free backgrounds; the exact app UI pixels were then composited back into the designs. Mockups add a frame and truthful English headlines, not generated or retouched UI. Tablet mockups keep the screenshot free of added headlines. Both the plain screenshots above and these designed alternatives are retained so you can choose which presentation to upload.
