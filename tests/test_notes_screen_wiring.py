# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-T4-001 E2 et PLAN-16-001 E3 : l'écran « Notes » est atteignable depuis l'accueil, avec sa pastille,
et ouvrir une note mène à sa page et à l'onglet Notes. Contrôle de la source (SwiftUI hors de `swift test`) ;
le comportement réel se vérifie sur l'iPad."""

import re
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"


class NotesScreenWiringTests(unittest.TestCase):
    def test_home_opens_the_notes_screen_with_its_badge(self):
        library = (APP / "Library/LibraryView.swift").read_text(encoding="utf-8")
        self.assertIn('actionRow(icon: "note.text", title: String(localized: "Notes")', library)
        # PLAN-NOTIF-001 E1 : la pastille de Notes devient un « ! » noir ou rouge (le nombre reste dans l'écran Notes).
        self.assertIn("due: model.noteDueBadge) { showNotes = true }", library)
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
        self.assertIn("notesToReviewCount(today: now, excludingDocuments: excluded)", model)
        self.assertIn("noteDueBadge(today: now, excludingDocuments: excluded)", model)

    def test_opening_a_note_jumps_to_its_page_once(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        load = reader[reader.index("    func load() {"):reader.index("    /// Résultat de la construction")]
        self.assertIn("acceptNoteJump()", load)
        self.assertIn("rebuild(keepingSource: document.lastPageIndex)", load)
        install = reader[reader.index("    func install("):reader.index("    func markOpened()")]
        self.assertIn("let pendingNote = pending.flatMap { noteForJump($0) }", install)
        self.assertIn("let target = pdf == nil ? (pendingNote?.pageIndex ?? source) : currentSourcePage", install)
        self.assertIn("self?.completeNoteJump(pending)", install)
        self.assertLess(install.index("pdfView.document = pdf"), install.index("self?.completeNoteJump(pending)"))
        observe = reader[reader.index("    func observe() {"):reader.index("        let center = NotificationCenter.default", reader.index("    func observe() {"))]
        self.assertIn(".receive(on: DispatchQueue.main)", observe)
        self.assertIn("self.model.noteJump == jump", observe)
        self.assertIn("self.acceptNoteJump()", observe)

    def test_only_the_controller_consumes_the_current_jump(self):
        reader_dir = APP / "Reader"
        reader = (reader_dir / "ReaderController.swift").read_text(encoding="utf-8")
        accept = reader[reader.index("    private func acceptNoteJump()"):reader.index("    private func completeNoteJump(")]
        self.assertIn("!closed, model.openDocumentId == document.id", accept)
        self.assertIn("jump.documentId == document.id", accept)
        self.assertLess(accept.index("model.noteJump = nil"), accept.index("guard notes.contains"),
                        "la demande est consommée même si la note a disparu")
        self.assertIn("pendingAnchorNote = pending", accept)
        self.assertIn("completeNoteJump(pending)", accept)
        files_with_jump = [path.name for path in reader_dir.glob("*.swift")
                           if re.search(r"\bnoteJump\b", path.read_text(encoding="utf-8"))]
        self.assertEqual(files_with_jump, ["ReaderController.swift"])
        self.assertEqual(reader.count("model.$noteJump"), 1)
        self.assertEqual(reader.count("model.noteJump = nil"), 1)

    def test_only_a_completed_note_jump_opens_the_notes_tab(self):
        reader = (APP / "Reader/ReaderController.swift").read_text(encoding="utf-8")
        validate = reader[reader.index("    private func noteForJump("):reader.index("    private func completeNoteJump(")]
        self.assertIn("!closed, model.openDocumentId == document.id", validate)
        self.assertIn("pending.opening == model.openRequestSerial", validate)
        self.assertIn("return notes.first { $0.id == pending.noteId }", validate)
        complete = reader[reader.index("    private func completeNoteJump("):reader.index("    /// Résultat de la construction")]
        self.assertIn("guard let note = noteForJump(pending) else { return }", complete)
        self.assertIn("        goToAnchor(note)\n        completedNoteJump = pending.opening", complete)
        self.assertEqual(reader.count("completedNoteJump ="), 1)

        screen = (APP / "Reader/ReaderScreen.swift").read_text(encoding="utf-8")
        self.assertIn(".onChange(of: reader.completedNoteJump) { opening in\n"
                      "            guard opening == model.openRequestSerial, model.openDocumentId == reader.document.id else { return }\n"
                      "            showStudy(.notes)\n        }", screen)
        show = screen[screen.index("    private func showStudy("):screen.index("    // MARK: Colonne de droite animée")]
        self.assertIn("guard capabilities.study else { return }\n        studyTab = tab\n        side = .study", show)
        self.assertIn("if studyMode == .minimized { studyMode = studyRestore == .minimized ? .docked : studyRestore }", show)
        self.assertNotIn("side = nil", show)


if __name__ == "__main__":
    unittest.main()
