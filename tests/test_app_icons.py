# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
from pathlib import Path
import plistlib
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "App/Resources/Assets.xcassets"
ALTERNATES = ("AppIconNavy", "AppIconJade", "AppIconCharcoal")


class AppIconConfigurationTests(unittest.TestCase):
    def test_info_plist_declares_the_same_three_alternates_for_ipad(self):
        with (ROOT / "App/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            icons = info[key]
            self.assertEqual(icons["CFBundlePrimaryIcon"]["CFBundleIconName"], "AppIcon")
            self.assertEqual(set(icons["CFBundleAlternateIcons"]), set(ALTERNATES))
            for name in ALTERNATES:
                self.assertEqual(icons["CFBundleAlternateIcons"][name]["CFBundleIconName"], name)

    def test_every_icon_asset_has_one_opaque_1024_png(self):
        for name in ("AppIcon",) + ALTERNATES:
            folder = ASSETS / f"{name}.appiconset"
            metadata = json.loads((folder / "Contents.json").read_text())
            self.assertEqual(metadata["images"][0]["filename"], "AppIcon-1024.png")
            png = (folder / "AppIcon-1024.png").read_bytes()
            self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
            width, height, depth, color_type = struct.unpack(">IIBB", png[16:26])
            self.assertEqual((width, height, depth), (1024, 1024, 8))
            self.assertEqual(color_type, 2, f"{name} doit être RGB sans canal alpha")

    def test_settings_expose_all_six_areas_and_icon_route(self):
        navigation = (ROOT / "App/Settings/SettingsNavigation.swift").read_text()
        self.assertIn("case general, reading, aiText, japaneseReview, data, help", navigation)
        self.assertIn("case .general: return [.theme, .appIcon, .intro]", navigation)
        self.assertIn("case .appIcon: AppIconSettingsView()", navigation)
        view = (ROOT / "App/Settings/AppIconSettingsView.swift").read_text()
        for name in ALTERNATES:
            self.assertIn(f'"{name}"', view)

    def test_candidate_build_and_asset_compiler_settings_are_pinned(self):
        project = (ROOT / "project.yml").read_text()
        self.assertRegex(project, r'CURRENT_PROJECT_VERSION: "\d+"')
        self.assertIn("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES", project)
        for name in ALTERNATES:
            self.assertIn(name, project)


if __name__ == "__main__":
    unittest.main()
