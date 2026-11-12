# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Garde-fous git (décision de NOxygen59 du 13/11/2026) : un commit qui contient un terme privé, un mail personnel, un
téléphone ou une clé est refusé ; un push sans relecture finale « VERDICT : OK » aussi. Tout se passe dans un dépôt
jetable, avec un faux terme privé : jamais le vrai fichier ~/.kyokasho-secret."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOKS = Path(__file__).resolve().parents[1] / "scripts/githooks"
FAKE_NAME = "Jean Exemple"


class PrivacyHooksTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        self.secret = root / "secret"
        self.reviews = root / "finales"
        self.reviews.mkdir()
        self.secret.write_text("# terme privé de test\nNOM=" + FAKE_NAME + "\n", encoding="utf-8")
        self.env = dict(os.environ, KYOKASHO_SECRET_FILE=str(self.secret), KYOKASHO_FINAL_REVIEWS=str(self.reviews),
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q", str(self.repo), cwd=root)
        self.git("config", "user.name", "NOxygen59")
        self.git("config", "user.email", "1+NOxygen59@users.noreply.github.com")
        self.git("config", "core.hooksPath", str(HOOKS))

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env, capture_output=True, text=True)

    def commit(self, content, message="Ajout"):
        (self.repo / "f.txt").write_text(content, encoding="utf-8")
        self.git("add", "f.txt")
        return self.git("commit", "-q", "-m", message)

    def test_clean_commit_passes(self):
        result = self.commit("Rien de privé.\n", "Ajout\n\nCo-Authored-By: Claude <noreply@anthropic.com>")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_private_term_is_refused_and_never_echoed(self):
        result = self.commit("Auteur : " + FAKE_NAME.upper() + "\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("terme privé", result.stderr)
        self.assertNotIn(FAKE_NAME.casefold(), result.stderr.casefold())

    def test_mail_phone_and_keys_are_refused(self):
        for bad in ["contact : prenom.nom" + "@" + "gmail.com", "tel 06 12 34 56 78", "+81 90-1234-5678",
                    "gh" + "p_" + "a" * 36, "sk-" + "ant-" + "b" * 30, "AK" + "IA" + "ABCDEFGHIJKLMNOP",
                    "-----BEGIN " + "RSA PRIVATE KEY-----"]:
            with self.subTest(bad=bad[:8]):
                self.assertNotEqual(self.commit(bad + "\n").returncode, 0)

    def test_private_term_in_message_or_identity_is_refused(self):
        self.assertNotEqual(self.commit("ok\n", "Corrigé par " + FAKE_NAME).returncode, 0)
        self.git("config", "user.name", FAKE_NAME)
        self.assertNotEqual(self.commit("ok 2\n").returncode, 0)

    def test_missing_secret_file_refuses_everything(self):
        self.secret.unlink()
        result = self.commit("Rien de privé.\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("absent", result.stderr)

    def test_push_needs_a_final_review_with_ok_verdict(self):
        self.assertEqual(self.commit("Rien de privé.\n").returncode, 0)
        sha = self.git("rev-parse", "HEAD").stdout.strip()
        push = lambda: subprocess.run([str(HOOKS / "pre-push"), "origin", "url"], cwd=self.repo, env=self.env,
                                      input=f"refs/heads/main {sha} refs/heads/main {'0' * 40}\n",
                                      capture_output=True, text=True).returncode
        self.assertNotEqual(push(), 0, "sans relecture")
        report = self.reviews / f"REVUE-FINALE-{sha[:7]}.md"
        report.write_text("VERDICT : BLOQUANT\n", encoding="utf-8")
        self.assertNotEqual(push(), 0, "verdict bloquant")
        report.write_text("# Relecture finale\nVERDICT : OK\n", encoding="utf-8")
        self.assertEqual(push(), 0)


if __name__ == "__main__":
    unittest.main()
