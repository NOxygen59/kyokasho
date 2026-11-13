# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-MODLOC-001, E1 (DEC-01 à DEC-03 = A, décidés par NOxygen59 le 13/11/2026) : trois touchers sur « Temps de
lecture » basculent le mode propriétaire ; verrouillé, tout le chat est caché. Contrôle de la source (vues SwiftUI non
compilées par `swift test`) ; le geste réel se vérifie sur l'iPad."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"
KEY = "@AppStorage(OwnerMode.unlockedKey) private var ownerUnlocked = false"


class OwnerModeWiringTests(unittest.TestCase):
    def read(self, path):
        return (APP / path).read_text(encoding="utf-8")

    def test_stats_card_counts_taps_then_decides(self):
        library = self.read("Library/LibraryView.swift")
        self.assertIn("Button { statsTapped() } label: { statsCardContent }", library)
        self.assertIn("case .single: showDashboard = true", library)
        self.assertIn("case .toggleOwnerMode: OwnerMode.toggle()", library)

    def test_every_chat_entry_is_hidden_while_locked(self):
        self.assertIn("if !document.capabilities.chat || !ownerUnlocked {", self.read("Library/LibraryView.swift"))
        study = self.read("Study/StudyPanel.swift")
        self.assertIn("reader.document.capabilities.chat && ownerUnlocked", study)
        self.assertIn(".onChange(of: ownerUnlocked) { _ in normalizeTab() }", study)
        settings = self.read("Settings/SettingsView.swift")
        self.assertIn("if ownerUnlocked {\n                LocalModelsSection()\n                Section {\n                    NavigationLink { AIChatSettingsView() }", settings)
        self.assertIn(".filter { ownerUnlocked || $0.id != ModelSpec.qwen35chat4b.id }", settings)
        self.assertIn("if ownerUnlocked, spec.id == ModelSpec.qwen3vl4b.id", self.read("Settings/AIModelViews.swift"))
        self.assertIn('if ownerUnlocked { row(.qwen35chat4b', self.read("Settings/OCRModelsView.swift"))
        for path in ["Library/LibraryView.swift", "Study/StudyPanel.swift", "Settings/SettingsView.swift",
                     "Settings/AIModelViews.swift", "Settings/OCRModelsView.swift"]:
            self.assertIn(KEY, self.read(path), path)


if __name__ == "__main__":
    unittest.main()
