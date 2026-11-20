# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-DATA03-001 E2/E3 : l'export part des pages telles qu'à l'écran, et la hauteur de référence vient de la base."""

import pathlib
import unittest

APP = pathlib.Path(__file__).resolve().parents[1] / "App"


def equalized_document_source():
    reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
    return reader.split("static func equalizedDocument(", 1)[1].split("\n    }", 1)[0]


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
        self.assertIn("let common = stored ?? inherited ?? commonHeight(original)", reader)
        self.assertIn("equalizedDocument(url: url, documentId: documentId, database: database)", reader)
        self.assertIn("PageEqualization.factor(height: height, common: common)", reader)

    def test_inconsistent_pair_is_deleted_before_the_only_preparation(self):
        source = equalized_document_source()
        cache, preparation = source.split("guard let original = PDFDocument(url: url)", 1)
        self.assertIn("equalizationLock.lock()\n        defer { equalizationLock.unlock() }", cache)
        valid_pair = "if let pdf = PDFDocument(url: pdfFile), pdf.pageCount == boxes.count {"
        self.assertIn(valid_pair, cache)
        rejected = cache.split(valid_pair, 1)[1].split("return (pdf, boxes)\n            }", 1)[1]
        self.assertIn('Diagnostics.error("paire d’égalisation incohérente rejetée : \\(documentId.prefix(8))", "lecteur")', rejected)
        self.assertIn("rejectedNames = [pdfFile.lastPathComponent, boxesFile.lastPathComponent]", rejected)
        self.assertIn("fm.removeItem(at: boxesFile)", rejected)
        self.assertIn("fm.removeItem(at: pdfFile)", rejected)
        self.assertNotIn("return", rejected)
        self.assertNotIn("equalizedDocument(", source)
        self.assertIn("!rejectedNames.contains($0.lastPathComponent)", preparation.split("var inherited:", 1)[0])
        self.assertIn('for oldPDF in previous.filter(', preparation)
        self.assertIn("fm.moveItem(at: temporary, to: pdfFile)", preparation)

    def test_empty_marker_returns_before_any_pair_validation(self):
        source = equalized_document_source()
        marker = source.split("if boxes.isEmpty {", 1)[1].split("\n            }", 1)[0]
        self.assertIn("if stored == nil { remember(PDFDocument(url: url).flatMap(commonHeight)) }", marker)
        self.assertIn("return nil", marker)
        for unexpected in ("pdfFile", "Diagnostics.error", "failed()", "removeItem"):
            self.assertNotIn(unexpected, marker)
        self.assertLess(source.index("if boxes.isEmpty {"), source.index("PDFDocument(url: pdfFile)"))

    def test_reader_logs_failed_preparation_but_still_falls_back(self):
        source = equalized_document_source()
        self.assertIn("onPreparationFailure()\n            return nil", source)
        # Revue Claude (PLAN-16-001 E2) : une page non redimensionnable reste telle quelle, comme avant #95.
        self.assertIn("if let factor = PageEqualization.factor(height: height, common: common), let (scaled, doc) = scaledPage(page, factor: factor) {", source)
        self.assertIn("guard (try? fm.moveItem(at: temporary, to: pdfFile)) != nil else { return failed() }", source)
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        build = reader.split("static func build(", 1)[1]
        self.assertIn('    Diagnostics.error("échec de la préparation des pages égalisées : \\(documentId.prefix(8)) ; repli sur le PDF d’origine", "lecteur")\n'
                      '        }\n        guard let pdf = equalized?.pdf ?? PDFDocument(url: url) else { return nil }', build)

    def test_cached_equalized_pages_are_created_after_the_reader_delegate(self):
        # Recette 1.5.10 (3.2, 3.3) : lire les pages du PDF rendu avant `TonedPageProvider` les créait en PDFPage
        # simples (preuve PDFKit sur Mac, REVUES/BUGS-16-2026-11-20/FAIT-CLAUDE-FURIGANA.md) : plus aucun furigana.
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        source = equalized_document_source()
        self.assertNotIn("preparedHeight(pdf, boxes)", source)
        self.assertNotIn("pdf.page(at:", source.split("let values =", 1)[1])
        self.assertIn("if stored == nil { remember(PDFDocument(url: pdfFile).flatMap { preparedHeight($0, boxes) }) }", source)
        self.assertIn("!(pdf.page(at: 0) is TonedPage)", reader)


if __name__ == "__main__":
    unittest.main()
