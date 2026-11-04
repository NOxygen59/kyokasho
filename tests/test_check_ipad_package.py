# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Le contrôle du paquet iPad doit bloquer tout contenu réservé au Mac."""

import plistlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from check_ipad_package import problems  # noqa: E402


class CheckIPadPackageTests(unittest.TestCase):
    def make_app(self, root: Path) -> Path:
        app = root / "Kyokasho.app"
        (app / "fr.lproj").mkdir(parents=True)
        (app / "lexique-interieur.zip").touch()
        (app / "lexique-interieur-en.zip").touch()
        with (app / "Info.plist").open("wb") as target:
            plistlib.dump({"CFBundleLocalizations": ["fr", "en"]}, target)
        return app

    def test_clean_package_passes(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(problems(self.make_app(Path(folder))), [])

    def test_mac_only_content_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.make_app(Path(folder))
            (app / "GRDB.bundle/zh-Hans.lproj").mkdir(parents=True)
            (app / "llama-server").touch()
            (app / "lexique-interieur-zh-Hans.zip").touch()
            with (app / "Info.plist").open("wb") as target:
                plistlib.dump({"CFBundleLocalizations": ["fr", "en", "zh-Hans"]}, target)
            self.assertEqual(len(problems(app)), 4)

    def test_missing_english_lexicon_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.make_app(Path(folder))
            (app / "lexique-interieur-en.zip").unlink()
            self.assertEqual(problems(app), ["Lexique absent : lexique-interieur-en.zip"])


if __name__ == "__main__":
    unittest.main()
