"""Render Folio's geometric book mark. Requires Pillow; no AI assets or fonts."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Folio/Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT.mkdir(parents=True, exist_ok=True)
scale = 2
image = Image.new("RGB", (1024 * scale, 1024 * scale), "#f5f3ed")
draw = ImageDraw.Draw(image)


def line(points, fill, width):
    draw.line([(x * scale, y * scale) for x, y in points], fill=fill, width=width * scale, joint="curve")


# Two page outlines, with an editorial rule on each spread.
ink = "#293027"
draw.rounded_rectangle((238*scale, 240*scale, 786*scale, 780*scale), radius=22*scale, fill=ink)
draw.polygon([(270*scale, 275*scale), (475*scale, 305*scale), (475*scale, 731*scale), (270*scale, 701*scale)], fill="#f5f3ed")
draw.polygon([(549*scale, 305*scale), (754*scale, 275*scale), (754*scale, 701*scale), (549*scale, 731*scale)], fill="#f5f3ed")
line([(316, 376), (433, 393)], "#65795b", 14)
line([(591, 393), (708, 376)], "#65795b", 14)
line([(316, 439), (433, 456)], ink, 10)
line([(591, 456), (708, 439)], ink, 10)
line([(316, 502), (404, 515)], ink, 10)
line([(591, 519), (679, 506)], ink, 10)
image.resize((1024, 1024), Image.Resampling.LANCZOS).save(OUTPUT / "AppIcon.png")
(OUTPUT / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
print("Generated AppIcon.png (1024 x 1024, opaque RGB).")
