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
        self.assertIn("guard started else { return }", body)
        self.assertLess(body.index("guard started else { return }"), body.index("trashedDocuments.removeAll"),
                        "la liste de la corbeille n'est modifiée qu'après un effacement lancé")

    def test_trash_mark_is_removed_only_after_a_successful_deletion(self):
        # Revue DeepSeek D-07 (C1) : un effacement lancé puis échoué gardait le document hors de la corbeille.
        body = body_of(self.source, "    func deleteForever(_ document: LibraryDocument) {", "    func emptyTrash()")
        success = body[body.index("if succeeded {"):body.index("} else if")]
        self.assertIn("self.trash.remove(document.id)", success)
        self.assertEqual(body.count("trash.remove(document.id)"), 1, "jamais retirée hors du cas réussi")
        failure = body[body.index("} else if"):]
        self.assertIn("self.trashedDocuments.insert(document, at: 0)", failure)

    def test_delete_reports_its_outcome_once_on_each_branch(self):
        body = body_of(self.source, "    func delete(_ document: LibraryDocument, finished: ((Bool) -> Void)? = nil) -> Bool {",
                       "    func closeTab(")
        failure = body[body.index("} catch {"):]
        success = body[:body.index("} catch {")]
        self.assertEqual(success.count("finished?(true)"), 1)
        self.assertEqual(failure.count("finished?(false)"), 1)
        self.assertNotIn("finished?(", body[:body.index("let importer = importer")], "pas d'appel sur un refus")

    def test_delete_reports_a_refusal(self):
        body = body_of(self.source, "    func delete(_ document: LibraryDocument, finished: ((Bool) -> Void)? = nil) -> Bool {", "    func closeTab(")
        refused = body[:body.index("let importer = importer")]
        self.assertEqual(refused.count("return false"), 2, "sauvegarde en cours et copies à réparer : deux refus")
        self.assertTrue(body.rstrip().endswith("return true\n    }".rstrip()) or "        return true\n    }" in body)

    def test_failed_deletion_does_not_bring_trashed_documents_back(self):
        # BUG-007 : la liste relue après un effacement en échec garde le filtre de la corbeille.
        body = body_of(self.source, "    func delete(_ document: LibraryDocument, finished: ((Bool) -> Void)? = nil) -> Bool {", "    func closeTab(")
        failure = body[body.index("} catch {"):]
        self.assertIn("!self.trash.contains($0.id) && !self.deletingIds.contains($0.id)", failure)
        self.assertNotIn("self.documents = (try? self.database.allDocuments()) ?? self.documents\n", failure)


if __name__ == "__main__":
    unittest.main()
