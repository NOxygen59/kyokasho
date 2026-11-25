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
        tools = screen.split("private func bottomTools(", 1)[1].split("private func bottomTail(", 1)[0]
        self.assertNotIn("pageCounter", tools)
        self.assertNotIn("TextField", tools)
        self.assertIn("bottomTail(aiAndWebInMenu: aiAndWebInMenu, webAllowed: webAllowed).fixedSize()", screen)

    def test_resume_cards_can_be_dismissed_and_keep_natural_height(self):
        row = source("App/Library/ResumeRow.swift")
        self.assertIn("dismissed[doc.id] != doc.lastPageIndex", row)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", row)
        self.assertIn('Text("Retirer de Reprendre")', row)
        # Retour d'usage du 24/11 : rangée repliable en pastilles rondes, choix gardé.
        self.assertIn('@AppStorage("library.resumeCollapsed")', row)
        self.assertIn("DocumentTileBar.glyph(document.title)", row)
        # Demande du 24/11 : ✕ rouge tant que l'onglet est ouvert, gris ensuite ; pastille bleue repliée = onglet ouvert.
        self.assertIn("isOpen ? Color(.systemRed) : Atelier.textSecondary", row)
        # Mesure SSH du 24/11 : rouvrir un livre retiré de Reprendre l'y remet.
        self.assertIn("ResumeRow.forgetDismissal(openDocumentId)", source("App/AppModel.swift"))
        self.assertIn("all.removeValue(forKey: id)", row)
        self.assertIn("if model.tabs.ids.contains(document.id) {\n                                            Circle().fill(Color(.systemBlue))", row)

    def test_bars_tried_by_view_that_fits_only_hold_the_relay(self):
        # Point 13 : les versions écartées par ViewThatFits restent en vie sous iOS 16 ; leurs boutons ne doivent
        # tenir que le relais faible, jamais l'écran (donc le lecteur).
        screen = source("App/Reader/ReaderScreen.swift")
        bodies = [
            screen.split("private func bottomTools(", 1)[1].split("private func bottomTail(", 1)[0],
            screen.split("private func annotationTools(", 1)[1].split("private enum AnnotationTool", 1)[0],
            screen.split("private func newActionsCapsule(", 1)[1].split("if monitorEnabled && monitorShown", 1)[0],
            screen.split("private func newPageArrow(", 1)[1].split("private func railDivider", 1)[0],
        ]
        for body in bodies:
            for action in ("selectAnnotationTool(", "stopAnnotating()", "startAnnotating()", "reader.toggleBookmark()",
                           "toggleStudyPanel()", "searchCardShown = true", "reader.next()", "reader.endLookup()",
                           "reader.setFurigana("):
                self.assertNotIn(action, body)
            self.assertIn("[menuActions] in menuActions.perform?", body)

    def test_switching_tabs_reopens_at_latest_page(self):
        # Retour d'usage du 24/11 : un onglet rouvert reprenait la page de son ouverture.
        nav = source("App/Reader/ReaderController+Navigation.swift")
        self.assertIn("model.latestReadingPage[id] = page", nav)
        host = source("App/Reader/DocumentTabsBar.swift")
        self.assertIn("Self.atLatestPage(document, model.latestReadingPage[id])", host)
        app = source("App/AppModel.swift")
        self.assertEqual(app.count("latestReadingPage = [:]"), 2)

    def test_reader_bars_never_use_view_that_fits(self):
        # Point 13 (paquets 119-122 sur l'iPad) : ViewThatFits dans les barres retenait le lecteur fermé.
        screen = source("App/Reader/ReaderScreen.swift")
        code = "\n".join(l for l in screen.splitlines() if not l.strip().startswith("//"))
        self.assertNotIn("ViewThatFits(", code)
        self.assertIn("bottomBar(width: barWidth, aiAndWebInMenu: aiAndWebInMenu, webAllowed: webAllowed)", screen)
        self.assertIn("annotationBar(width: barWidth)", screen)


if __name__ == "__main__":
    unittest.main()
