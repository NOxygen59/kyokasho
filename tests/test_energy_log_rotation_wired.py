# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""BUG-004 (audit Fable) et revue DeepSeek D-07 (C2) : la coupe du relevé de batterie doit passer par
`EnergyLog.rotated` (coupe au début d'une ligne, testée dans `EnergyLogRotationTests`) et la lecture par
`EnergyLog.parse(Data)`. Ce contrôle lit la source de l'app, que `swift test` ne compile pas."""

import re
import unittest
from pathlib import Path

METER = Path(__file__).resolve().parents[1] / "App/Settings/EnergyMeter.swift"


class EnergyLogRotationWiredTests(unittest.TestCase):
    def test_append_trims_through_rotated(self):
        source = METER.read_text(encoding="utf-8")
        # PLAN-DIAG-001 E1 : l'écriture passe par `DiagnosticStore.appendEnergy`, qui coupe à `limit / 2` avec la
        # fonction fournie ; l'app y passe toujours `EnergyLog.rotated`.
        self.assertIn("{ EnergyLog.rotated($0, keeping: $1) }", source)
        store = (METER.parents[2] / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticStore.swift").read_text(encoding="utf-8")
        self.assertIn("try? rotate(data, limit / 2).write(to: energy)", store)
        self.assertIsNone(re.search(r"data\.suffix\(limit / 2\)", source), "ancienne coupe au milieu d'une ligne")

    def test_samples_are_read_as_bytes(self):
        source = METER.read_text(encoding="utf-8")
        self.assertIn("EnergyLog.parse((try? Data(contentsOf: url)) ?? Data())", source)


if __name__ == "__main__":
    unittest.main()
