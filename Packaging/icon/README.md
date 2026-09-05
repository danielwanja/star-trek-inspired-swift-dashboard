# App icon

`generate-icons.py` draws the "Astra mark" — an original console motif
(elbow rail, sensor ring, sweep, contact dot) in the dashboard's palette —
as vector art and renders every asset both apps need:

- `Packaging/macOS/AppIcon-1024.png` and `AppIcon.icns` (macOS bundle icon,
  Apple's 1024 grid with an 824 pt squircle and shadow), plus the 512 px
  `Sources/AstraConsole/Resources/AppIcon.png` the app sets as its Dock icon
  when launched with `swift run`.
- `AppleTV/SpaceshipDashboardTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets`:
  layered App Icon (Back / Middle / Front for parallax, 400×240 @1x/@2x),
  App Icon – App Store (1280×768, layered), Top Shelf Image (1920×720
  @1x/@2x) and Top Shelf Image Wide (2320×720 @1x/@2x).

Regenerate with Python 3, `pip install cairosvg pillow` and the DejaVu
fonts (used for the Top Shelf wordmark):

```bash
python3 Packaging/icon/generate-icons.py   # writes to ./out next to the script
```

then copy the outputs into the locations above (the script documents the
mapping at the bottom). The design is CC0 within this repository; no
third-party artwork is used.
