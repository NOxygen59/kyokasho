# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.6 (1.2 à 1.4) : en mode dessin, les défilements de PDFKit au-dessus d'une page attendent l'échec du
geste de dessin de la toile, et la toile ne retient plus rien hors du mode dessin. Contrôle de la source (UIKit non
testable sur Mac) ; le comportement réel se vérifie sur l'iPad."""

import unittest
from pathlib import Path

INK = Path(__file__).resolve().parents[1] / "App/Reader/InkOverlay.swift"


class PencilPageHoldTests(unittest.TestCase):
    def test_page_scrolls_wait_for_the_drawing_gesture(self):
        source = INK.read_text(encoding="utf-8")
        self.assertIn("scroll.panGestureRecognizer.require(toFail: canvas.drawingGestureRecognizer)", source)
        hold = source[source.index("private func holdPageScrollsForPencil()"):]
        self.assertIn("guard let canvas, isUserInteractionEnabled, window != nil", hold)

    def test_hold_is_set_when_the_page_appears_and_when_drawing_starts(self):
        source = INK.read_text(encoding="utf-8")
        moved = source[source.index("override func didMoveToWindow()"):source.index("private func holdPageScrollsForPencil()")]
        self.assertIn("holdPageScrollsForPencil()", moved)
        editing = source[source.index("func setEditing(_ on: Bool, toolPicker:"):]
        self.assertIn("canvas.drawingGestureRecognizer.isEnabled = on", editing)
        self.assertIn("holdPageScrollsForPencil()", editing[:editing.index("} else {")])


if __name__ == "__main__":
    unittest.main()
