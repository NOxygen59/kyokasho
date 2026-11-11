# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de la revue DeepSeek #11 (C1.5) : cartes d'export disparues, message en français.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage et la
présence de la phrase dans les trois langues, pas l'affichage réel sur l'iPad.
"""

from pathlib import Path
import json
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class ExportCardsErrorTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "App/Library/DocumentExport.swift").read_text(encoding="utf-8")

    def test_cards_export_throws_an_explained_error(self):
        # Seul le chemin des cartes change : les autres `CocoaError(.fileWriteUnknown)` du fichier sont de vrais
        # échecs d'écriture, dont le message système est justifié.
        cards = body_of(self.source, "                case .cards:", "                case .annotated:")
        self.assertNotIn("CocoaError(.fileWriteUnknown)", cards)
        self.assertIn("guard let cards else { throw DocumentExport.CardsUnavailable() }", cards)
        self.assertIn("struct CardsUnavailable: LocalizedError", self.source)
        self.assertIn('String(localized: "Cartes indisponibles : rouvre l\'écran d\'export.")', self.source)

    def test_the_explanation_replaces_the_generic_prefix(self):
        self.assertIn("case .failure(let e as DocumentExport.CardsUnavailable): error = e.localizedDescription",
                      self.source)

    def test_the_french_sentence_exists_in_the_three_languages(self):
        catalog = json.loads((ROOT / "App/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))
        entry = catalog["strings"]["Cartes indisponibles : rouvre l'écran d'export."]
        self.assertEqual(sorted(entry["localizations"]), ["en", "fr", "zh-Hans"])
        self.assertEqual(entry["localizations"]["fr"]["stringUnit"]["value"],
                         "Cartes indisponibles : rouvre l'écran d'export.")


if __name__ == "__main__":
    unittest.main()
