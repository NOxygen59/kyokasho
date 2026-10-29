# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_domain_lexicon as lexicon


# Pages fabriquées pour le test, au format des sources (aucun contenu réel recopié).
WIKTIONARY_PAGE = """== {{langue|fr}} ==
=== {{S|nom|fr}} ===
# Sens français à ignorer.

== {{langue|ja}} ==
=== {{S|étymologie}} ===
: {{composé de|m=1|lang=ja|試|tr1=shi}}.

=== {{S|nom|ja|clé=しけんま}} ===
{{ja-trans|試験間|しけんま||shikenma}}
{{ja-mot|試験間|shikenma}} {{pron|ɕi.keɴ.ma|ja}}
# {{lexique|architecture|ja|clé=しけんま}} [[pièce|Pièce]] de [[test]] {{note|{{lien|x|ja}}}}.
#* {{exemple|'''試験間'''で。|Dans la pièce.|lang=ja}}

==== {{S|synonymes}} ====
* {{lien|テスト室|ja}}

=== {{S|prononciation}} ===
* {{pron|ɕi.keɴ.ma|ja}}
"""


class LexiconTests(unittest.TestCase):
    def test_wiktionary_keeps_only_japanese_senses(self):
        entries = lexicon.wiktionary_entries("試験間", WIKTIONARY_PAGE)
        self.assertEqual(entries, [("試験間", "しけんま", "nom", ["Pièce de test."])])

    def test_wiktionary_reading_from_hira_parameter_or_sort_key(self):
        self.assertEqual(lexicon.wiktionary_reading("{{ja-trans|hira=おにがわら}}", "鬼瓦"), "おにがわら")
        self.assertEqual(lexicon.wiktionary_reading("=== {{S|nom|ja|clé=てすと}} ===", "試"), "てすと")
        self.assertEqual(lexicon.wiktionary_reading("", "テスト"), "テスト")
        self.assertEqual(lexicon.wiktionary_reading("", "試"), "")

    def test_empty_senses_are_dropped(self):
        page = "== {{langue|ja}} ==\n=== {{S|nom|ja}} ===\n# {{lexique|x|ja}} {{lien|y}}, ,.\n# Vrai sens."
        self.assertEqual(lexicon.wiktionary_entries("試", page), [("試", "", "nom", ["Vrai sens."])])

    def test_page_without_japanese_section_gives_nothing(self):
        self.assertEqual(lexicon.wiktionary_entries("test", "== {{langue|fr}} ==\n# Sens."), [])

    def test_wikipedia_reading_and_title(self):
        self.assertEqual(lexicon.wikipedia_reading("試験板", "試験板（しけんいた、英: test）は、試験の板。"), "しけんいた")
        self.assertEqual(lexicon.wikipedia_reading("試験板", "試験板（Test board）は、試験の板。"), "")
        self.assertEqual(lexicon.wikipedia_reading("テストボード", "説明。"), "テストボード")
        self.assertEqual(lexicon.wikipedia_title("試験板 (建築)"), "試験板")

    def test_first_sentence_is_short(self):
        self.assertEqual(lexicon.first_sentence("一文目。二文目。\n次の段落。"), "一文目。")
        self.assertLessEqual(len(lexicon.first_sentence("長" * 500)), lexicon.EXCERPT_LIMIT)

    def test_rows_skip_lists_and_cite_their_source(self):
        wikipedia = [
            {"title": "試験板 (建築)", "extract": "試験板（しけんいた）は、試験の板。詳細。",
             "langlinks": {"fr": "Planche d'essai", "en": "Test board"}},
            {"title": "試験の一覧", "extract": "一覧。", "langlinks": {}},
            {"title": "Test", "extract": "Latin seul.", "langlinks": {}},
            {"title": "試験館", "extract": "試験館（しけんかん）は、架空市にある建物。", "langlinks": {"fr": "Maison d'essai"}},
        ]
        rows = lexicon.term_rows([{"title": "試験間", "wikitext": WIKTIONARY_PAGE}], wikipedia)
        self.assertEqual([row[0] for row in rows], ["試験間", "試験板"])
        self.assertEqual([row[6] for row in rows], [1, 2])
        board = rows[1]
        self.assertEqual(board[1], "しけんいた")
        self.assertEqual(board[5][:3], ["Français : Planche d'essai", "Anglais : Test board", "試験板（しけんいた）は、試験の板。"])
        self.assertTrue(board[5][-1].startswith("Source : https://ja.wikipedia.org/wiki/"))
        self.assertTrue(rows[0][5][-1].startswith("Source : https://fr.wiktionary.org/wiki/"))

    def test_build_writes_a_yomitan_archive_with_attribution(self):
        with tempfile.TemporaryDirectory(prefix="kyokasho-lexicon-synthetic-") as folder:
            raw = Path(folder)
            (raw / "wiktionary.json").write_text(json.dumps([{"title": "試験間", "wikitext": WIKTIONARY_PAGE}]), encoding="utf-8")
            (raw / "wikipedia.json").write_text("[]", encoding="utf-8")
            output = raw / "sortie" / "lexique.zip"
            self.assertEqual(lexicon.build(raw, output, "2026-10-29"), 1)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(sorted(archive.namelist()), ["index.json", "tag_bank_1.json", "term_bank_1.json"])
                index = json.loads(archive.read("index.json"))
                self.assertEqual((index["format"], index["revision"]), (3, "2026-10-29"))
                self.assertIn("CC BY-SA 4.0", index["attribution"])
                tags = {tag[0] for tag in json.loads(archive.read("tag_bank_1.json"))}
                for row in json.loads(archive.read("term_bank_1.json")):
                    self.assertEqual(len(row), 8)
                    self.assertTrue(set(row[2].split() + row[7].split()) <= tags)


if __name__ == "__main__":
    unittest.main()
