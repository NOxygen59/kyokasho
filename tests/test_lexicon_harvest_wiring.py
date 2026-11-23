# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import unittest
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "App/Dictionary/LexiconHarvestView.swift"


class LexiconHarvestWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_picker_lists_only_documents_with_text_analysis(self):
        self.assertRegex(
            self.source,
            r"var eligibleDocuments: \[LibraryDocument\]\s*\{\s*"
            r"model\.documents\.filter\s*\{\s*\$0\.capabilities\.textAnalysis\s*\}",
        )
        self.assertRegex(
            self.source,
            r'Picker\("Livre",\s*selection:\s*documentSelection\)\s*\{\s*'
            r'Text\("Choisir…"\)\.tag\(String\?\.none\)\s*ForEach\(eligibleDocuments\)',
        )

    def test_selection_and_harvest_use_an_eligible_document(self):
        self.assertRegex(
            self.source,
            r"var selectedDocument: LibraryDocument\?\s*\{\s*"
            r"eligibleDocuments\.first\s*\{\s*\$0\.id\s*==\s*documentId\s*\}",
        )
        self.assertRegex(
            self.source,
            r"var documentSelection: Binding<String\?>\s*\{\s*(?://[^\n]*\n\s*)?"
            r"Binding\(get: \{ selectedDocument\?\.id \}",
        )
        self.assertIn(".disabled(selectedDocument == nil ||", self.source)
        self.assertRegex(
            self.source,
            r"private func harvest\(\)\s*\{\s*guard let document = selectedDocument else \{ return \}",
        )

    def test_manga_space_does_not_exclude_pdfs(self):
        self.assertNotRegex(self.source, r"\b(?:isInMangaSpace|mangaSpace)\b")
