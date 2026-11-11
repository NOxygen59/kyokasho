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
        body = body_of(source, "func delete(_ document: LibraryDocument", "func closeTab(")
        cancel = body.index("AITaskCenter.shared.cancel(documentId:")
        self.assertLess(cancel, body.index("ioQueue.async"), "annulées avant le déclenchement de la suppression")
        self.assertLess(cancel, body.index("closeTab(document.id)"))

    def test_document_deletion_never_closes_ticket_with_ai_task_running(self):
        # L'annulation doit précéder le retrait du document de la bibliothèque.
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument", "func closeTab(")
        cancel = body.index("AITaskCenter.shared.cancel(documentId:")
        self.assertLess(cancel, body.index("documents.removeAll"))

    def test_ai_tasks_refused_while_document_is_being_deleted(self):
        # P3 n°6 (revue R2) : une nouvelle tâche IA pour un document en cours d'effacement est refusée.
        # L'état vit dans AITaskCenter (couplage mince), posé et retiré par AppModel.delete.
        center = (ROOT / "App/Reader/AITaskCenter.swift").read_text(encoding="utf-8")
        self.assertIn("deletingDocumentIds", center)
        self.assertIn("func beginDeletion(documentId: String)", center)
        self.assertIn("func endDeletion(documentId: String)", center)
        run = body_of(center, "func run(_ key: String", "func setProgress(")
        self.assertIn("deletingDocumentIds", run, "la garde est dans run")
        # même prédicat de clé que cancel(documentId:) et PageShift.blocksAI
        self.assertLess(run.index("deletingDocumentIds"), run.index("let job = Job("))
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument", "func closeTab(")
        begin = body.index("AITaskCenter.shared.beginDeletion(documentId: document.id)")
        self.assertLess(begin, body.index("deletingIds.insert(document.id)"), "refus posé avant le retrait de la liste")
        end = body.index("AITaskCenter.shared.endDeletion(documentId: document.id)")
        self.assertLess(begin, end, "posé avant tout retrait")
        self.assertEqual(
            len([line for line in body.splitlines() if "AITaskCenter.shared.endDeletion(documentId: document.id)" in line]),
            2, "libéré dans les deux branches (effacement réussi ou échec)")

    def test_deletion_stops_document_analysis_before_erase_and_after_forget(self):
        # P2 n°3 (revue R2) : l'analyse du document entier (ou la traduction, même tâche) est arrêtée
        # avant l'effacement ; le `forget` attend la fin de la tâche, sinon une dernière lecture
        # recrée Analysis/<id>.json ou Analysis/<id>/ après leur suppression.
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument", "func closeTab(")
        self.assertLess(body.index("DocumentAnalysisService.shared.cancel(documentId:"),
                        body.index("ioQueue.async"), "arrêt demandé avant l'effacement des fichiers")
        cancel = body.index("await DocumentAnalysisService.shared.cancelAndFinish(documentId: document.id)")
        forget = body.index("DocumentAnalysisService.shared.forget(document.id)")
        self.assertLess(cancel, forget, "forget seulement après la fin de la tâche arrêtée")
        service = (ROOT / "App/Library/DocumentAnalysisService.swift").read_text(encoding="utf-8")
        for marker in ["func cancel(documentId: String)", "func cancelAndFinish(documentId: String)"]:
            self.assertIn(marker, service, marker)


if __name__ == "__main__":
    unittest.main()
