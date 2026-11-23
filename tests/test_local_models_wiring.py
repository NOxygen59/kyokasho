# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-MODLOC-001, E2 : l'import d'un modèle MLX n'est visible qu'en mode propriétaire, passe par `LocalModels`
(testé sur Mac), hors du fil principal, et décharge un modèle avant de l'effacer."""

import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App/Settings"


class LocalModelsWiringTests(unittest.TestCase):
    def test_import_section_only_when_unlocked(self):
        settings = (APP / "SettingsView.swift").read_text(encoding="utf-8")
        self.assertIn("            if ownerUnlocked {\n                LocalModelsSection()", settings)

    def test_import_uses_the_tested_core_off_main_thread(self):
        section = (APP / "LocalModelsSection.swift").read_text(encoding="utf-8")
        self.assertIn("Task.detached(priority: .userInitiated)", section)
        self.assertIn("try LocalModels.install(url, into: root)", section)
        self.assertIn("url.startAccessingSecurityScopedResource()", section)
        self.assertIn("allowedContentTypes: [.folder]", section)

    def test_delete_unloads_first(self):
        section = (APP / "LocalModelsSection.swift").read_text(encoding="utf-8")
        delete = section[section.index("private func delete("):]
        self.assertLess(delete.index("GLMOCREngine.unload(directory:"), delete.index("LocalModels.delete("))


if __name__ == "__main__":
    unittest.main()
