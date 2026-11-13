# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.7 : nom de dossier dans une fenêtre de l'app (2.1), barre à poignée qui ne bouge plus quand sa
taille change et qui se prend par toute sa surface (1.2), écran Notes avec date et heure (4.1). Contrôle de la source ;
le rendu réel se vérifie sur l'iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


class Recette157FixesTests(unittest.TestCase):
    def test_folder_name_is_an_in_app_sheet(self):
        library = (APP / "Library/LibraryView.swift").read_text(encoding="utf-8")
        self.assertIn("FolderNameSheet(title: folderNaming?.title", library)
        self.assertNotIn('.alert(folderNaming?.title ?? ""', library)
        sheet = library[library.index("struct FolderNameSheet"):]
        self.assertIn("Button(confirm, action: done).disabled(!valid)", sheet)

    def test_toolbar_position_is_relative_to_the_area_and_whole_bar_drags(self):
        bar = (APP / "Reader/FloatingToolbar.swift").read_text(encoding="utf-8")
        self.assertIn("fractionX * area.width + drag.width", bar)
        self.assertIn("fractionX = area.width > 0 ? endX / area.width : 0", bar)
        self.assertIn(".contentShape(Rectangle())\n        .gesture(gesture)", bar)
        self.assertNotIn("grabMargin", bar)

    def test_notes_show_date_and_time(self):
        notes = (APP / "Notes/NotesView.swift").read_text(encoding="utf-8")
        self.assertIn("Label(Self.dateLabel(note), systemImage: \"clock\")", notes)
        self.assertIn("Date.FormatStyle(date: .abbreviated, time: .shortened)", notes)


if __name__ == "__main__":
    unittest.main()
