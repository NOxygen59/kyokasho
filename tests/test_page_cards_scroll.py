# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.5 (5.8) : la feuille « Cartes de la page » ne défilait plus. Le formulaire entier était désactivé
pendant et après l'ajout (`.disabled` sur le `Form`), ce qui bloque aussi son défilement. Seuls les champs des termes
sont désactivés."""

import re
import unittest
from pathlib import Path

VIEW = Path(__file__).resolve().parents[1] / "App/Review/PageCardsView.swift"


class PageCardsScrollTests(unittest.TestCase):
    def test_form_itself_is_never_disabled(self):
        source = VIEW.read_text()
        self.assertNotIn("            .disabled(saving || message != nil)\n            .navigationTitle", source)

    def test_term_fields_are_disabled_during_and_after_adding(self):
        source = VIEW.read_text()
        block = re.search(r"ForEach\(\$entries\).*?\n                \}\n", source, re.S)
        self.assertIsNotNone(block)
        self.assertIn(".disabled(saving || message != nil)", block.group(0))


if __name__ == "__main__":
    unittest.main()
