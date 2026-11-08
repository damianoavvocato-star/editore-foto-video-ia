# MagicIAedit branding assets

The launcher icon and native splash artwork are maintained as SVG sources in `assets/branding/`. PNG variants are generated reproducibly by `python tool/prepare_branding.py` (requires CairoSVG).

After `flutter pub get`, run:

```bash
python -m pip install cairosvg
python tool/prepare_branding.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
python tool/configure_android_branding.py
```

The installed Android app is labelled MagicIAedit. Its launcher icon and native splash share the purple/blue film-and-play brand mark. The in-app app bar renders the SVG mark and MagicIAedit wordmark.
