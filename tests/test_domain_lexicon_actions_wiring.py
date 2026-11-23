# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette 1.6.0 (4.1) : les actions du lexique précèdent les termes."""

import pathlib
import unittest


SOURCE = pathlib.Path(__file__).resolve().parents[1] / "App/Dictionary/DomainLexicon.swift"


class DomainLexiconActionsWiringTests(unittest.TestCase):
    def test_actions_are_in_first_section_before_terms(self):
        source = SOURCE.read_text(encoding="utf-8")
        view = source.split("struct DomainLexiconView: View {", 1)[1].split("\n}", 1)[0]
        rows = view.split("List {", 1)[1].split("\n        }", 1)[0]
        first_section, remaining_sections = rows.split("\n            Section {", 2)[1:]

        self.assertIn("Button { showHarvest = true }", first_section)
        self.assertIn('Button("Remettre les termes de départ manquants") { lexicon.restoreStarter() }', first_section)
        self.assertNotIn("ForEach(shown)", first_section)
        self.assertIn("ForEach(shown)", remaining_sections)
        self.assertIn(".sheet(isPresented: $showHarvest) { LexiconHarvestView() }", view)
