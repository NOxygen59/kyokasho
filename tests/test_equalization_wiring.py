# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-DATA03-001 E2/E3 : l'export part des pages telles qu'à l'écran, et la hauteur de référence vient de la base."""

import pathlib
import unittest

APP = pathlib.Path(__file__).resolve().parents[1] / "App"


class EqualizationWiringTests(unittest.TestCase):
    def test_annotated_export_and_images_use_the_displayed_pages(self):
        export = (APP / "Library/DocumentExport.swift").read_text(encoding="utf-8")
        self.assertEqual(export.count("guard let doc = displayedPDF(source: source, documentId: documentId, database: database)"), 2)
        self.assertNotIn("guard let doc = PDFDocument(url: source)", export)

    def test_reader_and_export_share_the_stored_reference(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        self.assertIn("guard let common = stored ?? inherited ?? commonHeight(original) else { return nil }", reader)
        self.assertIn("equalizedDocument(url: url, documentId: documentId, database: database)", reader)
        self.assertIn("PageEqualization.factor(height: height, common: common)", reader)


if __name__ == "__main__":
    unittest.main()
