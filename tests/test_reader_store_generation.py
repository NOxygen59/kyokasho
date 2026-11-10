# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
READER = ROOT / "App/Reader"


class ReaderStoreGenerationTests(unittest.TestCase):
    """UIKit/OCRKit ne sont pas chargés ici : ce contrôle lit la source, il ne prouve rien sur l'iPad."""

    def test_every_reader_ocr_store_passes_expected_generation(self):
        # C2.5 (audit du 09/11/2026) : une écriture du panneau OCR sans `expectedGeneration`
        # peut s'installer sur une page déplacée ou relue entre-temps. Les voies hors du lecteur
        # (`DocumentAnalysisService`) ont un autre contrat : non couvertes par ce contrôle.
        found = []
        for path in sorted(READER.rglob("*.swift")):
            for line in path.read_text(encoding="utf-8").splitlines():
                if ".store(" in line and not line.lstrip().startswith("//"):
                    found.append((path.name, line.strip()))
                    self.assertIn("expectedGeneration", line, (path.name, line.strip()))
        self.assertGreaterEqual(len(found), 5)


if __name__ == "__main__":
    unittest.main()
