# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Recette iPad 1.5.5 (1.1) : en page simple + Glissement, le Pencil faisait glisser la page tant qu'on n'avait pas
tourné une page. La garde `applyPencilPageTurnGuard` doit être réappliquée à chaque page créée par PDFKit pendant le
dessin, après l'activation du dessin et à chaque changement de page. Le comportement réel (gestes) ne se vérifie que
sur l'iPad."""

import re
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App/Reader"


class PencilGuardReappliedTests(unittest.TestCase):
    def test_new_page_overlay_reapplies_the_guard_while_drawing(self):
        source = (APP / "InkOverlay.swift").read_text()
        provider = re.search(r"overlayViewFor page: PDFPage\) -> UIView\?.*?return overlay", source, re.S).group(0)
        self.assertRegex(provider, r"if editing \{\s*DispatchQueue\.main\.async \{ \[weak controller\] in controller\?\.applyPencilPageTurnGuard\(\) \}")

    def test_drawing_activation_and_page_change_reapply_the_guard(self):
        source = (APP / "ReaderController+Navigation.swift").read_text()
        set_drawing = re.search(r"func setDrawing\(_ on: Bool\) \{.*?\n    \}", source, re.S).group(0)
        self.assertGreaterEqual(set_drawing.count("applyPencilPageTurnGuard()"), 2)
        page_changed = re.search(r"func pageChanged\(\) \{.*?\n    \}", source, re.S).group(0)
        self.assertIn("applyPencilPageTurnGuard()", page_changed)


if __name__ == "__main__":
    unittest.main()
