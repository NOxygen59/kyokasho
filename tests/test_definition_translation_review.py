# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de la revue DeepSeek #3 (C1.2) : un avis 👍/👎 survit à la retraduction.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas le
comportement sur l'iPad. La règle elle-même est testée en Swift (`TranslationFreshnessTests`).
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class DefinitionTranslationReviewTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "App/Dictionary/DefinitionTranslation.swift").read_text(encoding="utf-8")

    def test_retranslation_carries_the_existing_review(self):
        translate = body_of(self.source, "    func translate(_ term: TermResult) async throws",
                            "    func set(_ key: String")
        self.assertIn("let review = entries[key]?.status.keptWhenRetranslated ?? .machine", translate)
        self.assertIn("set(key, Entry(text: text, status: review, source: source))", translate)
        self.assertNotIn("status: .machine", translate, "plus d'écrasement systématique de l'avis")

    def test_the_review_type_lives_in_the_tested_package(self):
        self.assertIn("typealias Status = TranslationReview", self.source)
        package = (ROOT / "Packages/KyokashoKit/Sources/DictionaryKit/Translator.swift").read_text(encoding="utf-8")
        self.assertIn("public enum TranslationReview: String, Codable, Sendable, Equatable", package)
        self.assertIn("public var keptWhenRetranslated: TranslationReview", package)


if __name__ == "__main__":
    unittest.main()
