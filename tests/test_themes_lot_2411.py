# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Thèmes du 24/11/2026 (Genkō, Riso, Shōwa, Kokuban, Contour) : palettes listées, fonds branchés, textes traduits,
contrastes de la maquette. Le rendu réel des fonds se vérifie sur l'iPad."""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDS = ["genko", "riso", "showa", "kokuban", "contour"]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def luminance(hex_value):
    channels = [int(hex_value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    channels = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


class ThemesLot2411Tests(unittest.TestCase):
    def test_themes_listed_and_backdrops_wired(self):
        themes = source("App/Design/Themes.swift")
        backdrop = source("App/Design/ThemeBackdrop.swift")
        drawings = source("App/Design/ThemeBackdropJapon.swift")
        all_line = re.search(r"static let all: \[Theme\] = \[(.*?)\]", themes, re.S).group(1)
        for theme_id in IDS:
            self.assertIn(f".{theme_id}", all_line)
            self.assertIn(f'id: "{theme_id}"', themes)
            self.assertIn(f'case "{theme_id}": return "', themes)  # symbole et ambiance
            self.assertIn(f"case .{theme_id}: Self.{theme_id}(&context, size, theme)", backdrop)
            self.assertIn(f"static func {theme_id}(", drawings)

    def test_function_colors_keep_contrast(self):
        # Même règle que la maquette : 4,5:1 sur les trois fonds et sous le texte posé sur la couleur (`onAccent`).
        themes = source("App/Design/Themes.swift")
        for theme_id in IDS:
            block = themes.split(f'id: "{theme_id}"', 1)[1].split("static let", 1)[0]
            colors = dict(re.findall(r"(\w+): Color\(hex: 0x([0-9A-F]{6})\)", block))
            on_accent = colors.get("onAccent", "000000")
            for function in ("read", "annotate", "japanese", "ai", "cloud"):
                for ground in ("canvas", "surface", "surfaceHigh"):
                    self.assertGreaterEqual(ratio(colors[function], colors[ground]), 4.5, f"{theme_id} {function}/{ground}")
                self.assertGreaterEqual(ratio(colors[function], on_accent), 4.5, f"{theme_id} {function}/onAccent")

    def test_names_translated(self):
        strings = json.loads(source("App/Resources/Localizable.xcstrings"))["strings"]
        themes = source("App/Design/Themes.swift")
        for theme_id in IDS:
            name = re.search(rf'id: "{theme_id}", name: String\(localized: "([^"]+)"\)', themes).group(1)
            atmosphere = re.search(rf'case "{theme_id}": return String\(localized: "([^"]+)"\)', themes).group(1)
            for key in (name, atmosphere):
                self.assertEqual(set(strings[key]["localizations"]), {"en", "fr", "zh-Hans"}, key)


if __name__ == "__main__":
    unittest.main()
