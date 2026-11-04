# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
from pathlib import Path
import plistlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("fr", "en", "zh-Hans")
SPEC = re.compile(r"%(?:(\d+)\$)?(\.\d+f|0?\d*(?:lld|llu|d|f|@))")


def kinds(text):
    """Variables d'un texte : (position explicite ou None, type)."""
    text = text.replace("%%", "")
    return [(match.group(1), re.sub(r"[0-9.]", "", match.group(2))) for match in SPEC.finditer(text)]


def variables_match(source, translated):
    """Préserve les types ; une omission ou permutation exige des positions explicites valides."""
    expected = [kind for _, kind in kinds(source)]
    found = kinds(translated)
    if any(position for position, _ in found):
        return all(position is not None and 1 <= int(position) <= len(expected)
                   and expected[int(position) - 1] == kind for position, kind in found)
    return [kind for _, kind in found] == expected


class FormatParsingTests(unittest.TestCase):
    def test_usual_variables_are_really_recognized(self):
        self.assertEqual(kinds("%lld page%@"), [(None, "lld"), (None, "@")])
        self.assertEqual(kinds("%d h %02d · %.1f"), [(None, "d"), (None, "d"), (None, "f")])
        self.assertEqual(kinds("%llu"), [(None, "llu")])

    def test_positions_and_literal_percent_are_recognized(self):
        self.assertEqual(kinds("%2$@ : %1$lld · 90 %%"), [("2", "@"), ("1", "lld")])
        self.assertEqual(kinds("%%@"), [])

    def test_invalid_translations_are_rejected(self):
        for source, translated in [
            ("%lld", "%@"),
            ("%lld %@", "%lld"),
            ("%lld", "%lld %@"),
            ("%lld", "%0$lld"),
            ("%lld", "%2$lld"),
            ("%lld %@", "%1$@"),
            ("%lld %@", "%1$lld %@"),
        ]:
            with self.subTest(source=source, translated=translated):
                self.assertFalse(variables_match(source, translated))

    def test_safe_reordering_and_positional_omissions_are_allowed(self):
        self.assertTrue(variables_match("%lld page%@", "%1$lld 页"))
        self.assertTrue(variables_match("%lld %@", "%2$@ %1$lld"))
        self.assertTrue(variables_match("%.1f", "%1$.2f"))
        self.assertTrue(variables_match("%lld %%", "%lld %%"))


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
            for language in LANGUAGES:
                translated = entry["localizations"][language]["stringUnit"]["value"]
                with self.subTest(key=key, language=language):
                    self.assertTrue(variables_match(key, translated), translated)

    def test_french_agreements_are_not_reused_on_english_words_that_do_not_take_them(self):
        # « 2 pages addeds », « 2 uncertain liness » : revue Codex de la 1.4.0.
        wrong = re.compile(r"(added|deleted|selected|Restorable)%(?:\d+\$)?@|line%(?:\d+\$)?@%(?:\d+\$)?@")
        for key, entry in self.strings.items():
            if re.search(r"[a-zé]%@", key):
                self.assertIsNone(wrong.search(entry["localizations"]["en"]["stringUnit"]["value"]), key)

    def test_info_plist_declares_the_three_languages(self):
        with (ROOT / "App/Info.plist").open("rb") as stream:
            self.assertEqual(set(plistlib.load(stream)["CFBundleLocalizations"]), set(LANGUAGES))


if __name__ == "__main__":
    unittest.main()
