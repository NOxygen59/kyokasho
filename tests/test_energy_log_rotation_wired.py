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
        self.assertIn("EnergyLog.rotated(data, keeping: limit / 2)", source)
        self.assertIsNone(re.search(r"data\.suffix\(limit / 2\)", source), "ancienne coupe au milieu d'une ligne")

    def test_samples_are_read_as_bytes(self):
        source = METER.read_text(encoding="utf-8")
        self.assertIn("EnergyLog.parse((try? Data(contentsOf: url)) ?? Data())", source)


if __name__ == "__main__":
    unittest.main()
