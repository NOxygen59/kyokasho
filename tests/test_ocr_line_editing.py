# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage du dialogue UIKit/SwiftUI ; ne remplace pas sa recette sur iPad."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LegacyLineCorrectionTests(unittest.TestCase):
    def test_dialog_captures_the_ocr_and_source_when_it_opens(self):
        panel = (ROOT / "App/Study/StudyPanel.swift").read_text(encoding="utf-8")
        menu = panel[panel.index(".contextMenu {"):panel.index(".sheet(isPresented: $showVerify)")]
        self.assertIn("LineCorrectionDraft(index: index, page: page, source: reader.focusSource)", menu)
        self.assertIn("original: editingLine.page, source: editingLine.source", menu)

    def test_single_line_entry_point_always_uses_the_existing_session_guard(self):
        source = (ROOT / "App/Reader/ReaderController+Verification.swift").read_text(encoding="utf-8")
        start = source.index("    func correctOCRLine(")
        end = source.index("\n    }", start)
        function = source[start:end]
        self.assertIn("original: OCRPage, source: Int", function)
        self.assertIn("correctOCRLines([index: text], ifStill: original, source: source)", function)
        self.assertNotRegex(function, r"correctOCRLines\(\[index: text\]\)")

    def test_rejected_correction_is_visible_to_the_user(self):
        source = (ROOT / "App/Reader/ReaderController+Verification.swift").read_text(encoding="utf-8")
        start = source.index("    func correctOCRLine(")
        end = source.index("\n    }", start)
        self.assertIn("model.lastError = String(localized:", source[start:end])


if __name__ == "__main__":
    unittest.main()
