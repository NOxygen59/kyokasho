# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


localize = load("localize_domain_lexicon")
pack = load("copy_bundled_lexicons")


class LexiconLanguagesTests(unittest.TestCase):
    def setUp(self):
        self.index = {"title": "source", "revision": "1", "targetLanguage": "fr", "attribution": "CC BY-SA origin"}
        self.tags = [[name, "source", 0, name, 0] for name in ["wikt", "wp", "wd", "law", "interieur"]]
        self.rows = [["天井", "てんじょう", "wp", "", 3, ["Plafond.", localize.AI,
            {"type": "structured-content", "content": {"tag": "a", "href": "https://example.org/天井",
             "content": "Source : Wikipédia en japonais"}}], 1, "interieur"]]
        self.cache = {"translations": {"Plafond.": {"en": "Ceiling.", "zh-Hans": "天花板。"}}, "literalTranslations": {"1": "天花板"}}

    def test_terms_readings_links_and_ai_notice_are_preserved(self):
        for language in ["en", "zh-Hans"]:
            index, _, rows = localize.localize(self.index, self.tags, self.rows, self.cache, language)
            self.assertEqual(rows[0][:5], self.rows[0][:5])
            self.assertEqual(rows[0][6:], self.rows[0][6:])
            self.assertEqual(rows[0][5][2]["content"]["href"], self.rows[0][5][2]["content"]["href"])
            self.assertIn(localize.WARNINGS[language], rows[0][5])
            self.assertIn(localize.MACHINE[language], rows[0][5])
            self.assertIn(self.index["attribution"], index["attribution"])
            self.assertEqual(index["targetLanguage"], language)
        self.assertEqual(self.rows[0][5][0], "Plafond.", "Source must not be mutated")

    def test_missing_translation_refuses_instead_of_leaving_french(self):
        del self.cache["translations"]["Plafond."]["en"]
        with self.assertRaises(ValueError):
            localize.localize(self.index, self.tags, self.rows, self.cache, "en")

    def archive(self, path, language):
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("index.json", json.dumps({"targetLanguage": language}))

    def test_ios_excludes_chinese_mac_copies_all_and_french_override_survives(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, ios, mac = [root / name for name in ["source", "ios", "mac"]]
            for path in [source, ios, mac]:
                path.mkdir()
            french = source / "custom.zip"
            self.archive(french, "fr")
            self.archive(source / "lexique-interieur-en.zip", "en")
            self.archive(source / "lexique-interieur-zh-Hans.zip", "zh-Hans")
            self.assertEqual(pack.copy_lexicons(source, ios, "ios", french), ["lexique-interieur.zip", "lexique-interieur-en.zip"])
            self.assertFalse((ios / "lexique-interieur-zh-Hans.zip").exists())
            self.assertEqual(len(pack.copy_lexicons(source, mac, "macos", french)), 3)
            self.archive(ios / "lexique-interieur-zh-Hans.zip", "zh-Hans")
            with self.assertRaises(ValueError):
                pack.copy_lexicons(source, ios, "ios", french)

    def test_wrong_language_refuses_before_any_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, app = root / "source", root / "app"
            source.mkdir(); app.mkdir()
            self.archive(source / "lexique-interieur.zip", "fr")
            self.archive(source / "lexique-interieur-en.zip", "fr")
            with self.assertRaises(ValueError):
                pack.copy_lexicons(source, app, "ios")
            self.assertEqual(list(app.iterdir()), [])

    def test_app_lookup_paths_use_the_language_filter(self):
        text = (Path(__file__).resolve().parents[1] / "App/Dictionary/DictionaryModel.swift").read_text()
        self.assertEqual(text.count("let options = lookupOptions"), 2, "lookup and segment")
        self.assertIn("!lookupOptions.excludedDictionaryIds.contains", text, "prefix words")
        self.assertIn("options.excludedDictionaryIds.formUnion(BundledLexicon.excludedDictionaryIds", text)

    def test_language_offer_is_checked_before_weekly_network_schedule(self):
        text = (Path(__file__).resolve().parents[1] / "App/Dictionary/DictionaryCatalogService.swift").read_text()
        check = text.split("func checkAutomaticallyIfDue", 1)[1].split("func installOfferedUpdates", 1)[0]
        self.assertLess(check.index("bundledUpdateAvailable"), check.index("DictionaryUpdateSchedule.isDue"))
        self.assertIn("discardOtherLanguageOffers()", check)
        self.assertIn('"dictionaries.bundledOfferedRevision." + BundledLexicon.selectedLanguage.rawValue', text)


if __name__ == "__main__":
    unittest.main()
