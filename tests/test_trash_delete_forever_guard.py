# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de BUG-003 (audit Fable du 10/11/2026).

« Supprimer définitivement » retirait le document de la corbeille avant de savoir si l'effacement pouvait
commencer. Pendant une sauvegarde, `delete` refusait : le document n'était plus à la corbeille et revenait dans
la bibliothèque. Le retrait de la corbeille doit suivre un effacement réellement lancé.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas le comportement
sur l'iPad.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class DeleteForeverGuardTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")

    def test_document_leaves_the_trash_only_after_deletion_started(self):
        body = body_of(self.source, "    func deleteForever(_ document: LibraryDocument) {", "    func emptyTrash()")
        self.assertIn("guard delete(document) else { return }", body)
        self.assertLess(body.index("guard delete(document) else { return }"), body.index("trash.remove(document.id)"),
                        "la corbeille n'est modifiée qu'après un effacement lancé")

    def test_delete_reports_a_refusal(self):
        body = body_of(self.source, "    func delete(_ document: LibraryDocument) -> Bool {", "    func closeTab(")
        refused = body[:body.index("let importer = importer")]
        self.assertEqual(refused.count("return false"), 2, "sauvegarde en cours et copies à réparer : deux refus")
        self.assertTrue(body.rstrip().endswith("return true\n    }".rstrip()) or "        return true\n    }" in body)


if __name__ == "__main__":
    unittest.main()
