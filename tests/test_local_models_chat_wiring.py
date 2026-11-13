# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-MODLOC-001, E3 : un modèle importé est proposé dans le chat, ses réglages, Stockage, les pastilles et le relevé
d'énergie ; la famille Qwen3.5 (réflexion, gabarit) couvre le modèle officiel et les modèles importés."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LocalModelsChatWiringTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_chat_engine_accepts_the_qwen35_family(self):
        chat = self.read("Packages/GLMOCRKit/Sources/GLMOCRKit/QwenChat.swift")
        self.assertIn("ModelSpec.isQwen35Family(model.id) else {", chat)
        self.assertIn('ModelSpec.isQwen35Family(model.id) ? ["enable_thinking": settings.thinking] : nil', chat)

    def test_imported_models_are_listed_everywhere(self):
        self.assertIn("[.qwen3vl4b, .qwen35chat4b] + LocalModels.specs()", self.read("App/Settings/AIChatSettingsView.swift"))
        views = self.read("App/Settings/AIModelViews.swift")
        self.assertIn("ForEach(LocalModels.specs(), id: \\.id) { spec in modelOption(spec, title: spec.title) }", views)
        self.assertIn("AIChatSettingsStore.models.first { $0.id == selectedModelID } ?? .qwen3vl4b", views)
        self.assertIn(".union(LocalModels.installed(in: store.root).map(\\.id))", self.read("App/Settings/OCRModelsView.swift"))
        for path in ["App/Settings/StorageUsage.swift", "App/Reader/AITaskCenter.swift", "App/Settings/EnergyMeter.swift"]:
            self.assertIn("LocalModels.specs()", self.read(path), path)


if __name__ == "__main__":
    unittest.main()
