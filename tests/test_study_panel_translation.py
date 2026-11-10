# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de la revue DeepSeek #10 (C3.1) : la traduction DeepL du panneau suit le texte.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas
l'affichage réel sur l'iPad.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class StudyPanelTranslationTests(unittest.TestCase):
    def setUp(self):
        self.panel = (ROOT / "App/Study/StudyPanel.swift").read_text(encoding="utf-8")
        self.block = body_of(self.panel, "    private func translationBlock(for text: String)",
                             "    private var documentOCRRow")

    def test_block_only_shows_the_translation_of_the_current_text(self):
        self.assertIn("@State private var translatedText: String?", self.panel)
        self.assertIn("let shown = translatedText == text ? translation : nil", self.block)
        self.assertIn("if let shown {", self.block)
        self.assertNotIn("if let translation {", self.block,
                         "le bloc ne lit plus l'état sans le comparer au texte")
        self.assertIn("if shown == nil {", self.block, "le bouton « Traduire » revient quand le texte a changé")

    def test_translation_records_the_text_it_came_from(self):
        translate = body_of(self.panel, "    private func translate(_ text: String) async", "\n    }\n}")
        self.assertIn("translation = try await DeepLService.shared.translate(text)", translate)
        self.assertLess(translate.index("translation = try await"), translate.index("translatedText = text"),
                        "le texte est noté avec la traduction, même si la page change pendant l'attente")

    def test_changing_page_forgets_both(self):
        start = self.panel.index(".onChange(of: reader.focusSource) { _ in")
        page_change = self.panel[start:self.panel.index("translationCopiedAt = nil", start)]
        self.assertIn("translation = nil", page_change)
        self.assertIn("translatedText = nil", page_change)


if __name__ == "__main__":
    unittest.main()
