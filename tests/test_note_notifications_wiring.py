# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-NOTIF-001 E3/E4 : câblage des notifications de notes (le calcul pur est testé en Swift, NoteReminder)."""

import pathlib
import unittest

APP = pathlib.Path(__file__).resolve().parents[1] / "App"


class NoteNotificationsWiringTests(unittest.TestCase):
    def read(self, path):
        return (APP / path).read_text(encoding="utf-8")

    def test_reminders_are_rescheduled_with_the_badge_and_on_return(self):
        model = self.read("AppModel.swift")
        self.assertIn("NoteNotifications.reschedule(database: database,", model)
        app = self.read("KyokashoApp.swift")
        self.assertIn("if phase == .active { model.refreshNotesToReview() }", app)

    def test_only_note_requests_are_replaced_and_iOS_limit_is_kept(self):
        service = self.read("Notes/NoteNotifications.swift")
        self.assertIn('static let prefix = "note-"', service)
        self.assertIn("static let limit = 60", service)
        self.assertIn(".filter { $0.hasPrefix(prefix) }", service)
        self.assertIn("for item in notes where !item.organization.archived {", service)
        self.assertIn("authorizationStatus == .notDetermined", service)

    def test_tapping_a_notification_opens_the_note_even_from_a_cold_start(self):
        app = self.read("KyokashoApp.swift")
        self.assertIn("UNUserNotificationCenter.current().delegate = NoteNotificationDelegate.shared", app)
        self.assertIn(".onAppear { NoteNotificationDelegate.shared.model = model }", app)
        service = self.read("Notes/NoteNotifications.swift")
        self.assertIn("pending = (documentId, noteId)", service)
        self.assertIn("func open(_ note: PageComment) { openNote(documentId: note.documentId, noteId: note.id) }",
                      self.read("AppModel.swift"))


if __name__ == "__main__":
    unittest.main()
