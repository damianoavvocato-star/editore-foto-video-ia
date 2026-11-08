from pathlib import Path
import cairosvg
ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
BRANDING.mkdir(parents=True, exist_ok=True)
for source, target, size in [
    ("app_icon.svg", "app_icon.png", 1024),
    ("magiciaedit_mark.svg", "app_icon_foreground.png", 1024),
    ("magiciaedit_mark.svg", "splash_logo.png", 512),
]:
    cairosvg.svg2png(url=str(BRANDING / source), write_to=str(BRANDING / target), output_width=size, output_height=size)
print("MagicIAedit branding PNGs generated.")
