# MagicIAedit branding assets

The official launcher icon is the neon purple/blue MagicIAedit artwork in `assets/branding/app_icon.svg`, with the clapperboard, film strip, IA monogram, MagicIAedit wordmark and photo/video AI subtitle. PNG variants are generated reproducibly by `python tool/prepare_branding.py` (requires CairoSVG).

After `flutter pub get`, run:

```bash
python -m pip install cairosvg
python tool/prepare_branding.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
python tool/configure_android_branding.py
```

The generated 1024px launcher artwork is configured for Android and iOS. Android uses an adaptive foreground mark on a deep-violet background; the native splash uses the matching MagicIAedit mark. The installed app display name is MagicIAedit, and the in-app app bar renders the SVG mark and wordmark.
