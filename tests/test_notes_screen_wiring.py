# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-T4-001, étape E2 : l'écran « Notes » est atteignable depuis l'accueil, la pastille compte les notes à revoir,
et ouvrir une note mène le lecteur à sa page. Contrôle de la source (vues SwiftUI non compilées par `swift test`) ;
le comportement réel se vérifie sur l'iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


class NotesScreenWiringTests(unittest.TestCase):
    def test_home_opens_the_notes_screen_with_its_badge(self):
        library = (APP / "Library/LibraryView.swift").read_text(encoding="utf-8")
        self.assertIn('actionRow(icon: "note.text", title: String(localized: "Notes")', library)
        self.assertIn("count: model.notesToReview) { showNotes = true }", library)
        self.assertIn(".fullScreenCover(isPresented: $showNotes, onDismiss: { model.refreshNotesToReview() })", library)
        self.assertIn("NotesView()", library)

    def test_badge_excludes_trashed_documents(self):
        model = (APP / "AppModel.swift").read_text(encoding="utf-8")
        self.assertIn("notesToReviewCount(today: Date(), excludingDocuments: excluded)", model)

    def test_opening_a_note_jumps_to_its_page_once(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        self.assertIn("rebuild(keepingSource: jumpNote?.pageIndex ?? document.lastPageIndex)", reader)
        self.assertIn("if jumpNote != nil { model.noteJump = nil }", reader)
        self.assertIn("self.model.noteJump = nil", reader)


if __name__ == "__main__":
    unittest.main()
