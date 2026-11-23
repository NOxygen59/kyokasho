# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.6.4 : gardes de câblage des corrections (recherche, barre du bas, accueil). Le comportement réel se
vérifie sur l'iPad."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class Recette164FixesTests(unittest.TestCase):
    def test_search_waits_for_ocr_and_reads_ai_text(self):
        search = source("App/Reader/ReaderController+Search.swift")
        self.assertIn("ocrSearchRunning = true", search)
        self.assertIn("Self.aiTextHits(trimmed", search)
        self.assertIn("DocumentAITextStore.read(documentId: documentId, reader: ModelSpec.ovisocr2.id", search)
        controller = source("App/Reader/ReaderController.swift")
        self.assertIn("isSearching = ocrSearchRunning", controller)
        self.assertLess(search.index("ocrSearchRunning = true"), search.index("pdf.beginFindString("))
        screen = source("App/Reader/ReaderScreen.swift")
        self.assertEqual(screen.count("openLineEditor: { [sheet = $sheet] in sheet.wrappedValue = .lineEditor }"), 2)
        service = source("Packages/KyokashoKit/Sources/OCRKit/OCRService.swift")
        self.assertIn("public nonisolated func search(", service)
        self.assertNotIn("additionalRotation(documentId: documentId, pageIndex: record.pageIndex)", service)

    def test_bottom_bar_width_does_not_depend_on_page_text(self):
        screen = source("App/Reader/ReaderScreen.swift")
        self.assertIn(".opacity(reader.pageHasText ? 1 : 0)", screen)
        self.assertNotIn("if reader.pageHasText {\n                    NewLayoutIconButton", screen)
        self.assertIn("bottomTools(compact: true, annotateLabel: true)", screen)
        # Point 13 : le champ de page (UIKit) hors des versions essayées par ViewThatFits.
        tools = screen.split("private func bottomTools(", 1)[1].split("private var bottomTail", 1)[0]
        self.assertNotIn("pageCounter", tools)
        self.assertNotIn("TextField", tools)
        self.assertIn("bottomTail.fixedSize()", screen)

    def test_resume_cards_can_be_dismissed_and_keep_natural_height(self):
        row = source("App/Library/ResumeRow.swift")
        self.assertIn("dismissed[doc.id] != doc.lastPageIndex", row)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", row)
        self.assertIn('Text("Retirer de Reprendre")', row)


if __name__ == "__main__":
    unittest.main()
