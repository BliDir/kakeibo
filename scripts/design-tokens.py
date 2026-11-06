#!/usr/bin/env python3
"""Kakeibo design tokens: the single source for app colors.

    python3 scripts/design-tokens.py          # write App/Assets.xcassets/Tokens/*.colorset
    python3 scripts/design-tokens.py --check  # fail if assets are stale or contrast is too low

Values come from the approved visual refresh (Linear "Kakeibo Visual Refresh — Design &
Implementation", 5 November 2026): white and soft grey grounds, ink-green primary, and a dark
theme on deep green-black with a pale green accent. Every token has a light and a dark value;
some also have an Increased Contrast value (System Settings › Accessibility › Display & Text
Size › Increase Contrast), used by iOS automatically.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "App", "Assets.xcassets")

# name: (light, dark) or (light, dark, light high contrast, dark high contrast).
# Hex as RRGGBB or RRGGBBAA.
COLORS = {
    # Grounds and surfaces
    "Ground": ("FFFFFF", "0B100D"),          # screen background (ledger, review, settings)
    "GroundDeep": ("F0F2F1", "070A08"),      # reading screen background
    "Surface": ("F5F6F7", "18201B"),         # cards and grouped rows
    "Field": ("FFFFFF", "222B25"),           # inputs and unselected chips on a card
    "Border": ("E8ECE9", "29392D", "7F8B84", "5E7363"),
    # Divider is also a fill (disabled buttons, 10% tag), so it has no stronger variant:
    # Increased Contrast strengthens Border instead.
    "Divider": ("EEF1EF", "222E25"),
    # Text
    "Text": ("111815", "F2F6EF"),
    "SecondaryText": ("64706A", "A2B2A5", "47524C", "C9D5CB"),
    "Pending": ("C9CFCB", "3A4A3E"),         # empty step circle (decorative)
    # Primary: ink green (the asset catalog's AccentColor is the app tint)
    "AccentColor": ("174D37", "C0E6A6"),
    "AccentTint": ("EDF3EF", "263C28"),      # soft green fill (selected chips, notes)
    "OnAccent": ("FFFFFF", "142C1C"),
    # Secondary "soft glass" buttons. Light: translucent green-grey over a material, with a
    # subtle green border. Dark, Reduce Transparency and Increased Contrast: opaque.
    "SecondaryFill": ("ECF2EEA3", "18201B"),
    "SecondaryFillOpaque": ("ECF2EE", "18201B", "E4EBE6", "222B25"),
    "SecondaryBorder": ("174D371A", "29392D", "174D37A6", "5E7363"),
    # States
    "Success": ("276A49", "97C49A"),
    "Destructive": ("AD352E", "FFB4A7"),     # 朱 vermilion, for destructive actions and errors
    "OnDestructive": ("FFFFFF", "3A0D08"),
    "DestructiveFill": ("FBEAE7", "3D1810"),  # over-budget banner
    "DestructiveText": ("8C2A17", "FFB4A7"),
    "Warning": ("A87310", "E3AE45"),         # "check this field" border
    "WarningFill": ("FFF7E8", "382C15"),
    "WarningText": ("774A0A", "F7CE82"),
    # Tax rate tags
    "ReducedRateFill": ("E6F0E9", "1E3A2A"),
    "ReducedRateText": ("276A49", "97C49A"),
    "StandardRateText": ("4A524D", "B9C4BC"),
    # Brand: ivory, the app icon's light color (kept for anything that needs a light plate).
    "LogoPlate": ("F7F4E9", "F7F4E9"),
    # Overlays
    "Scrim": ("00000059", "0000008C"),       # behind confirm panels
    "Shadow": ("15271C14", "00000080"),      # soft elevation
    # Categories: the same identity in both modes, brightened for dark.
    "CategoryGroceries": ("3F8A5C", "5FB97F"),
    "CategoryDining": ("B96227", "E58E52"),
    "CategoryHousehold": ("8A6BB8", "AE92DB"),
    "CategoryTransport": ("2F74B5", "5D9DDB"),
    "CategoryKids": ("C94D82", "E77DAA"),
    "CategoryHealth": ("23898A", "4CC0C0"),
    "CategoryShopping": ("957414", "D5AE3D"),
    "CategoryUtilities": ("5D6B82", "8E9BB3"),
    "CategoryOther": ("7D8189", "A9ACB3"),
}

# (foreground, background, minimum ratio, where it is used). A background written as
# "Over/Under" is `Over` composited on `Under`, for translucent fills (the glass buttons).
TEXT = 4.5    # WCAG AA body text
UI = 3.0      # WCAG AA non-text UI and large text
PAIRS = [
    ("Text", "Ground", TEXT, "body text and titles"),
    ("Text", "Surface", TEXT, "text on cards"),
    ("Text", "Field", TEXT, "input text"),
    ("SecondaryText", "Ground", TEXT, "captions on the ground"),
    ("SecondaryText", "Surface", TEXT, "labels and captions on cards"),
    ("SecondaryText", "GroundDeep", TEXT, "reading screen captions"),
    ("SecondaryText", "Field", TEXT, "placeholders"),
    ("SecondaryText", "Divider", TEXT, "disabled button label"),
    ("AccentColor", "Ground", TEXT, "links and text buttons"),
    ("AccentColor", "Surface", TEXT, "links and buttons on cards"),
    ("AccentColor", "AccentTint", TEXT, "selected chip text"),
    ("Text", "AccentTint", TEXT, "notes on a soft green fill"),
    ("OnAccent", "AccentColor", TEXT, "primary button label"),
    ("Text", "SecondaryFill/Ground", TEXT, "secondary button label on the ground"),
    ("Text", "SecondaryFill/Surface", TEXT, "secondary button label on a card"),
    ("AccentColor", "SecondaryFill/Ground", TEXT, "secondary button icon"),
    ("Text", "SecondaryFillOpaque", TEXT, "secondary button label, opaque fallback"),
    ("AccentColor", "SecondaryFillOpaque", TEXT, "secondary button icon, opaque fallback"),
    ("Destructive", "Ground", TEXT, "Delete text on the ground"),
    ("Destructive", "Surface", TEXT, "Delete text on a card"),
    ("OnDestructive", "Destructive", TEXT, "destructive confirm label"),
    ("DestructiveText", "DestructiveFill", TEXT, "over-budget banner text"),
    ("Text", "DestructiveFill", TEXT, "over-budget banner title"),
    ("Destructive", "DestructiveFill", UI, "over-budget banner icon"),
    ("Success", "Ground", TEXT, "verified line on the ground"),
    ("Success", "Surface", TEXT, "verified line on a card"),
    ("WarningText", "WarningFill", TEXT, "hint text in a highlighted field"),
    ("WarningText", "Surface", TEXT, "hint text under a field"),
    ("WarningText", "Ground", TEXT, "hint text on the ground"),
    ("Text", "WarningFill", TEXT, "input text in a highlighted field"),
    ("ReducedRateText", "ReducedRateFill", TEXT, "8% tag"),
    ("StandardRateText", "Divider", TEXT, "10% tag"),
    ("Ground", "Text", TEXT, "save banner (inverted)"),
    ("Warning", "Surface", UI, "highlight border on a card"),
    ("Warning", "Ground", UI, "highlight border on the ground"),
    ("AccentColor", "Field", UI, "selected chip border"),
] + [(f"Category{c}", bg, UI, f"{c.lower()} category dot on {bg.lower()}")
     for c in ["Groceries", "Dining", "Household", "Transport", "Kids", "Health", "Shopping", "Utilities", "Other"]
     for bg in ["Ground", "Surface"]]

# Increased Contrast must at least keep these pairs at the ratio it adds.
HIGH_CONTRAST_PAIRS = [
    ("SecondaryText", "Ground", 7.0, "captions, increased contrast"),
    ("SecondaryText", "Surface", 6.0, "captions on cards, increased contrast"),
    ("Border", "Ground", UI, "borders, increased contrast"),
    ("SecondaryBorder", "Ground", UI, "secondary button border, increased contrast"),
]


def rgba(hex_value):
    r, g, b = (int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(hex_value[6:8], 16) / 255 if len(hex_value) == 8 else 1.0
    return r, g, b, a


def composite(over, under):
    """`over` drawn on an opaque `under`, as an opaque hex."""
    r1, g1, b1, a = rgba(over)
    r2, g2, b2, _ = rgba(under)
    mix = [c1 * a + c2 * (1 - a) for c1, c2 in zip((r1, g1, b1), (r2, g2, b2))]
    return "".join(f"{round(c * 255):02X}" for c in mix)


def luminance(hex_value):
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b, _ = rgba(hex_value)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def value(name, index):
    """Index 0 light, 1 dark, 2 light high contrast, 3 dark high contrast (falls back)."""
    values = COLORS[name]
    if index >= 2 and len(values) < 4:
        index -= 2
    return values[index]


def resolve(spec, index, against):
    """A token, or "Over/Under" composited; translucent colors land on `against`."""
    if "/" in spec:
        over, under = spec.split("/")
        return composite(value(over, index), resolve(under, index, against))
    color = value(spec, index)
    return composite(color, against) if len(color) == 8 else color


def colorset(values):
    def entry(hex_value, appearances):
        r, g, b, a = rgba(hex_value)
        item = {
            "color": {
                "color-space": "srgb",
                "components": {"red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}", "alpha": f"{a:.3f}"},
            },
            "idiom": "universal",
        }
        if appearances:
            item["appearances"] = appearances
        return item
    dark = {"appearance": "luminosity", "value": "dark"}
    high = {"appearance": "contrast", "value": "high"}
    colors = [entry(values[0], []), entry(values[1], [dark])]
    if len(values) == 4:
        colors += [entry(values[2], [high]), entry(values[3], [dark, high])]
    return {"colors": colors, "info": {"author": "xcode", "version": 1}}


def asset_path(name):
    # AccentColor stays at the catalog root, where Xcode looks for the app's tint.
    folder = ASSETS if name == "AccentColor" else os.path.join(ASSETS, "Tokens")
    return os.path.join(folder, f"{name}.colorset", "Contents.json")


def expected_files():
    files = {asset_path(n): json.dumps(colorset(v), indent=2) + "\n" for n, v in COLORS.items()}
    files[os.path.join(ASSETS, "Tokens", "Contents.json")] = json.dumps(
        {"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    return files


def check_contrast():
    failures = []
    modes = (("light", 0), ("dark", 1), ("light, increased contrast", 2), ("dark, increased contrast", 3))
    count = 0
    for pairs, mode_list in ((PAIRS, modes), (HIGH_CONTRAST_PAIRS, modes[2:])):
        for mode, index in mode_list:
            for fg, bg, minimum, use in pairs:
                ground = value("Ground", index)
                back = resolve(bg, index, ground)
                fore = resolve(fg, index, back)
                ratio = contrast(fore, back)
                count += 1
                if ratio < minimum:
                    failures.append(f"{mode}: {fg} on {bg} is {ratio:.2f}:1, needs {minimum}:1 ({use})")
    return failures, count


def main():
    files = expected_files()
    failures, count = check_contrast()
    if "--check" in sys.argv:
        for path, content in files.items():
            if not os.path.exists(path) or open(path).read() != content:
                failures.append(f"{os.path.relpath(path, ROOT)} is stale: run scripts/design-tokens.py")
        for failure in failures:
            print(failure)
        print(f"{count} contrast checks, {len(failures)} problems")
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
