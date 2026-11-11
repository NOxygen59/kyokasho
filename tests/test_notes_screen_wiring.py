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
        self.assertIn(".fullScreenCover(isPresented: $showNotes, onDismiss: {", library)
        self.assertIn("if let note = noteToOpen { model.open(note) }", library)
        self.assertIn("NotesView { noteToOpen = $0 }", library)

    def test_notes_entry_is_outside_the_manga_only_block(self):
        # Revue DeepSeek F1 : les PDF de Manga ont aussi des notes.
        library = (APP / "Library/LibraryView.swift").read_text(encoding="utf-8")
        before_merge = library[:library.index('title: String(localized: "Fusionner des PDF")')]
        last_block = before_merge.rindex("if space != .manga {")
        notes_row = before_merge.index('actionRow(icon: "note.text"')
        closing = before_merge.index("}", last_block)
        self.assertGreater(notes_row, closing, "l'entrée Notes suit la fermeture du bloc réservé à l'étude")

    def test_badge_excludes_trashed_documents(self):
        model = (APP / "AppModel.swift").read_text(encoding="utf-8")
        self.assertIn("notesToReviewCount(today: Date(), excludingDocuments: excluded)", model)

    def test_opening_a_note_jumps_to_its_page_once(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        self.assertIn("rebuild(keepingSource: jumpNote?.pageIndex ?? document.lastPageIndex)", reader)
        load = reader[reader.index("    func load() {"):reader.index("    /// Résultat de la construction")]
        self.assertIn("if let jump = model.noteJump, jump.documentId == document.id {", load)
        self.assertIn("            model.noteJump = nil\n        }", load, "consommée même si la note a disparu (F2)")
        self.assertIn("pendingAnchorNote = jumpNote", load)
        self.assertIn("self.model.noteJump = nil", reader)


if __name__ == "__main__":
    unittest.main()
