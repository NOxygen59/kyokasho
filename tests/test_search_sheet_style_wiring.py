# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Gardes de câblage de la carte de recherche (AV-16-02 G4) et des commandes du fluo."""

import json
import pathlib
import re
import unittest

READER = pathlib.Path(__file__).resolve().parents[1] / "App/Reader"


class SearchSheetStyleWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.screen = (READER / "ReaderScreen.swift").read_text(encoding="utf-8")

    def test_search_is_a_nonmodal_overlay_under_the_toolbar(self):
        self.assertNotIn("case search,", self.screen)
        self.assertNotIn("case .search:", self.screen)
        self.assertNotIn("sheet = .search", self.screen)
        self.assertIn(".overlayPreferenceValue(SearchBarBounds.self)", self.screen)
        self.assertIn(".anchorPreference(key: SearchBarBounds.self, value: .bounds)", self.screen)
        self.assertEqual(self.screen.count("searchCardShown = true"), 3)

    def test_search_presents_a_single_atelier_card(self):
        search = (READER / "SearchCard.swift").read_text(encoding="utf-8")
        for token in (
            "Atelier.material(.regularMaterial)", "Atelier.radius", ".atelierShapeShadow(",
            "Atelier.Tint.read", ".topTrailing", "ViewThatFits(in: .vertical)",
            "reduceMotion ? nil", ".opacity.combined(with: .offset(y:",
        ):
            with self.subTest(token=token):
                self.assertIn(token, search)
        for token in ("Atelier.scrim", "NavigationStack", ".ignoresSafeArea", ".sheet("):
            self.assertNotIn(token, search)

    def test_search_cancels_on_clear_and_navigates_without_closing(self):
        search = (READER / "SearchCard.swift").read_text(encoding="utf-8")
        self.assertIn(".onSubmit(submit)", search)
        self.assertIn("reader.search(term)", search)
        self.assertIn('reader.search("")', search)
        self.assertIn("ForEach(reader.searchResults)", search)
        self.assertRegex(search, r"reader\.show\(result\)\s+} label:")
        self.assertIn(".range(of: submittedTerm", search)
        self.assertIn('Button("Fermer") { close() }', search)
        self.assertIn(".keyboardShortcut(.escape, modifiers: [])", search)
        self.assertNotRegex(search, r"(?m)^\s*reader\.close\(\)")

    def test_result_count_is_localized(self):
        catalog = READER.parent / "Resources/Localizable.xcstrings"
        strings = json.loads(catalog.read_text(encoding="utf-8"))["strings"]
        key = "Résultats : %lld"
        self.assertIn(key, strings)
        for language in ("en", "zh-Hans"):
            self.assertEqual(strings[key]["localizations"][language]["stringUnit"]["state"], "translated")

    def test_ocr_commands_but_not_page_preview_are_above_chrome(self):
        mode = self.screen.split("if reader.ocrHighlightMode {", 1)[1].split("\n                    }", 1)[0]
        preview, controls = mode.split("OCRHighlightControls(reader: reader,", 1)
        self.assertIn("OCRHighlightDragLayer", preview)
        self.assertNotIn(".zIndex", preview)
        self.assertRegex(controls, r"\.zIndex\([1-9]\d*\)")
        self.assertIn(".padding(.bottom, chromeVisible ? 110 : 24)", controls)
        self.assertIn("handlesEscape: !searchCardShown", mode)
        self.assertIn(".keyboardShortcut(handlesEscape ? KeyboardShortcut(.escape, modifiers: []) : nil)", self.screen)

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
