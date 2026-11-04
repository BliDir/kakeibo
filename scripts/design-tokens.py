#!/usr/bin/env python3
"""Kakeibo design tokens: the single source for app colors.

    python3 scripts/design-tokens.py          # write App/Assets.xcassets/Tokens/*.colorset
    python3 scripts/design-tokens.py --check  # fail if assets are stale or contrast is too low

Light values come from the "Kakeibo iOS App Screens" canvas. Dark values are chosen to keep
the same roles and pass the contrast checks below in both modes.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App", "Assets.xcassets")

# name: (light, dark). Hex as RRGGBB or RRGGBBAA.
COLORS = {
    # Grounds and surfaces
    "Ground": ("EEF0F3", "0F1217"),          # ledger and review background
    "GroundDeep": ("E4E7EC", "0A0D11"),      # reading screen background
    "Surface": ("FFFFFF", "1B2029"),         # cards
    "Field": ("F6F7F9", "252B36"),           # inputs, unselected chips
    "Border": ("DADDE3", "3A4150"),
    "Divider": ("ECEEF2", "2B313C"),
    # Text
    "Text": ("1A1F2B", "ECEEF2"),
    "SecondaryText": ("5F6676", "A3A9B6"),
    "Pending": ("C9CDD5", "4B5263"),         # empty step circle (decorative)
    # Accent 藍 (the asset catalog's AccentColor is the app tint)
    "AccentColor": ("2B4785", "9DB4EB"),
    "AccentTint": ("E3E9F5", "243354"),
    "OnAccent": ("FFFFFF", "0E1730"),
    # States
    "Success": ("2F7A4F", "6CCB91"),
    "Destructive": ("C23B22", "FF8266"),     # 朱 vermilion
    "OnDestructive": ("FFFFFF", "2A0B05"),
    "Warning": ("C08419", "E3AE45"),         # "check this field" border (canvas C98A1A, darkened to pass 3:1)
    "WarningFill": ("FFF4DF", "3A2C10"),
    "WarningText": ("7A4E00", "F4CA74"),
    # Tax rate tags
    "ReducedRateFill": ("E2EFE6", "1E3A2A"),
    "ReducedRateText": ("2D6A45", "92D6AC"),
    "StandardRateText": ("4A505C", "B9BFCB"),
    # Overlays
    "Scrim": ("00000059", "0000008C"),       # behind confirm panels
    "Shadow": ("141C2D2E", "00000080"),
    # Categories
    "CategoryGroceries": ("3F8A5C", "5FB97F"),
    "CategoryDining": ("C96B2C", "E58E52"),
    "CategoryHousehold": ("8A6BB8", "AE92DB"),
    "CategoryTransport": ("2F74B5", "5D9DDB"),
    "CategoryKids": ("D0548A", "E77DAA"),
    "CategoryHealth": ("2C9A9A", "4CC0C0"),
    "CategoryShopping": ("B08A1E", "D5AE3D"),
    "CategoryUtilities": ("5D6B82", "8E9BB3"),
    "CategoryOther": ("8C8F96", "A9ACB3"),
}

# (foreground, background, minimum ratio, where it is used)
TEXT = 4.5    # WCAG AA body text
UI = 3.0      # WCAG AA non-text UI and large text
PAIRS = [
    ("Text", "Surface", TEXT, "body text on cards"),
    ("Text", "Ground", TEXT, "titles on the ground"),
    ("Text", "Field", TEXT, "input text"),
    ("SecondaryText", "Surface", TEXT, "labels and captions on cards"),
    ("SecondaryText", "Ground", TEXT, "captions on the ground"),
    ("SecondaryText", "GroundDeep", TEXT, "reading screen captions"),
    ("SecondaryText", "Field", TEXT, "placeholders"),
    ("AccentColor", "Surface", TEXT, "links and buttons on cards"),
    ("AccentColor", "Ground", TEXT, "Cancel on the ground"),
    ("AccentColor", "AccentTint", TEXT, "selected chip text"),
    ("Text", "AccentTint", TEXT, "privacy note on Settings"),
    ("OnAccent", "AccentColor", TEXT, "primary button text"),
    ("Destructive", "Surface", TEXT, "Delete text"),
    ("Destructive", "Ground", TEXT, "Delete button on the ground"),
    ("OnDestructive", "Destructive", TEXT, "confirm button text"),
    ("Success", "Surface", TEXT, "total verified line"),
    ("WarningText", "WarningFill", TEXT, "hint text in a highlighted field"),
    ("WarningText", "Surface", TEXT, "hint text under a field"),
    ("Text", "WarningFill", TEXT, "input text in a highlighted field"),
    ("ReducedRateText", "ReducedRateFill", TEXT, "8% tag"),
    ("StandardRateText", "Divider", TEXT, "10% tag"),
    ("Surface", "Text", TEXT, "save banner (inverted)"),
    ("Warning", "Surface", UI, "highlight border"),
    ("AccentColor", "Field", UI, "selected chip border"),
] + [(f"Category{c}", "Surface", UI, f"{c.lower()} category dot")
     for c in ["Groceries", "Dining", "Household", "Transport", "Kids", "Health", "Shopping", "Utilities", "Other"]]


def rgba(hex_value):
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(hex_value[6:8], 16) / 255 if len(hex_value) == 8 else 1.0
    return r, g, b, a


def luminance(hex_value):
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b, _ = rgba(hex_value)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def colorset(light, dark):
    def entry(hex_value, appearance=None):
        r, g, b, a = rgba(hex_value)
        item = {
            "color": {
                "color-space": "srgb",
                "components": {"red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}", "alpha": f"{a:.3f}"},
            },
            "idiom": "universal",
        }
        if appearance:
            item["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        return item
    return {"colors": [entry(light), entry(dark, "dark")], "info": {"author": "xcode", "version": 1}}


def asset_path(name):
    # AccentColor stays at the catalog root, where Xcode looks for the app's tint.
    folder = ASSETS if name == "AccentColor" else os.path.join(ASSETS, "Tokens")
    return os.path.join(folder, f"{name}.colorset", "Contents.json")


def expected_files():
    files = {asset_path(n): json.dumps(colorset(*v), indent=2) + "\n" for n, v in COLORS.items()}
    files[os.path.join(ASSETS, "Tokens", "Contents.json")] = json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    return files


def check_contrast():
    failures = []
    for mode, index in (("light", 0), ("dark", 1)):
        for fg, bg, minimum, use in PAIRS:
            ratio = contrast(COLORS[fg][index], COLORS[bg][index])
            if ratio < minimum:
                failures.append(f"{mode}: {fg} on {bg} is {ratio:.2f}:1, needs {minimum}:1 ({use})")
    return failures


def main():
    files = expected_files()
    failures = check_contrast()
    if "--check" in sys.argv:
        for path, content in files.items():
            if not os.path.exists(path) or open(path).read() != content:
                failures.append(f"{os.path.relpath(path, ROOT)} is stale: run scripts/design-tokens.py")
        for failure in failures:
            print(failure)
        print(f"{len(PAIRS) * 2} contrast checks, {len(failures)} problems")
        sys.exit(1 if failures else 0)

    for path, content in files.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
    print(f"wrote {len(COLORS)} color sets")
    for failure in failures:
        print("WARNING", failure)


if __name__ == "__main__":
    main()
