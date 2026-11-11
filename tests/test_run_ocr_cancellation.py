# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de la revue DeepSeek #9 (C1.9) : le `catch` de `runOCR` applique `OCRCancellation`.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas
l'absence d'échec affiché sur l'iPad.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECK = "OCRCancellation.isCancellation(error, taskCancelled: Task.isCancelled)"


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class RunOCRCancellationTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / "App/Reader/ReaderController+OCR.swift").read_text(encoding="utf-8")
        self.run_ocr = body_of(source, "    func runOCR(engine: String? = nil",
                               "    /// OCR d'une page avec un moteur précis")
        self.ensure_ocr = body_of(source, "    func ensureOCR(", "    func cancelEnsureOCR()")

    def test_cancellation_is_not_shown_as_a_failure(self):
        self.assertIn(CHECK, self.run_ocr)
        self.assertIn("self.ocrState = cancelled ? .idle : .failed(error.localizedDescription)", self.run_ocr)
        self.assertNotIn("self.ocrState = .failed(error.localizedDescription)", self.run_ocr,
                         "plus d'échec affiché sans regarder si la lecture a été annulée")

    def test_a_cancelled_read_keeps_the_chosen_engine_and_a_quiet_log(self):
        self.assertIn("if !cancelled, let intent { self.ocrSelection.revert(intent) }", self.run_ocr)
        self.assertIn("if !cancelled { Diagnostics.error(", self.run_ocr)

    def test_same_rule_as_the_background_queue(self):
        # La file de fond applique déjà C1.9 : les deux chemins doivent parler du même test.
        self.assertIn(CHECK, self.ensure_ocr)


if __name__ == "__main__":
    unittest.main()
