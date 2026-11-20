# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""#93 : garde du câblage SwiftUI ; le comportement visuel se vérifie sur iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


def source(path):
    return (APP / path).read_text(encoding="utf-8")


class ReaderOverlayWiringTests(unittest.TestCase):
    def test_reader_is_an_opaque_overlay_for_an_available_document(self):
        root = source("KyokashoApp.swift")
        self.assertNotIn(".fullScreenCover(", root)
        visibility = root.split("private var showsReader: Bool {", 1)[1].split("var body:", 1)[0]
        self.assertIn("guard model.storageRecoveryError == nil, let id = model.openDocumentId", visibility)
        self.assertIn("return model.documents.contains { $0.id == id }", visibility)
        self.assertRegex(root, r"\.overlay\s*\{\s*ZStack\s*\{\s*(?://[^\n]*\n\s*)*if showsReader\s*\{\s*ReaderTabsHost\(\)")
        self.assertIn(".background(Atelier.canvas.ignoresSafeArea())", root)

    def test_library_is_isolated_and_intro_waits_without_unmounting_navigation(self):
        root = source("KyokashoApp.swift")
        self.assertRegex(root, r"NavigationStack\s*\{\s*LibraryView\(\)")
        before_reader = root.split("if showsReader {", 1)[0]
        self.assertIn(".allowsHitTesting(!showsReader)", before_reader)
        self.assertIn(".accessibilityHidden(showsReader)", before_reader)
        self.assertRegex(before_reader, r"if !showsReader\s*\{[^{}]*\.modifier\(IntroPresenter\(")

    def test_library_button_closes_explicitly_and_reader_still_cleans_up(self):
        reader = source("Reader/ReaderScreen.swift")
        self.assertRegex(reader, r'CapsuleButton\([^\n]*"Bibliothèque"[^\n]*\)\s*\{\s*model\.openDocumentId = nil\s*\}')
        self.assertRegex(reader, r"\.onDisappear\s*\{\s*reader\.close\(\)")
        self.assertIn(".id(document.id)", source("Reader/DocumentTabsBar.swift"))

    def test_opening_keeps_the_request_serial_and_diagnostics_but_no_retries(self):
        model = source("AppModel.swift")
        self.assertRegex(model, r"if let openDocumentId\s*\{\s*tabs\.open\(openDocumentId\)\s*openRequestSerial \+= 1")
        self.assertIn('Diagnostics.log("ouverture demandée :', model)
        self.assertRegex(source("Reader/DocumentTabsBar.swift"), r'\.onAppear\s*\{\s*Diagnostics\.log\("lecteur affiché"')
        for obsolete in ("readerPresented", "ReaderOpenGuard", "presentReaderAgain", "checkReaderLater", "readerCoverDismissed"):
            self.assertNotIn(obsolete, model)


if __name__ == "__main__":
    unittest.main()
