# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""1.6.4 : surlignage bref (2 s) du mot d'un résultat de recherche ; le rendu se vérifie sur l'iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


def source(path):
    return (APP / path).read_text(encoding="utf-8")


class SearchFlashWiringTests(unittest.TestCase):
    def test_both_kinds_of_results_flash_then_clear(self):
        search = source("Reader/ReaderController+Search.swift")
        show = search.split("func show(_ result: SearchResult) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertTrue(show.lstrip().startswith("clearSearchFlash()"))
        self.assertIn("flashOCRMatch(source: result.sourcePage, query: lastSearchQuery)", show)
        self.assertIn("Task.sleep(nanoseconds: Self.searchFlashDuration)", show)
        self.assertIn("static let searchFlashDuration: UInt64 = 2_000_000_000", search)
        self.assertIn("lastSearchQuery = trimmed", search)

    def test_flash_is_temporary_and_never_saved(self):
        search = source("Reader/ReaderController+Search.swift")
        flash = search.split("private func flashOCRMatch(", 1)[1].split("func clearSearchFlash()", 1)[0]
        self.assertIn('annotation.userName = "flash:recherche"', flash)
        self.assertNotIn("highlights.append", flash)
        self.assertNotIn("saveHighlights", flash)
        self.assertIn("[weak self]", flash)
        clear = search.split("func clearSearchFlash() {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("item.page.removeAnnotation(item.annotation)", clear)
        self.assertIn("searchFlashTask?.cancel()", clear)
        # Fermeture du livre : rien ne survit.
        self.assertIn("savePositionWork?.perform()\n        clearSearchFlash()", source("Reader/ReaderController+OCR.swift"))


if __name__ == "__main__":
    unittest.main()
