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
        self.assertRegex(reader, r"if newLayout \{\s*newChrome\(width: documentWidth, floatingSide: floatingSide\)"
                                 r"\s*\} else if chromeVisible \{")
        self.assertIn("chrome(filmstripTrailing: trailing)", reader)
        # L'ancienne barre d'outils flottante n'existe que dans l'ancien chrome.
        old = reader.split("private func chrome(filmstripTrailing: CGFloat)", 1)[1].split("private func setFilmstrip", 1)[0]
        new = reader.split("private func newChrome(width: CGFloat, floatingSide: Side?)", 1)[1].split("private func newActionsCapsule(compact: Bool)", 1)[0]
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
        self.assertIn(".frame(minHeight: large ? 56 : 48)", components)
        # Boutons icône de la nouvelle présentation (`size: N) {` : appel suivi de son action), pas les polices.
        sizes = [int(n) for n in re.findall(r"size: (\d+)\) \{", source("Reader/ReaderScreen.swift"))]
        self.assertTrue(sizes and min(sizes) >= 48, sizes)


    def test_home_keeps_the_old_layout_when_the_switch_is_off(self):
        home = source("Library/LibraryView.swift")
        self.assertIn("private var newLayout: Bool { NewLayout.isAvailable && newLayoutPreference }", home)
        self.assertIn("if newLayout { newSidebarContent } else { sidebarContent }", home)
        self.assertIn("if newLayout { Atelier.canvas.ignoresSafeArea() } else { libraryBackdrop }", home)
        self.assertRegex(home, r"if newLayout \{\s*newHeader\(width: width\)\s*\} else \{\s*if usesCompactDocuments \{")
        # L'ancienne colonne garde ses tuiles d'import ; la nouvelle les confie au menu « Importer ».
        old = home.split("private var sidebarContent: some View {", 1)[1].split("private func sideRow", 1)[0]
        self.assertIn('"Importer et convertir"', old)
        header = home.split("private func newHeaderActions(compact: Bool)", 1)[1].split("private var spaceMenu", 1)[0]
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
        # Tous les onglets ouverts (fermables d'ici, revue R2 P3), puis les livres en cours de l'espace.
        self.assertIn("let open = tabs.compactMap { id in all.first { $0.id == id } }", logic)
        self.assertIn("doc.isInMangaSpace == manga && !tabs.contains(doc.id)", logic)
        self.assertIn("&& doc.lastPageIndex > 0 && doc.lastPageIndex < doc.pageCount - 1", logic)
        self.assertIn("return open + inProgress.prefix(max(0, limit - open.count))", logic)
        self.assertIn("close: { model.closeTab(document.id) }", row)


    def test_reader_floating_panel_and_bottom_controls_use_separate_rows(self):
        reader = source("Reader/ReaderScreen.swift")
        self.assertIn("let reservesSide = dockingFits &&", reader)
        self.assertIn("let floatingSide = reservesSide ? nil : docked", reader)
        self.assertIn("if !newLayout, docked == .study, !landscape", reader)
        chrome = reader.split("private func newChrome", 1)[1].split("private func newTopBar", 1)[0]
        self.assertNotIn("filmstripTrailing", chrome)
        self.assertLess(chrome.index("ResourceMonitorPanel("), chrome.index("GeometryReader"))
        self.assertLess(chrome.index("sidePanel(floatingSide, floating: true)"), chrome.index("AITaskPill("))
        self.assertLess(chrome.index("PageFilmstrip("), chrome.index("OCRHighlightControls("))
        self.assertLess(chrome.index("OCRHighlightControls("), chrome.index("annotationBar"))

    def test_home_keeps_tabs_available_outside_unfiltered_root(self):
        home = source("Library/LibraryView.swift")
        self.assertRegex(home, r"if currentFolder == nil && filter == \.all && search\.isEmpty \{"
                                 r"\s*ResumeRow\(space: space\)\s*\} else \{"
                                 r"\s*OpenDocumentsStrip\(compact: true,")
        strip = source("Library/OpenDocumentsStrip.swift")
        self.assertIn("model.closeTab(document.id)", strip)

    def test_new_labels_follow_dynamic_type(self):
        components = source("Design/NewLayout.swift").split("struct NewLayoutPillButton", 1)[1]
        self.assertIn("@ScaledMetric", components)
        self.assertIn("(large ? 16 : 15) * typeScale", components)
        self.assertNotIn(".lineLimit(1)", components)
        for path in ("Reader/ReaderScreen.swift", "Library/LibraryView.swift", "Library/ResumeRow.swift"):
            self.assertIn("@ScaledMetric", source(path), path)

    def test_reader_menus_do_not_capture_the_reader(self):
        # Revue R2 Codex (P1) : les actions des menus passent par un relais retiré à la fermeture.
        reader = source("Reader/ReaderScreen.swift")
        menus = reader.split("@ViewBuilder private var displayMenuItems: some View {", 1)[1].split(
            "private func runMenuCommand", 1)[0]
        self.assertNotIn("reader.", menus.replace("reader.isCurrentPageSplit", "").replace("reader.document.firstPageIndex", ""))
        self.assertNotIn("sheet = .", menus)
        self.assertNotIn("Binding(get:", menus)
        self.assertIn("menuActions.detach()", reader)
        relay = reader.split("final class ReaderMenuActions {", 1)[1]
        self.assertIn("func detach() { perform = nil }", relay)

    def test_lookup_button_turns_the_dictionary_on(self):
        # Revue R2 Codex (P1) : couper l'annotation avant d'activer, pas après.
        reader = source("Reader/ReaderScreen.swift")
        button = reader.split("let on = !reader.lookupMode", 1)[1].split("} label:", 1)[0]
        self.assertLess(button.index("if on { stopAnnotating() }"), button.index("reader.lookupMode = on"))


if __name__ == "__main__":
    unittest.main()
