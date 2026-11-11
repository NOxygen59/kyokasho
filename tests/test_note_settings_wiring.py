# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-T4-001, étape E3 : on règle une note depuis sa fenêtre et depuis l'écran « Notes » (une note ou plusieurs).
Contrôle de la source (vues SwiftUI non compilées par `swift test`) ; le comportement réel se vérifie sur l'iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


class NoteSettingsWiringTests(unittest.TestCase):
    def test_note_window_opens_the_settings(self):
        window = (APP / "Reader/NoteWindow.swift").read_text(encoding="utf-8")
        self.assertIn("NoteSettingsView(database: reader.model.database, noteId: note.id)", window)
        self.assertIn("reader.model.refreshNotesToReview()", window)

    def test_settings_only_write_organization_columns(self):
        settings = (APP / "Notes/NoteSettingsView.swift").read_text(encoding="utf-8")
        self.assertIn("database.apply(", settings)
        self.assertNotIn("saveNote", settings)
        self.assertNotIn("database.save(", settings)

    def test_notes_screen_has_single_and_multiple_settings(self):
        notes = (APP / "Notes/NotesView.swift").read_text(encoding="utf-8")
        self.assertIn("NoteSettingsView(database: model.database, noteId: note.id)", notes)
        self.assertIn("List(selection: $selection)", notes)
        self.assertIn("try database.apply(change, to: ids)", notes)
        for action in ("Échéance", "Priorité", "Classeur", "Étiquette"):
            self.assertIn(f'Label("{action}"', notes)
        self.assertIn("model.refreshNotesToReview()", notes)


if __name__ == "__main__":
    unittest.main()
