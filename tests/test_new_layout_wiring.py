# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-REFONTE-001 : garde du câblage de la nouvelle présentation ; le rendu se vérifie sur l'iPad."""

import re
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


def source(path):
    return (APP / path).read_text(encoding="utf-8")


class NewLayoutWiringTests(unittest.TestCase):
    def test_switch_is_off_by_default_and_never_writes_saved_appearance(self):
        themes = source("Design/Themes.swift")
        block = themes.split("enum NewLayout {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('static let storageKey = "appearance.readerRefresh"', block)
        self.assertIn("static let defaultEnabled = false", block)
        self.assertIn("PersonalPadLibrary.isAvailable", block)
        # La présentation lit le thème ; elle ne touche jamais aux réglages enregistrés.
        for path in ("Design/NewLayout.swift", "Reader/ReaderScreen.swift"):
            text = source(path)
            for key in ('"theme.id"', '"style.id"', "paletteKey"):
                self.assertNotIn(key, text, f"{path} ne doit pas écrire {key}")

    def test_paper_theme_is_new_and_washi_is_unchanged(self):
        themes = source("Design/Themes.swift")
        self.assertIn('id: "papier"', themes)
        self.assertRegex(themes, r"static let all: \[Theme\] = \[[^\]]*\.papier")
        washi = themes.split("static let washi = Theme(", 1)[1].split(")\n", 1)[0]
        self.assertNotIn("isLight: true", washi)

    def test_reader_keeps_the_old_chrome_when_the_switch_is_off(self):
        reader = source("Reader/ReaderScreen.swift")
        self.assertIn("private var newLayout: Bool { NewLayout.isAvailable && newLayoutPreference }", reader)
        self.assertRegex(reader, r"if newLayout \{ newChrome\(filmstripTrailing: trailing\) \} "
                                 r"else \{ chrome\(filmstripTrailing: trailing\) \}")
        # L'ancienne barre d'outils flottante n'existe que dans l'ancien chrome.
        old = reader.split("private func chrome(filmstripTrailing: CGFloat)", 1)[1].split("private func setFilmstrip", 1)[0]
        new = reader.split("private func newChrome(filmstripTrailing: CGFloat)", 1)[1].split("private var newActionsCapsule", 1)[0]
        self.assertIn("FloatingToolbar(", old)
        self.assertNotIn("FloatingToolbar(", new)

    def test_menus_are_shared_not_duplicated(self):
        reader = source("Reader/ReaderScreen.swift")
        # Chaque commande des menus n'est écrite qu'une fois, et les deux présentations l'utilisent.
        for label in ('"Fond de page"', '"Pagination et réglages de ce document"', '"Créer des cartes de cette page"'):
            self.assertEqual(reader.count(label), 1, label)
        self.assertGreaterEqual(reader.count("displayMenuItems"), 3)
        self.assertGreaterEqual(reader.count("moreMenuItems"), 3)

    def test_annotation_tools_are_exclusive(self):
        reader = source("Reader/ReaderScreen.swift")
        select = reader.split("private func selectAnnotationTool(_ tool: AnnotationTool) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("if tool != .pencilLookup, reader.pencilLookup { reader.pencilLookup = false }", select)
        self.assertIn("if tool != .highlight, reader.ocrHighlightMode { reader.setOCRHighlightMode(false) }", select)
        self.assertIn("if tool != .draw, reader.isDrawing { reader.setDrawing(false) }", select)

    def test_bottom_bar_targets_are_large_enough(self):
        components = source("Design/NewLayout.swift")
        self.assertIn(".frame(height: large ? 56 : 48)", components)
        # Boutons icône de la nouvelle présentation (`size: N) {` : appel suivi de son action), pas les polices.
        sizes = [int(n) for n in re.findall(r"size: (\d+)\) \{", source("Reader/ReaderScreen.swift"))]
        self.assertTrue(sizes and min(sizes) >= 48, sizes)


    def test_home_keeps_the_old_layout_when_the_switch_is_off(self):
        home = source("Library/LibraryView.swift")
        self.assertIn("private var newLayout: Bool { NewLayout.isAvailable && newLayoutPreference }", home)
        self.assertIn("if newLayout { newSidebarContent } else { sidebarContent }", home)
        self.assertIn("if newLayout { Atelier.canvas.ignoresSafeArea() } else { libraryBackdrop }", home)
        self.assertRegex(home, r"if newLayout \{\s*newHeader\s*\} else \{\s*if usesCompactDocuments \{")
        # L'ancienne colonne garde ses tuiles d'import ; la nouvelle les confie au menu « Importer ».
        old = home.split("private var sidebarContent: some View {", 1)[1].split("private func sideRow", 1)[0]
        self.assertIn('"Importer et convertir"', old)
        header = home.split("private var newHeader: some View {", 1)[1].split("private func spaceTab", 1)[0]
        for action in ("showImportOptions = true", "showDrive = true", "showMerge = true", "showImagesToPDF = true"):
            self.assertIn(action, header)

    def test_home_sidebar_keeps_every_command(self):
        home = source("Library/LibraryView.swift")
        new = home.split("private var newSidebarContent: some View {", 1)[1].split("private var sidebarContent", 1)[0]
        for part in ("brandHeader", "libraryRows", "studyRows", "LocalAIEnergyCard()", "showBench = true",
                     "showTrash = true", "showSettings = true", "showFolder(tile.folder.id)"):
            self.assertIn(part, new)

    def test_resume_row_lists_open_tabs_first_then_books_in_progress(self):
        row = source("Library/ResumeRow.swift")
        logic = row.split("static func documents(", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("let inSpace = all.filter { $0.isInMangaSpace == manga }", logic)
        self.assertIn("let open = tabs.compactMap { id in inSpace.first { $0.id == id } }", logic)
        self.assertIn("!tabs.contains(doc.id) && doc.lastPageIndex > 0 && doc.lastPageIndex < doc.pageCount - 1", logic)
        self.assertIn("return Array((open + inProgress).prefix(limit))", logic)
        self.assertIn("close: { model.closeTab(document.id) }", row)


if __name__ == "__main__":
    unittest.main()
