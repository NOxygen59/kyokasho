# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-DATA03-001 E2/E3 : l'export part des pages telles qu'à l'écran, et la hauteur de référence vient de la base."""

import pathlib
import unittest

APP = pathlib.Path(__file__).resolve().parents[1] / "App"


class EqualizationWiringTests(unittest.TestCase):
    def test_annotated_export_and_images_use_the_displayed_pages(self):
        export = (APP / "Library/DocumentExport.swift").read_text(encoding="utf-8")
        self.assertEqual(export.count("guard let doc = try displayedPDF(source: source, documentId: documentId, database: database)"), 2)
        # Revue R2 DATA-03 (n°4) : pas de repli silencieux sur le PDF d'origine quand une page devait être égalisée.
        self.assertIn("throw ExportPreparationFailed()", export)
        self.assertNotIn("guard let doc = PDFDocument(url: source)", export)

    def test_export_applies_the_rotation_chosen_in_the_app(self):
        # Essais Kimi/Hy4 du 14/11/2026 : la rotation choisie dans l'app manquait à l'export.
        export = (APP / "Library/DocumentExport.swift").read_text(encoding="utf-8")
        self.assertEqual(export.count("applyAppRotation(page, extra: rotations[index])"), 2)
        self.assertIn("PageTransform.effectiveRotation(intrinsic: page.rotation, additional: extra)", export)
        self.assertIn("pageTransforms(documentId: doc.id)", export)

    def test_reader_and_export_share_the_stored_reference(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        self.assertIn("guard let common = stored ?? inherited ?? commonHeight(original) else { return nil }", reader)
        self.assertIn("equalizedDocument(url: url, documentId: documentId, database: database)", reader)
        self.assertIn("PageEqualization.factor(height: height, common: common)", reader)

    def test_cached_equalized_pages_are_created_after_the_reader_delegate(self):
        # Recette 1.5.10 (3.2, 3.3) : lire les pages du PDF rendu avant `TonedPageProvider` les créait en PDFPage
        # simples (preuve PDFKit sur Mac, REVUES/BUGS-16-2026-11-20/FAIT-CLAUDE-FURIGANA.md) : plus aucun furigana.
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        self.assertNotIn("remember(preparedHeight(pdf, boxes))", reader)
        self.assertIn("if stored == nil { remember(PDFDocument(url: pdfFile).flatMap { preparedHeight($0, boxes) }) }", reader)
        self.assertIn("!(pdf.page(at: 0) is TonedPage)", reader)


if __name__ == "__main__":
    unittest.main()
