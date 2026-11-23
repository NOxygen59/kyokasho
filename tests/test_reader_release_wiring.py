# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""1.6.3 : le lecteur fermé doit être libéré (gel CPU de la 1.6.1-1.6.2). Garde du câblage ; la libération réelle se
vérifie sur l'iPad (ligne « lecteur libéré » du journal de diagnostic)."""

import re
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


def source(path):
    return (APP / path).read_text(encoding="utf-8")


class ReaderReleaseWiringTests(unittest.TestCase):
    def test_close_keeps_the_pdf_view_document(self):
        ocr = source("Reader/ReaderController+OCR.swift")
        close = ocr.split("private func closeWork() {", 1)[1].split("\n    }\n", 1)[0]
        self.assertNotIn("pdfView.document = nil", close, "vider la vue PDF fait boucler PDFKit")
        self.assertIn("pdf = nil", close)

    def test_engine_menu_actions_do_not_capture_the_view(self):
        panel = source("Study/StudyPanel.swift")
        self.assertIn("final class StudyMenuActions", panel)
        self.assertIn("weak var reader: ReaderController?", panel)
        self.assertIn(".onDisappear { menuActions.detach() }", panel)
        menu = panel.split("private var engineMenu: some View {", 1)[1].split("} label: {\n            // Icône", 1)[0]
        body = menu.split("return Menu {", 1)[1]
        self.assertNotRegex(body, r"(?<!actions\.)\breader\.(runOCR|verifyShownPages|keepPinnedEngineForDocument)\(")
        self.assertNotRegex(body, r"\{ aiLayout = |showVerify = true|showCompare = true|Button\(action: openDocumentSettings\)")

    def test_display_picker_and_settings_action_use_bindings_only(self):
        panel = source("Study/StudyPanel.swift")
        self.assertIn("let ai = $aiLayout, fm = $formatted", panel)
        screen = source("Reader/ReaderScreen.swift")
        self.assertEqual(screen.count("openDocumentSettings: { [sheet = $sheet] in sheet.wrappedValue = .settings }"), 2)
        self.assertNotIn("openDocumentSettings: { sheet = .settings }", screen)

    def test_new_text_header_menu_builds_its_content_outside_the_closure(self):
        # Recette 1.6.4 (13) : `Menu { engineMenu … $furigana }` capturait la vue, le lecteur n'était jamais libéré.
        panel = source("Study/StudyPanel.swift")
        header = panel.split("private var newTextHeader: some View {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("let engine = engineMenu, layout = layoutMenu, furiganaBinding = $furigana", header)
        body = header.split("                Menu {\n", 1)[1].split("} label:", 1)[0]
        self.assertNotRegex(body, r"engineMenu|layoutMenu|\$|\breader\b|self")
        layout = panel.split("private var layoutMenu: some View {", 1)[1].split("} label: {", 1)[0]
        self.assertIn("let engineBinding = $layoutEngineRaw", layout)
        self.assertNotIn("selection: $layoutEngineRaw", layout.split("Menu {", 1)[1])

    def test_reader_release_is_logged(self):
        self.assertRegex(source("Reader/ReaderController.swift"), r'deinit \{[^\n]*Diagnostics\.log\("lecteur libéré"')


if __name__ == "__main__":
    unittest.main()
