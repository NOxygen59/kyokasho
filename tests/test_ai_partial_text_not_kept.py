# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de BUG-001 (audit Fable du 10/11/2026) : un texte d'IA partiel n'est jamais gardé.

Arrêtée, la génération MLX rend le texte déjà produit sans lever d'erreur (`Task.isCancelled ? .stop : .more`).
Chaque écriture d'une lecture ou d'une traduction faite par un modèle doit donc être précédée d'un contrôle
d'annulation, sinon le fichier fait passer une page coupée pour une page lue.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas le comportement
sur l'iPad.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRITE = "DocumentAITextStore.write("
CHECKS = ("try Task.checkCancellation()", "guard !Task.isCancelled else { break }")


class PartialAITextNotKeptTests(unittest.TestCase):
    def test_every_model_text_write_follows_a_cancellation_check(self):
        found = 0
        for path in sorted((ROOT / "App").rglob("*.swift")):
            lines = path.read_text(encoding="utf-8").splitlines()
            for index, line in enumerate(lines):
                # La définition de la fonction elle-même n'est pas un appel.
                if WRITE not in line or "static func" in line:
                    continue
                found += 1
                window = lines[max(0, index - 8):index]
                # Revue DeepSeek D-07 (C3) : le contrôle doit suivre la **dernière** attente (la génération) ; un
                # contrôle placé avant elle ne prouve rien, la génération peut encore rendre un texte partiel.
                awaits = [i for i, text in enumerate(window) if "await " in text]
                before = "\n".join(window[awaits[-1] + 1:] if awaits else window)
                self.assertTrue(any(check in before for check in CHECKS),
                                f"{path.relative_to(ROOT)}:{index + 1} écrit un texte d'IA sans contrôle d'annulation")
        self.assertGreaterEqual(found, 6, "les six écritures connues sont toujours contrôlées")

    def test_generation_still_returns_partial_text_when_stopped(self):
        # Si ce comportement change (erreur levée à l'arrêt), ce contrôle et les gardes peuvent être revus.
        source = (ROOT / "Packages/GLMOCRKit/Sources/GLMOCRKit/OvisOCR2.swift").read_text(encoding="utf-8")
        self.assertGreaterEqual(len(re.findall(r"Task\.isCancelled \? \.stop : \.more", source)), 2)


if __name__ == "__main__":
    unittest.main()
