from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
if not manifest.exists():
    raise SystemExit("Generated AndroidManifest.xml was not found.")
content = manifest.read_text(encoding="utf-8")
updated, count = re.subn(r'android:label="[^"]*"', 'android:label="MagicIAedit"', content, count=1)
if count != 1 or 'android:icon="@mipmap/ic_launcher"' not in updated:
    raise SystemExit("Could not safely configure Android display name and launcher icon.")
manifest.write_text(updated, encoding="utf-8")
ios_info = ROOT / "ios" / "Runner" / "Info.plist"
if ios_info.exists():
    ios = ios_info.read_text(encoding="utf-8")
    if "<key>CFBundleDisplayName</key>" in ios:
        ios = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', r'\1MagicIAedit\2', ios, count=1)
    else:
        ios = ios.replace("</dict>", "<key>CFBundleDisplayName</key><string>MagicIAedit</string>\n</dict>", 1)
    ios_info.write_text(ios, encoding="utf-8")
print("MagicIAedit display name configured; Android launcher icon points to generated mipmap resources.")
