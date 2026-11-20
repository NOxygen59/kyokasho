# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Gardes de câblage de la recherche et des commandes du fluo (AV-16-01 R4)."""

import pathlib
import re
import unittest

READER = pathlib.Path(__file__).resolve().parents[1] / "App/Reader"


class SearchSheetStyleWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sheets = (READER / "ReaderSheets.swift").read_text(encoding="utf-8")
        cls.search = sheets.split("struct SearchSheet: View {", 1)[1].split("\n// MARK:", 1)[0]
        cls.screen = (READER / "ReaderScreen.swift").read_text(encoding="utf-8")

    def test_search_presents_a_single_atelier_card(self):
        for token in (
            "Atelier.material(.regularMaterial)", "Atelier.radius", ".atelierShapeShadow(",
            "Atelier.scrim", "Atelier.gap", "Atelier.Tint.read", ".atelierFontDesign()",
            ".scrollContentBackground(.hidden)", ".toolbarBackground(.hidden, for: .navigationBar)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, self.search)

    def test_search_keeps_native_input_and_reader_navigation(self):
        self.assertIn("case .search: SearchSheet(reader: reader, close: { self.sheet = nil })", self.screen)
        self.assertIn(".searchable(text: $query", self.search)
        self.assertIn(".onSubmit(of: .search) { reader.search(query) }", self.search)
        self.assertIn('.onChange(of: query) { if $0.isEmpty { reader.search(\"\") } }', self.search)
        self.assertIn("ForEach(reader.searchResults)", self.search)
        self.assertRegex(self.search, r"reader\.show\(result\)\s+close\(\)")
        self.assertIn('Button("OK") { close() }', self.search)

    def test_ocr_commands_but_not_page_preview_are_above_chrome(self):
        mode = self.screen.split("if reader.ocrHighlightMode {", 1)[1].split("\n                    }", 1)[0]
        preview, controls = mode.split("OCRHighlightControls(reader: reader)", 1)
        self.assertIn("OCRHighlightDragLayer", preview)
        self.assertNotIn(".zIndex", preview)
        self.assertRegex(controls, r"\.zIndex\([1-9]\d*\)")
        self.assertIn(".padding(.bottom, chromeVisible ? 110 : 24)", controls)

    def test_selection_palette_is_raised_at_the_toolbar_container_level(self):
        chrome = self.screen.split("private func chrome(", 1)[1].split("FloatingToolbar(", 1)[0]
        self.assertRegex(chrome, re.compile(
            r"^            HStack.*HighlightMenu.*^            }\n"
            r"(?:^            (?:\.[^\n]+|//[^\n]*)\n)*"
            r"^            \.zIndex\(reader\.hasSelection \? [1-9]\d* : 0\)\n"
            r"^            GeometryReader", re.MULTILINE | re.DOTALL,
        ))


if __name__ == "__main__":
    unittest.main()
