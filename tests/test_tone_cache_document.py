# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Garde de câblage de la revue DeepSeek #7 (C1.6) : `ToneCache.clear()` libère le PDF gardé ouvert.

Ce contrôle lit la source de l'app (non compilée par `swift test`) : il prouve le câblage, pas la
mémoire réellement rendue sur l'iPad.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def body_of(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[start:end]


class ToneCacheReleasesDocumentTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / "App/Reader/PageTone.swift").read_text(encoding="utf-8")
        self.clear = body_of(source, "    static func clear()", "    /// Taille d'après les dimensions")

    def test_clear_releases_the_open_pdf(self):
        self.assertIn("documentLock.withLock", self.clear, "le document est libéré sous son verrou")
        self.assertIn("openDocument = nil", self.clear, "le PDF gardé ouvert est lâché")
        self.assertIn("images = [:]", self.clear, "les images restent vidées")
        self.assertLess(self.clear.index("documentLock.withLock"), self.clear.index("openDocument = nil"))

    def test_lock_order_is_the_same_as_prepare(self):
        # `prepare` prend `documentLock` puis `lock` ; `clear` suit le même ordre : aucun interblocage possible.
        self.assertLess(self.clear.index("documentLock.withLock"), self.clear.index("lock.withLock"))


if __name__ == "__main__":
    unittest.main()
