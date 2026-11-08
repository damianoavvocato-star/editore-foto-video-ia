from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
SOURCE = BRANDING / "app_icon_source.png"
BRANDING.mkdir(parents=True, exist_ok=True)

if not SOURCE.is_file():
    raise SystemExit(
        "Missing assets/branding/app_icon_source.png. "
        "Add the approved MagicIAedit icon image before generating launcher assets."
    )

with Image.open(SOURCE) as original:
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
