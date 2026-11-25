# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Simulateur : l'app ne doit pas lire la mémoire Metal de MLX au lancement.

Régression du 25/11/2026 : sur le simulateur iPad (iOS 17.0.1), `AIModelBadgeMonitor` appelle
`GLMOCREngine.status()` dès le lancement ; `MLX.GPU.activeMemory` crée le périphérique Metal de MLX, qui fait
`abort()` faute de Metal utilisable, et l'app se ferme. Sur l'iPad, le relevé réel doit rester."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "Packages/GLMOCRKit/Sources/GLMOCRKit/GLMOCREngine.swift"


class SimulatorMLXGuardTests(unittest.TestCase):
    def test_status_skips_mlx_memory_on_simulator(self):
        source = ENGINE.read_text(encoding="utf-8")
        body = re.search(r"func status\(\) -> AIModelStatus \{(.*?)\n    \}", source, re.S).group(1)
        simulator, _, device = body.partition("#else")
        self.assertIn("#if targetEnvironment(simulator)", simulator)
        self.assertNotIn("MLX.", simulator)  # aucune lecture MLX côté simulateur
        self.assertIn("MLX.GPU.activeMemory", device)  # l'iPad garde le vrai relevé
        self.assertIn("#endif", device)


if __name__ == "__main__":
    unittest.main()
