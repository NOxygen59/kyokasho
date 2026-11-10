# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class DeletionConcurrencyGuardsTests(unittest.TestCase):
    """Ce contrôle lit la source des fichiers de l'app (non compilée ici) : il ne prouve rien sur l'iPad."""

    def test_ai_task_center_cancels_by_document(self):
        # C2.6 (audit du 09/11/2026) : les tâches IA d'un document supprimé doivent pouvoir être
        # arrêtées par document, avec le même prédicat de clé que PageShift.blocksAI.
        source = (ROOT / "App/Reader/AITaskCenter.swift").read_text(encoding="utf-8")
        self.assertIn("func cancel(documentId: String)", source)
        body = body_of(source, "func cancel(documentId: String)", "func cancel(prefix: String)")
        self.assertIn("split(separator: \"|\")", body, "même prédicat que blocksAI")

    def test_document_deletion_cancels_ai_tasks_first(self):
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument)", "func closeTab(")
        cancel = body.index("AITaskCenter.shared.cancel(documentId:")
        self.assertLess(cancel, body.index("ioQueue.async"), "annulées avant le déclenchement de la suppression")
        self.assertLess(cancel, body.index("closeTab(document.id)"))

    def test_document_deletion_never_closes_ticket_with_ai_task_running(self):
        # L'annulation doit précéder le retrait du document de la bibliothèque.
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument)", "func closeTab(")
        cancel = body.index("AITaskCenter.shared.cancel(documentId:")
        self.assertLess(cancel, body.index("documents.removeAll"))


if __name__ == "__main__":
    unittest.main()
