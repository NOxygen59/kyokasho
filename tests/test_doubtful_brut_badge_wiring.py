# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""AV-16-01 R5 : le sélecteur signale les doutes, seul Brut affiche le détail."""

import json
import pathlib
import unittest

APP = pathlib.Path(__file__).resolve().parents[1] / "App"


class DoubtfulBrutBadgeWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.panel = (APP / "Study/StudyPanel.swift").read_text(encoding="utf-8")

    def test_detail_is_gated_to_raw_with_or_without_furigana(self):
        self.assertEqual(self.panel.count("doubtRow(page)"), 1)
        display = self.panel.split("case (let page?, _):", 1)[1].split("translationBlock(for: page.text)", 1)[0]
        self.assertIn("if !aiLayout && !formatted { doubtRow(page) }", display)
        ai_view = (APP / "Study/AILayoutView.swift").read_text(encoding="utf-8")
        self.assertNotIn("doubtRow", ai_view)
        self.assertNotIn("doubt:", ai_view)
        self.assertIn("Text(Self.marked(line))", self.panel)
        furigana = (APP / "Study/FuriganaText.swift").read_text(encoding="utf-8")
        self.assertIn("let doubt = formatted ? [] : Set(page.lines[u].doubt ?? [])", furigana)
        # Le HTML de Brut ne doit pas rester affiché pendant la reconstruction du mode formaté.
        self.assertRegex(display, r"FuriganaTextView\([^\n]+\n\s+\.id\(formatted\)")

    def test_only_raw_is_badged_from_current_character_marks(self):
        picker = self.panel.split("private var displayPicker: some View {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("reader.ocrPage?.lines.contains { $0.doubt?.isEmpty == false } == true", picker)
        self.assertRegex(picker, r'Text\("Brut"\)\s+\.tag\(1\)\s+\.accessibilityLabel\(hasDoubtfulCharacters')
        self.assertIn('Text("Brut : caractères douteux") : Text("Brut")', picker)
        self.assertRegex(picker, r'(?s)\.overlay\s*\{\s*if hasDoubtfulCharacters \{.*Circle\(\).*\.fill\(\.orange\)')
        self.assertIn(".allowsHitTesting(false)", picker)
        self.assertIn(".accessibilityHidden(true)", picker)

    def test_badge_accessibility_label_is_localized(self):
        catalog = json.loads((APP / "Resources/Localizable.xcstrings").read_text(encoding="utf-8"))
        label = catalog["strings"]["Brut : caractères douteux"]["localizations"]
        for language in ("en", "zh-Hans"):
            with self.subTest(language=language):
                self.assertTrue(label[language]["stringUnit"]["value"])
