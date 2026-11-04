# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
from pathlib import Path
import plistlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("fr", "en", "zh-Hans")
SPEC = re.compile(r"%(?:(\\d+)\\$)?(\\.\\d+f|0?\\d*(?:lld|llu|d|f|@))")


def kinds(text):
    """Variables d'un texte : (position explicite ou None, type)."""
    text = text.replace("%%", "")
    return [(match.group(1), re.sub(r"[0-9.]", "", match.group(2))) for match in SPEC.finditer(text)]


class CatalogTests(unittest.TestCase):
    def setUp(self):
        catalog = json.loads((ROOT / "App/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))
        self.strings = catalog["strings"]

    def test_every_text_exists_in_every_language(self):
        missing = [(key, language) for key, entry in self.strings.items() for language in LANGUAGES
                   if language not in entry.get("localizations", {})]
        self.assertEqual(missing, [])

    def test_variables_are_kept_or_only_dropped_when_positional(self):
        # Une variable sautée n'est permise qu'avec des positions explicites : les accords français (« page%@ »).
        for key, entry in self.strings.items():
            source = [kind for _, kind in kinds(key)]
            for language in LANGUAGES:
                found = kinds(entry["localizations"][language]["stringUnit"]["value"])
                if any(position for position, _ in found):
                    for position, kind in found:
                        self.assertIsNotNone(position, (key, language))
                        self.assertEqual(source[int(position) - 1], kind, (key, language))
                else:
                    self.assertEqual([kind for _, kind in found], source, (key, language))

    def test_french_agreements_are_not_reused_on_english_words_that_do_not_take_them(self):
        # « 2 pages addeds », « 2 uncertain liness » : revue Codex de la 1.4.0.
        wrong = re.compile(r"(added|deleted|selected|Restorable)%(?:\\d\\$)?@|line%(?:\\d\\$)?@%(?:\\d\\$)?@")
        for key, entry in self.strings.items():
            if re.search(r"[a-zé]%@", key):
                self.assertIsNone(wrong.search(entry["localizations"]["en"]["stringUnit"]["value"]), key)

    def test_info_plist_declares_the_three_languages(self):
        with (ROOT / "App/Info.plist").open("rb") as stream:
            self.assertEqual(set(plistlib.load(stream)["CFBundleLocalizations"]), set(LANGUAGES))


if __name__ == "__main__":
    unittest.main()
