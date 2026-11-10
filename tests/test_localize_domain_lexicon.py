# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
import importlib.util
import argparse
import hashlib
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


class ManualTermsInEnglishTests(unittest.TestCase):
    """Termes du manuel dans la version anglaise : exemples inventés, fichier hors dépôt."""

    SOURCE_ROW = ["天井", "てんじょう", "wp", "", 3, ["Plafond.", {"type": "structured-content", "content": {
        "tag": "a", "href": "https://example.org/天井", "content": "Source : Wikipédia en japonais"}}], 1, "interieur"]
    MANUAL = [{"terme": "試験吊", "lecture": "しけんづり", "fr": "suspension d'essai", "en": "test pendant",
               "definition_fr": "Luminaire suspendu de test.", "page": "12", "confiance": "élevée"}]

    def make(self, folder, manual):
        root = Path(folder)
        source, extra, out = root / "source.zip", root / "termes.jsonl", root / "sortie"
        extra.write_text("\n".join(json.dumps(item, ensure_ascii=False) for item in manual) + "\n", encoding="utf-8")
        with zipfile.ZipFile(source, "w") as z:
            z.writestr("index.json", json.dumps({"title": "source", "revision": "2026-11-04.2", "targetLanguage": "fr",
                                                 "attribution": "CC BY-SA origin", "description": "source"}))
            z.writestr("tag_bank_1.json", json.dumps([[name, "source", 0, name, 0]
                                                      for name in ["wikt", "wp", "wd", "law", "interieur"]]))
            z.writestr("term_bank_1.json", json.dumps([self.SOURCE_ROW], ensure_ascii=False))
        cache = root / "cache.json"
        cache.write_text(json.dumps({"source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                     "translations": {"Plafond.": {"en": "Ceiling.", "zh-Hans": "天花板。"}},
                                     "literalTranslations": {"1": "天花板"}}), encoding="utf-8")
        return source, extra, cache, out

    def build(self, folder, manual, language="en"):
        source, extra, cache, out = self.make(folder, manual)
        args = argparse.Namespace(source=str(source), cache=str(cache), output=str(out), language=[language],
                                  extra=str(extra), revision="2026-11-10.1")
        localize.build(args)
        with zipfile.ZipFile(out / f"lexique-interieur-{language}.zip") as z:
            return (json.loads(z.read("index.json")), json.loads(z.read("tag_bank_1.json")),
                    json.loads(z.read("term_bank_1.json")))

    def test_english_archive_gets_manual_terms_tagged_and_untranslated(self):
        with tempfile.TemporaryDirectory() as folder:
            index, tags, rows = self.build(folder, self.MANUAL)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0][:5], self.SOURCE_ROW[:5], "l'entrée traduite ne doit pas bouger")
        self.assertEqual(rows[1][2], localize.lexicon.MANUAL_TAG)
        self.assertEqual(rows[1][1], "しけんづり")
        self.assertEqual(rows[1][5][0], "English : test pendant")
        self.assertNotIn("Luminaire suspendu de test.", rows[1][5], "aucune définition française dans l'anglais")
        self.assertIn("please verify", rows[1][5][1])
        labels = {tag[0]: tag[3] for tag in tags}
        self.assertEqual(labels[localize.lexicon.MANUAL_TAG], "Manual: automatic extraction, please verify")
        self.assertEqual(index["revision"], "2026-11-10.1.en.1")
        self.assertIn("CC BY-SA origin", index["attribution"])
        self.assertIn(localize.lexicon.MANUAL_ATTRIBUTION_EN, index["attribution"])

    def test_chinese_archive_stays_out_of_the_manual_scope(self):
        with tempfile.TemporaryDirectory() as folder:
            index, tags, rows = self.build(folder, self.MANUAL, "zh-Hans")
        self.assertEqual(len(rows), 1, "le chinois ne reçoit pas les termes du manuel")
        self.assertEqual(index["revision"], "2026-11-10.1.zh-Hans.1")

    def test_archive_without_manual_terms_keeps_its_five_tags(self):
        with tempfile.TemporaryDirectory() as folder:
            index, tags, rows = self.build(folder, [])
        self.assertEqual((len(rows), len(tags)), (1, 5))
        self.assertEqual(index["revision"], "2026-11-10.1.en.1")


if __name__ == "__main__":
    unittest.main()
