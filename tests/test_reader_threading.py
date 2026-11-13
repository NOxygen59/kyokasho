# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
READER = ROOT / "App/Reader/ReaderController.swift"
# `transform`, `self` et les variables locales nommées `rotation` ne sont pas des `PDFPage`.
PDF_PAGE_SETTER = re.compile(r"\b(?!self\b|transform\b|t\b)(\w+)\.rotation\s*(?:=[^=]|[-+]=)")


class PDFPageRotationThreadTests(unittest.TestCase):
    """UIKit n'est pas chargé ici : ce contrôle lit la source, il ne prouve rien sur l'iPad."""

    def body_of(self, signature, source):
        start = source.index(signature)
        end = source.index("\n    }\n", start)
        return source[start:end]

    def test_every_page_rotation_setter_is_known(self):
        # Crash de la recette 1.3.2 (72) : `PDFPage.rotation` notifie UIKit de façon synchrone.
        # Un nouveau setter doit être ajouté ici après avoir vérifié son fil d'exécution.
        found = []
        for folder in ("App", "Packages/KyokashoKit/Sources", "Packages/GLMOCRKit/Sources"):
            for path in (ROOT / folder).rglob("*.swift"):
                for line in path.read_text(encoding="utf-8").splitlines():
                    if PDF_PAGE_SETTER.search(line) and not line.lstrip().startswith("//"):
                        found.append((path.name, line.strip()))
        self.assertEqual(sorted(found), sorted([
            ("ReaderController.swift", "for (page, degrees) in built.pendingRotations { page.rotation = degrees }"),
            ("ReaderController.swift", "if Thread.isMainThread { scaled.rotation = rotation }"),
            ("ReaderController.swift", "else { DispatchQueue.main.sync { scaled.rotation = rotation } }"),
            # Export (14/11/2026) : rotation de l'app sur une page d'un document d'export (jamais affiché), posée sur le
            # fil principal comme `scaledPage`.
            ("DocumentExport.swift", "if Thread.isMainThread { page.rotation = rotation } else { DispatchQueue.main.sync { page.rotation = rotation } }"),
        ]))

    def test_background_build_never_sets_page_rotation(self):
        body = self.body_of("nonisolated static func build(", READER.read_text(encoding="utf-8"))
        self.assertIsNone(PDF_PAGE_SETTER.search(body))

    def test_background_build_never_sets_page_bounds(self):
        # Crash de la découpe, recette 1.3.2 (74) : `setBounds` notifie UIKit comme `rotation`.
        body = self.body_of("nonisolated static func build(", READER.read_text(encoding="utf-8"))
        self.assertNotIn(".setBounds(", body)

    def test_every_page_bounds_setter_is_known(self):
        found = []
        for path in (ROOT / "App").rglob("*.swift"):
            for line in path.read_text(encoding="utf-8").splitlines():
                if ".setBounds(" in line and not line.lstrip().startswith("//"):
                    found.append(path.name)
        self.assertEqual(sorted(found), sorted(["ReaderController.swift", "ReaderController.swift", "ReaderController+PageLayout.swift"]))

    def test_install_applies_pending_changes_before_showing_the_document(self):
        body = self.body_of("func install(_ built: Built?", READER.read_text(encoding="utf-8"))
        for pending in ("built.pendingRotations", "built.pendingBounds"):
            self.assertLess(body.index(pending), body.index("pdfView.document = pdf"))


if __name__ == "__main__":
    unittest.main()
