# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-CARTES-001, étape E2 : « Créer des cartes de cette page » propose le lexique (coché) puis les autres mots de la
page trouvés dans les dictionnaires (décochés). Contrôle de la source (vue SwiftUI non compilée par `swift test`) ; le
découpage et la recherche sont testés en Swift (`PageWordCandidatesTests`, `LexiconSavedWordsTests`)."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


class PageCardsWordsWiringTests(unittest.TestCase):
    def setUp(self):
        self.view = (APP / "Review/PageCardsView.swift").read_text(encoding="utf-8")

    def test_two_sections_lexicon_checked_others_unchecked(self):
        self.assertIn("wordSection(lexicon: true)", self.view)
        self.assertIn("wordSection(lexicon: false)", self.view)
        self.assertIn("selected = Set(words.filter { $0.fromLexicon && $0.existingDocumentId == nil }.map(\\.id))", self.view)

    def test_other_words_come_from_mecab_and_active_dictionaries_off_main_thread(self):
        self.assertIn("PageWordCandidates.words(mecab.tokens(text), excluding: lexiconTerms)", self.view)
        self.assertIn("dictionary.activeTermDictionaryIds", self.view)
        self.assertIn("Task.detached(priority: .userInitiated)", self.view)
        self.assertIn("onCancel: { work.cancel() }", self.view)

    def test_existing_cards_are_flagged_and_adding_keeps_the_same_path(self):
        self.assertIn("store.existingCardDocuments(keys)", self.view)
        self.assertIn("review.addPageCards(fields, documentId: document.id, page: page)", self.view)

    def test_cards_get_the_full_definition(self):
        # Revue Codex après 1.5.6 (P2 n°2) : jamais l'aperçu coupé à 90 caractères.
        self.assertIn("let meaning = sense?.full ?? \"\"", self.view)
        self.assertNotIn("word.senses.first?.short", self.view)


if __name__ == "__main__":
    unittest.main()
