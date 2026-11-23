# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
COUNTDOWN = "Fichiers récents gardés : effaçables dans %@"
READY = "Fichiers récents : effaçables maintenant"


class StorageClearTimerWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "App/Settings/StorageUsage.swift").read_text(encoding="utf-8")

    def test_clear_keeps_the_same_cutoff_and_returns_the_latest_deadline(self):
        clear = self.source.split("static func clearCaches()", 1)[1].split("static func size(", 1)[0]
        self.assertIn("(bytes: Int64, recentUntil: Date?)", clear)
        self.assertIn("let retention: TimeInterval = 300", clear)
        self.assertIn("let recent = Date().addingTimeInterval(-retention)", clear)
        self.assertRegex(clear, re.compile(
            r"if values\?\.isDirectory == true, depth == 0 \{\s*empty\(item, depth: 1\)"
            r"\s*\} else \{\s*let modified = values\?\.contentModificationDate \?\? \.distantPast"
            r"\s*if modified < recent \{\s*try\? fm\.removeItem\(at: item\)"
            r"\s*\} else \{\s*latestKept = max\(latestKept \?\? modified, modified\)",
        ))
        self.assertEqual(clear.count("fm.removeItem("), 1)
        self.assertIn("var latestKept: Date?\n", clear)
        self.assertIn("return (max(0, before - after), latestKept.map { $0.addingTimeInterval(retention) })", clear)

    def test_notice_only_uses_an_actual_deadline_returned_by_clear(self):
        self.assertIn("cleared = await Task.detached(priority: .userInitiated) { StorageUsage.clearCaches() }.value",
                      self.source)
        self.assertRegex(self.source, r"if let recentUntil = cleared\?\.recentUntil \{"
                                      r"\s*recentCacheNotice\(until: recentUntil\)\s*\}")
        self.assertEqual(self.source.count("recentCacheNotice("), 2)

    def test_countdown_switches_to_ready_at_expiry(self):
        notice = self.source.split("private func recentCacheNotice(", 1)[1].split("private func refresh(", 1)[0]
        swift_countdown = COUNTDOWN.replace("%@", r"\(countdown)")
        self.assertIn("TimelineView(.periodic(from: .now, by: 1))", notice)
        self.assertIn("let remaining = deadline.timeIntervalSince(context.date)", notice)
        self.assertRegex(notice, r"(?s)if remaining > 0 \{.*?remaining\.rounded\(\.up\).*?"
                                 + re.escape(f'Text("{swift_countdown}")')
                                 + r"\s*\} else \{\s*" + re.escape(f'Text("{READY}")'))

    def test_both_messages_are_localized(self):
        path = ROOT / "App/Resources/Localizable.xcstrings"
        strings = json.loads(path.read_text(encoding="utf-8"))["strings"]
        # Présence, pas position : d'autres clés (notes de version) s'insèrent aussi en tête.
        self.assertIn(COUNTDOWN, strings)
        self.assertIn(READY, strings)
        for key in (COUNTDOWN, READY):
            for language in ("fr", "en", "zh-Hans"):
                with self.subTest(key=key, language=language):
                    unit = strings[key]["localizations"][language]["stringUnit"]
                    self.assertEqual(unit["state"], "translated")
                    self.assertTrue(unit["value"].strip())


if __name__ == "__main__":
    unittest.main()
