# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.5 (10.3) : le chat du livre ouvert depuis l'accueil, fermé d'un toucher à côté, empêchait
ensuite d'ouvrir le livre. La feuille ne se ferme plus que par « Fermer »."""

import re
import unittest
from pathlib import Path

LIBRARY = Path(__file__).resolve().parents[1] / "App/Library/LibraryView.swift"


class BookChatSheetDismissTests(unittest.TestCase):
    def test_book_chat_sheet_only_closes_with_its_button(self):
        source = LIBRARY.read_text()
        block = re.search(r"\.sheet\(item: \$chatDocument\).*?\n        \}", source, re.S)
        self.assertIsNotNone(block, "feuille du chat introuvable")
        self.assertIn(".interactiveDismissDisabled()", block.group(0))


if __name__ == "__main__":
    unittest.main()
