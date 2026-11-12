from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
SOURCE = BRANDING / "app_icon_source.png"
BRANDING.mkdir(parents=True, exist_ok=True)

if SOURCE.is_file():
    original = Image.open(SOURCE)
    print("Using the approved user-provided MagicIAedit icon source.")
else:
    # Temporary CI-safe fallback: render the repository's existing branded SVG.
    # The exact user-approved artwork replaces this as soon as app_icon_source.png
    # is uploaded to assets/branding.
    svg_source = BRANDING / "app_icon.svg"
    if not svg_source.is_file():
        raise SystemExit("No app_icon_source.png or fallback app_icon.svg was found.")
    try:
        import cairosvg
        from io import BytesIO
        original = Image.open(BytesIO(cairosvg.svg2png(url=str(svg_source), output_width=1024, output_height=1024)))
    except Exception as error:
        raise SystemExit(f"Could not render fallback branding SVG: {error}") from error
    print("WARNING: using repository SVG fallback; exact user-approved image is not yet uploaded.")

with original:
    icon = original.convert("RGBA")
    if icon.width != icon.height:
        raise SystemExit(f"App icon must be square, got {icon.width}x{icon.height}")
    icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
    icon.save(BRANDING / "app_icon.png", format="PNG", optimize=True)
    icon.save(BRANDING / "app_icon_foreground.png", format="PNG", optimize=True)
    icon.resize((512, 512), Image.Resampling.LANCZOS).save(
        BRANDING / "splash_logo.png", format="PNG", optimize=True
    )

print("Approved MagicIAedit source image applied to launcher and splash assets.")
