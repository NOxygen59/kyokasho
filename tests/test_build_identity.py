# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Lot B1 (13/11/2026) : bon lexique trouvé ou refus, fiche d'identité sans donnée personnelle."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_manifest  # noqa: E402
import copy_bundled_lexicons as lex  # noqa: E402


def lexicon(path, language, revision):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("index.json", json.dumps({"targetLanguage": language, "revision": revision}))


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "lexique-interieur"
        lexicon(self.root / "lexique-interieur.zip", "fr", "2026-11-04.2")
        lexicon(self.root / "lexique-interieur-en.zip", "en", "2026-11-04.2.en.1")
        lexicon(self.root / "candidat-2026-11-10/lexique-interieur.zip", "fr", "2026-11-10.1")
        lexicon(self.root / "candidat-2026-11-10/lexique-interieur-en.zip", "en", "2026-11-10.1.en.1")
        self.app = Path(self.tmp.name) / "Kyokasho.app"
        self.app.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_old_default_lexicon_is_replaced_by_the_expected_revision(self):
        lex.copy_lexicons(self.root, self.app, "ios", self.root / "lexique-interieur.zip", "2026-11-10.1")
        self.assertEqual(lex.revision(self.app / "lexique-interieur.zip"), "2026-11-10.1")
        self.assertEqual(lex.revision(self.app / "lexique-interieur-en.zip"), "2026-11-10.1.en.1")

    def test_unknown_revision_refuses_to_build(self):
        with self.assertRaises(ValueError):
            lex.copy_lexicons(self.root, self.app, "ios", self.root / "lexique-interieur.zip", "2099-01-01.1")
        self.assertFalse((self.app / "lexique-interieur.zip").exists(), "rien de copié avant le refus")

    def test_manifest_lists_lexicons_and_never_absolute_paths(self):
        lex.copy_lexicons(self.root, self.app, "ios", self.root / "lexique-interieur.zip", "2026-11-10.1")
        data = build_manifest.app_manifest(ROOT, self.app, "9.9.9", "999", "REVUE-FINALE-abcdef1.md")
        self.assertEqual([l["revision"] for l in data["lexiques"]], ["2026-11-10.1.en.1", "2026-11-10.1"])
        text = json.dumps(data, ensure_ascii=False)
        self.assertNotIn(str(Path.home()), text)
        self.assertNotIn(self.tmp.name, text)
        tipa = Path(self.tmp.name) / "K.tipa"
        tipa.write_bytes(b"paquet")
        full = build_manifest.package_manifest(data, tipa, self.app / "absent", None)
        self.assertEqual(full["paquet"]["sha256"], build_manifest.sha256(tipa))
        self.assertFalse(full["symboles"]["correspondent"], "jamais de symboles déclarés sans contrôle")


if __name__ == "__main__":
    unittest.main()
