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
    def test_people_places_and_disambiguation_pages_are_left_out_unless_chosen(self):
        pages = [
            {"title": "試験太郎", "extract": "試験太郎（1950年生まれ）は、日本の人物。"},
            {"title": "試験大学", "extract": "試験の学校。"},
            {"title": "試験床", "extract": "床の曖昧さ。", "disambiguation": True},
            {"title": "試験材", "extract": "内装に使う材料。"},
            {"title": "天井", "extract": "ある大学の研究では部屋の上面。"},
        ]
        self.assertEqual({row[0] for row in lexicon.term_rows([], pages)}, {"試験材", "天井"})

    def test_french_definition_comes_first_with_its_source(self):
        page = {"title": "試験材", "extract": "内装に使う材料。", "langlinks": {"fr": "Matériau d'essai", "en": "Test material"}}
        enrichment = {"french": {"Matériau d'essai": "Un matériau d'essai sert aux tests. Il existe aussi autre chose."}}
        row = lexicon.term_rows([], [page], enrichment)[0]
        self.assertEqual(row[5][:2], ["Français : Matériau d'essai", "Un matériau d'essai sert aux tests."])
        self.assertEqual(row[5][-2]["content"]["content"], "Source : Wikipédia en français")
        self.assertEqual(row[4], 3)

    def test_french_definition_ignores_disambiguation_and_cuts_long_text(self):
        self.assertEqual(lexicon.french_definition("Le mot Essai peut désigner plusieurs choses."), "")
        self.assertLessEqual(len(lexicon.french_definition("mot " * 200)), lexicon.FRENCH_LIMIT)

    def test_nature_from_wikidata_removes_people_and_unrelated_species(self):
        pages = [{"title": "試験人", "extract": "説明。"}, {"title": "試験草", "extract": "植物。"},
                 {"title": "試験杉", "extract": "木材として使う。"}]
        enrichment = {"items": {"試験人": {"natures": ["Q5"]}, "試験草": {"natures": ["Q16521"]},
                                "試験杉": {"natures": ["Q16521"]}}}
        self.assertEqual({r[0] for r in lexicon.term_rows([], pages, enrichment)}, {"試験杉"})

    def test_wikidata_adds_only_missing_terms_with_its_source(self):
        pages = [{"title": "試験材", "extract": "材料。"}]
        extra = [{"term": "試験材", "french": "doublon", "item": "Q1"}, {"term": "試験扉", "french": "porte d'essai", "item": "Q2"}]
        rows = {r[0]: r for r in lexicon.term_rows([], pages, {"extra": extra})}
        self.assertNotIn("Français : doublon", rows["試験材"][5])
        self.assertEqual(rows["試験扉"][5][0], "Français : porte d'essai")
        self.assertEqual(rows["試験扉"][5][-1]["content"]["content"], "Source : Wikidata")

    def test_wikidata_noise_is_left_out(self):
        extra = [{"term": "試験24", "french": "x", "item": "Q1"}, {"term": "基質 (生物学)", "french": "x", "item": "Q2"},
                 {"term": "試験素", "french": "x", "description": "isotope de x", "item": "Q3"}]
        self.assertEqual(lexicon.term_rows([], [], {"extra": extra}), [])

    def test_written_definitions_file_is_complete(self):
        written = json.loads((Path(lexicon.__file__).with_name("lexique_definitions_fr.json")).read_text(encoding="utf-8"))
        self.assertGreater(len(written), 50)
        for term, entry in written.items():
            self.assertTrue(entry["french"] and entry["definition"] and entry["reading"], term)

    def test_law_definitions_are_read_from_two_columns_and_keep_their_article(self):
        xml = """<law><Article Num="2"><Paragraph>
          <Item Num="4"><ItemTitle>四</ItemTitle><ItemSentence><Column><Sentence>試験室</Sentence></Column>
            <Column><Sentence>試験に使う室をいう。</Sentence></Column></ItemSentence></Item>
          <Item Num="5"><ItemTitle>五</ItemTitle><ItemSentence><Column><Sentence>対象外</Sentence></Column>
            <Column><Sentence>読まない。</Sentence></Column></ItemSentence></Item>
        </Paragraph></Article></law>"""
        definitions = lexicon.law_definitions(xml, "ID", "試験法", "2", ("4",))
        self.assertEqual(definitions, [{"term": "試験室", "text": "試験に使う室をいう。", "source": "試験法 第2条第四号",
                                        "url": "https://laws.e-gov.go.jp/law/ID"}])

    def test_law_text_is_added_to_an_existing_entry_or_makes_a_new_one(self):
        laws = [{"term": "試験材", "text": "材料をいう。", "source": "試験法 第2条第四号", "url": "https://x"},
                {"term": "試験室", "text": "室をいう。", "source": "試験法 第2条第五号", "url": "https://y"}]
        rows = {r[0]: r for r in lexicon.term_rows([], [{"title": "試験材", "extract": "材料。"}], {"laws": laws})}
        self.assertIn("Définition légale (試験法 第2条第四号) : 材料をいう。", rows["試験材"][5])
        self.assertEqual(rows["試験室"][2], "law")
        self.assertEqual(rows["試験室"][5][-1]["content"]["content"], "Source : e-Gov 法令検索")

    def test_written_definition_is_marked_as_written_by_ai(self):
        written = {"試験材": {"french": "matériau d'essai", "definition": "Sert aux tests."}}
        row = lexicon.term_rows([], [{"title": "試験材", "extract": "材料。"}], {"written": written})[0]
        self.assertEqual(row[5][:3], ["Français : matériau d'essai", "Sert aux tests.", "Explication rédigée par une IA, à vérifier."])

    def test_other_spelling_gets_the_same_definition(self):
        page = {"title": "建蔽率", "extract": "敷地に対する割合。", "aliases": ["建ぺい率"]}
        rows = {row[0]: row for row in lexicon.term_rows([], [page])}
        self.assertEqual(rows["建ぺい率"][5], rows["建蔽率"][5])

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
        self.assertEqual(board[5][-1]["content"]["content"], "Source : Wikipédia en japonais")
        self.assertTrue(board[5][-1]["content"]["href"].startswith("https://ja.wikipedia.org/wiki/"))
        self.assertTrue(rows[0][5][-1]["content"]["href"].startswith("https://fr.wiktionary.org/wiki/"))

    def test_build_writes_a_yomitan_archive_with_attribution(self):
        with tempfile.TemporaryDirectory(prefix="kyokasho-lexicon-synthetic-") as folder:
            raw = Path(folder)
            (raw / "wiktionary.json").write_text(json.dumps([{"title": "試験間", "wikitext": WIKTIONARY_PAGE}]), encoding="utf-8")
            (raw / "wikipedia.json").write_text("[]", encoding="utf-8")
            output = raw / "sortie" / "lexique.zip"
            self.assertEqual(lexicon.build(raw, output, "2026-10-29", written={}), 1)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(sorted(archive.namelist()), ["index.json", "tag_bank_1.json", "term_bank_1.json"])
                index = json.loads(archive.read("index.json"))
                self.assertEqual((index["format"], index["revision"]), (3, "2026-10-29"))
                self.assertIn("CC BY-SA 4.0", index["attribution"])
                tags = {tag[0] for tag in json.loads(archive.read("tag_bank_1.json"))}
                for row in json.loads(archive.read("term_bank_1.json")):
                    self.assertEqual(len(row), 8)
                    self.assertTrue(set(row[2].split() + row[7].split()) <= tags)


class ManualTermTests(unittest.TestCase):
    """Termes relevés dans le manuel : jamais dans le dépôt, donc fabriqués ici avec des exemples inventés."""

    TERMS = [
        {"terme": "試験吊", "lecture": "しけんづり", "fr": "suspension d'essai", "en": "test pendant",
         "definition_fr": "Luminaire suspendu de test.", "page": "12", "confiance": "élevée"},
        {"terme": "試験LED", "lecture": "しけんLED", "fr": "diode de test", "en": "test light-emitting diode",
         "definition_fr": "Diode de test.", "page": "13", "confiance": "moyenne"},
    ]

    def write(self, folder, lines):
        path = Path(folder) / "termes.jsonl"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def test_terms_are_read_with_cleaned_reading_and_page(self):
        with tempfile.TemporaryDirectory(prefix="kyokasho-manual-") as folder:
            path = self.write(folder, [json.dumps(item, ensure_ascii=False) for item in self.TERMS])
            terms = lexicon.read_manual_terms(path)
        self.assertEqual([term["term"] for term in terms], ["試験吊", "試験LED"])
        self.assertEqual(terms[1]["reading"], "しけんLED", "une lecture qui contient du kana est gardée")
        self.assertEqual((terms[0]["page"], terms[0]["confidence"]), ("12", "élevée"))

    def test_reading_without_kana_is_dropped(self):
        self.assertEqual(lexicon.manual_reading("?"), "")
        self.assertEqual(lexicon.manual_reading("TEST-LED"), "")
        self.assertEqual(lexicon.manual_reading(" しけん "), "しけん")

    def test_incomplete_or_duplicated_lines_stop_the_build(self):
        incomplete = dict(self.TERMS[0], definition_fr="")
        with tempfile.TemporaryDirectory(prefix="kyokasho-manual-") as folder:
            path = self.write(folder, [json.dumps(incomplete, ensure_ascii=False)])
            with self.assertRaises(ValueError):
                lexicon.read_manual_terms(path)
            path = self.write(folder, [json.dumps(item, ensure_ascii=False) for item in self.TERMS * 2])
            with self.assertRaises(ValueError):
                lexicon.read_manual_terms(path)

    def test_manual_rows_carry_their_own_tag_page_and_warning(self):
        with tempfile.TemporaryDirectory(prefix="kyokasho-manual-") as folder:
            path = self.write(folder, [json.dumps(item, ensure_ascii=False) for item in self.TERMS])
            rows = lexicon.manual_rows(lexicon.read_manual_terms(path))
        self.assertEqual([row[2] for row in rows], [lexicon.MANUAL_TAG, lexicon.MANUAL_TAG])
        self.assertEqual(rows[0][5][0], "Français : suspension d'essai")
        self.assertEqual(rows[0][5][1], "Luminaire suspendu de test.")
        self.assertIn("page 12", rows[0][5][2])
        self.assertIn("à vérifier", rows[0][5][2])
        self.assertEqual(rows[0][4], 1, "relevé non vérifié : score bas, après les sources")

    def test_english_manual_rows_keep_no_french_definition(self):
        rows = lexicon.manual_rows([{"term": "試験吊", "reading": "", "fr": "suspension d'essai", "en": "test pendant",
                                     "definition": "Luminaire suspendu de test.", "page": "12", "confidence": "moyenne"}],
                                   "en")
        self.assertEqual(rows[0][5][0], "English : test pendant")
        self.assertNotIn("Luminaire suspendu de test.", rows[0][5])
        self.assertIn("page 12", rows[0][5][1])
        self.assertIn("medium", rows[0][5][1])

    def test_a_sourced_entry_is_never_replaced(self):
        sourced = [["試験吊", "しけんづり", "wp", "", 3, ["Français : suspension de test"], 1, "interieur"]]
        merged, added = lexicon.merge_manual_rows(sourced, [
            {"term": "試験吊", "reading": "", "fr": "autre", "en": "other", "definition": "Autre.", "page": "12",
             "confidence": "faible"}])
        self.assertEqual(added, [])
        self.assertEqual(merged, sourced)

    def test_merging_renumbers_sequences_once(self):
        sourced = [["試験間", "", "wikt", "", 2, ["Pièce de test."], 1, "interieur"]]
        merged, added = lexicon.merge_manual_rows(sourced, [
            {"term": f"term{number}", "reading": "", "fr": item["fr"], "en": item["en"], "definition": item["definition_fr"],
             "page": item["page"], "confidence": item["confiance"]} for number, item in enumerate(self.TERMS)])
        self.assertEqual(len(added), 2)
        self.assertEqual([row[6] for row in merged], [1, 2, 3])

    def test_build_adds_manual_terms_with_tag_and_attribution(self):
        with tempfile.TemporaryDirectory(prefix="kyokasho-lexicon-synthetic-") as folder:
            raw = Path(folder)
            (raw / "wiktionary.json").write_text(json.dumps([{"title": "試験間", "wikitext": WIKTIONARY_PAGE}]), encoding="utf-8")
            (raw / "wikipedia.json").write_text("[]", encoding="utf-8")
            extra = lexicon.read_manual_terms(self.write(folder, [json.dumps(item, ensure_ascii=False) for item in self.TERMS]))
            output = raw / "sortie" / "lexique.zip"
            self.assertEqual(lexicon.build(raw, output, "2026-11-10.1", written={}, extra=extra), 3)
            with zipfile.ZipFile(output) as archive:
                index = json.loads(archive.read("index.json"))
                tags = {tag[0]: tag[3] for tag in json.loads(archive.read("tag_bank_1.json"))}
                rows = json.loads(archive.read("term_bank_1.json"))
        self.assertIn(lexicon.MANUAL_TAG_LABEL, tags[lexicon.MANUAL_TAG])
        self.assertIn(lexicon.MANUAL_ATTRIBUTION, index["attribution"])
        self.assertIn("man", index["description"])
        self.assertEqual([row[0] for row in rows][-2:], ["試験吊", "試験LED"])


if __name__ == "__main__":
    unittest.main()
