"""Check project references, asset/plist syntax, previews, and optional Swift syntax.

This does not replace typechecking/building against Apple's SDKs.
"""
from pathlib import Path
import argparse
import json
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def validate(swiftc=None):
    project = (ROOT / "Folio.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    defined = set(re.findall(r"^\s*([A-F0-9]{24}) = \{", project, re.MULTILINE))
    referenced = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    assert referenced <= defined, f"Unresolved Xcode object references: {referenced - defined}"
    app_sources = sorted((ROOT / "Folio").rglob("*.swift"))
    test_sources = sorted((ROOT / "FolioTests").rglob("*.swift"))
    for folder, files in [("Folio", app_sources), ("FolioTests", test_sources)]:
        for path in files:
            relative = path.relative_to(ROOT / folder).as_posix()
            assert f"path = {json.dumps(relative)};" in project, f"Source missing from Xcode project: {path}"
    for path in app_sources:
        source = path.read_text(encoding="utf-8")
        if re.search(r"struct \w+\s*:\s*(?:View|UIViewRepresentable)\b", source):
            assert "#Preview" in source, f"Visual component has no preview: {path}"
    for path in (ROOT / "Folio/Resources").rglob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        for entry in data.get("images", []):
            if "filename" in entry:
                assert (path.parent / entry["filename"]).is_file()
    for path in (ROOT / "Folio/Resources").rglob("*.plist"):
        plistlib.loads(path.read_bytes())
    for path in (ROOT / "Folio/Resources").rglob("*.xcprivacy"):
        plistlib.loads(path.read_bytes())
    for path in (ROOT / "Folio.xcodeproj").rglob("*.xcscheme"):
        ET.parse(path)
    if swiftc:
        subprocess.run([swiftc, "-frontend", "-parse", *map(str, app_sources + test_sources)], check=True)
    print(f"Validated {len(defined)} Xcode objects, {len(app_sources)} app sources, previews, resources, and scheme XML.")
    if swiftc:
        print("Swift syntax parsing passed. Apple SDK typechecking is still required.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--swiftc")
    args = parser.parse_args()
    validate(args.swiftc)
