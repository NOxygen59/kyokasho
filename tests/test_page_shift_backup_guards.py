# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class PageShiftBackupMutualGuardsTests(unittest.TestCase):
    """Ce contrôle lit la source des fichiers de l'app (non compilée ici) : il ne prouve rien sur l'iPad."""

    def test_drive_replacement_refuses_during_backup(self):
        # C2.7 (audit du 09/11/2026) : les autres voies de PageShift refusent déjà une sauvegarde
        # en cours ; le remplacement Drive avait le même conflit de fichiers (C1, revue Codex e777c68).
        source = (ROOT / "App/Library/PageShift.swift").read_text(encoding="utf-8")
        body = body_of(source, "static func withDriveReplacement", "private static func run(")
        guard = body.index("guard !LibraryBackupService.inProgress")
        self.assertLess(guard, body.index("applyingDocuments.insert(documentId)"),
                        "refusé avant de réserver l'opération")

    def test_backup_refuses_during_page_operation(self):
        source = (ROOT / "App/Library/LibraryBackupService.swift").read_text(encoding="utf-8")
        guard = source.index("guard !PageShift.operationInProgress")
        self.assertLess(guard, source.index("inProgress = true"),
                        "refusé avant le début de la sauvegarde")

    def test_page_shift_exposes_operation_in_progress(self):
        source = (ROOT / "App/Library/PageShift.swift").read_text(encoding="utf-8")
        body = body_of(source, "static var operationInProgress", "static func blocksAI")
        self.assertIn("!applyingDocuments.isEmpty", body)
        # P3 n°7 (revue R2) : une reprise en attente (journal page-shift.json) compte aussi comme opération
        # en cours ; la garde croisée ne dépend plus de l'ordre des « guard » dans LibraryBackupService.
        self.assertIn("pendingDocumentId != nil", body)
