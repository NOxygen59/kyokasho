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
        self.assertRegex(root, r"\.overlay\s*\{\s*ZStack\s*\{[^{}]*Color\.clear\s*\.allowsHitTesting\(false\)"
                               r"[^{}]*if showsReader\s*\{\s*ReaderTabsHost\(\)")
        self.assertIn(".background(Atelier.canvas.ignoresSafeArea())", root)

    def test_reader_fades_in_after_its_pdf_is_installed_unless_reduce_motion_is_enabled(self):
        # Recette 1.6.1 (1.2, 1.3) : fondu lancé quand le PDF est posé, retrait immédiat, rien si « Réduire les animations ».
        root = source("KyokashoApp.swift")
        self.assertIn(r"@Environment(\.accessibilityReduceMotion) private var reduceMotion", root)
        layer = root.split("if showsReader {", 1)[1].split(".onAppear", 1)[0]
        self.assertIn(".modifier(ReaderReveal(reduceMotion: reduceMotion))", layer)
        self.assertRegex(layer, r"\.modifier\(ReaderReveal\(reduceMotion: reduceMotion\)\)\s*(?://[^\n]*\n\s*)*"
                                r"\.transition\(\.identity\)")
        self.assertNotIn(".animation(", layer)
        self.assertNotIn("withAnimation", layer)
        tabs = source("Reader/DocumentTabsBar.swift")
        self.assertRegex(tabs, r"ReaderScreen\(document: document, model: model\)\.id\(document\.id\)\s*"
                               r"\.transition\(\.identity\)")
        reveal = tabs.split("struct ReaderReveal: ViewModifier {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("@State private var shown = false", reveal)
        self.assertIn(".opacity(shown || reduceMotion ? 1 : 0)", reveal)
        self.assertIn(".onReceive(NotificationCenter.default.publisher(for: .readerContentReady))", reveal)
        self.assertIn("try? await Task.sleep(nanoseconds: 500_000_000)", reveal)
        self.assertRegex(reveal, r"if reduceMotion \{\s*shown = true\s*\} else \{\s*"
                                 r"withAnimation\(\.easeOut\(duration: 0\.2\)\) \{ shown = true \}")
        # Le signal part une fois le PDF posé, et aussi en cas d'échec (le message d'erreur doit se voir).
        controller = source("Reader/ReaderController.swift")
        install = controller.split("func install(_ built: Built?", 1)[1].split("func markOpened()", 1)[0]
        self.assertEqual(install.count("NotificationCenter.default.post(name: .readerContentReady"), 2)
        self.assertLess(install.index("pdfView.document = pdf"), install.rindex(".readerContentReady"))

    def test_diagnostic_banner_is_anchored_outside_the_reader_and_library(self):
        root = source("KyokashoApp.swift")
        self.assertEqual(root.count("DiagnosticSizeBanner()"), 1)
        self.assertNotIn("DiagnosticSizeBanner()", source("Reader/DocumentTabsBar.swift"))
        self.assertRegex(root, r"\.zIndex\(1\)\s*\}\s*\}\s*\}\s*(?://[^\n]*\n\s*)*"
                               r"\.safeAreaInset\(edge: \.top, spacing: 0\)\s*\{\s*"
                               r"if model\.storageRecoveryError == nil \{\s*DiagnosticSizeBanner\(\)")

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
