# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class CancelAndFinishBoundedToDocumentTests(unittest.TestCase):
    """Ce contrôle lit la source des fichiers de l'app (non compilée ici) : il ne prouve rien sur l'iPad."""

    def test_wait_is_bounded_to_the_deleted_document(self):
        # Revue DeepSeek constat n°1 (lot C2, reprise 2) : à l'effacement d'un document, l'attente de la
        # tâche d'analyse porte sur LE document effacé, jamais sur la dernière tâche créée. Supprimer A
        # pendant l'analyse d'un document B ne retardera pas `forget(A)`.
        source = (ROOT / "App/Library/DocumentAnalysisService.swift").read_text(encoding="utf-8")
        body = body_of(source, "func cancelAndFinish(documentId: String) async", "private func step(done: Int)")
        self.assertIn("taskDocumentId == documentId", body, "l'attente est bornée au document effacé")
        self.assertIn("let task", body, "la tâche n'est attendue que si elle existe")
        self.assertIn("cancel(documentId: documentId)", body, "on n'arrête que le document effacé")
        self.assertLess(body.index("taskDocumentId =="), body.index("await task.value"))
        self.assertNotIn("await task?.value", body, "plus d'attente systématique de la dernière tâche")

    def test_every_task_knows_its_document_and_clears_itself(self):
        # Les trois créations de tâche (analyse, traduction, corrections OvisOCR2) marquent leur document
        # avant la création, puis le `defer` remet `task` et `taskDocumentId` à nil : un effacement
        # ultérieur ne peut plus attendre une tâche déjà finie.
        source = (ROOT / "App/Library/DocumentAnalysisService.swift").read_text(encoding="utf-8")
        self.assertIn("private var taskDocumentId: String?", source)
        self.assertGreaterEqual(source.count("taskDocumentId = id"), 3, "trois créations de tâche marquées")
        self.assertGreaterEqual(source.count("self?.task = nil"), 3, "trois `defer` remettent `task` à nil")
        self.assertGreaterEqual(source.count("self?.taskDocumentId = nil"), 3, "trois `defer` remettent le document à nil")
        for phase in ["Lecture OCR", "Traduction (Qwen3-VL)", "Corrections OvisOCR2"]:
            body = body_of(source, f'phase: String(localized: "{phase}"', "task = Task { [weak self] in")
            self.assertIn("taskDocumentId = id", body, f"document noté avant la tâche ({phase})")

    def test_app_model_still_forgets_after_the_task_ends(self):
        # La garantie utilisateur de P2 n°3 reste : `forget` après `cancelAndFinish`, pas avant.
        source = (ROOT / "App/AppModel.swift").read_text(encoding="utf-8")
        body = body_of(source, "func delete(_ document: LibraryDocument)", "func closeTab(")
        self.assertIn("await DocumentAnalysisService.shared.cancelAndFinish(documentId: document.id)", body)
        self.assertLess(body.index("await DocumentAnalysisService.shared.cancelAndFinish(documentId: document.id)"),
                        body.index("DocumentAnalysisService.shared.forget(document.id)"))


if __name__ == "__main__":
    unittest.main()
