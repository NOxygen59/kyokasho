#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Garde-fous git de Kyōkasho (décision de NOxygen59 du 13/11/2026, après le blocage GitHub d'octobre).

- `pre-commit`  : refuse un commit dont les lignes ajoutées ou l'identité (auteur, committeur) contiennent un terme
  privé, un mail personnel, un numéro de téléphone ou une clé d'accès.
- `commit-msg`  : même contrôle sur le message du commit.
- `pre-push`    : refuse de pousser un commit sans relecture finale par un modèle d'une autre famille
  (`REVUE-FINALE-<sha court>.md` avec `VERDICT : OK`, voir `outils/revue_finale.py` dans le pont).
- `final-review <sha>` : même contrôle, pour `build_ipa.sh` (une candidate exige aussi sa relecture finale).

Les termes privés (nom légal…) vivent **seulement** dans `~/.kyokasho-secret` (un terme par ligne, `#` = commentaire ;
`CLE=valeur` donne `valeur`), jamais dans le dépôt. Fichier absent : tout commit est refusé (on ne protège pas à moitié).
Les messages ne réaffichent jamais un terme privé trouvé. Contournement (`git commit --no-verify`) : seulement avec
l'accord explicite de NOxygen59, noté dans le pont.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

SECRET = Path(os.environ.get("KYOKASHO_SECRET_FILE", Path.home() / ".kyokasho-secret"))
REVIEWS = Path(os.environ.get("KYOKASHO_FINAL_REVIEWS",
                              Path.home() / "Documents/Codex/Kyokasho-Pont/REVUES/FINALES"))
# Relecture finale f2b3d49 (B1) : code tiers livré tel quel, dont les en-têtes citent légitimement le mail de leurs
# auteurs. Les termes privés, téléphones et clés y restent contrôlés ; seuls les mails y sont admis.
THIRD_PARTY = ("Packages/KyokashoKit/Sources/MeCabC/", "LICENSES/", "THIRD_PARTY_NOTICES.md")
NOREPLY = re.compile(r"@(users\.noreply\.github\.com|anthropic\.com|example\.(com|org)|exemple\.fr)$", re.I)
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
PATTERNS = [
    ("téléphone", re.compile(r"(?<![\w.])(?:\+33[\s.-]?|0)[1-9](?:[\s.-]?\d{2}){4}(?![\w.])")),
    ("téléphone", re.compile(r"(?<![\w.])\+81[\s.-]?\d{1,4}[\s.-]?\d{2,4}[\s.-]?\d{3,4}(?![\w.])")),
    ("clé d'accès", re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}")),
    ("clé d'accès", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{22,}")),
    ("clé d'accès", re.compile(r"\bAKIA[0-9A-Z]{16}\b|\bAIza[0-9A-Za-z_-]{35}\b|\bGOCSPX-[A-Za-z0-9_-]{20,}")),
    ("clé d'accès", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("clé privée", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]


def secret_terms():
    if not SECRET.is_file():
        return None
    terms = []
    for line in SECRET.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        value = line.split("=", 1)[1].strip() if "=" in line else line
        if len(value) >= 3:
            terms.append(value.casefold())
    return terms


def findings(text, terms, path=None):
    """Problèmes d'un texte : (sorte, extrait sûr à afficher). Un terme privé n'est jamais réaffiché."""
    found = []
    folded = text.casefold()
    if any(term in folded for term in terms):
        found.append(("terme privé (~/.kyokasho-secret)", "<masqué>"))
    third_party = path is not None and path.startswith(THIRD_PARTY)
    for mail in [] if third_party else EMAIL.findall(text):
        if not NOREPLY.search(mail):
            found.append(("mail personnel", mail[:2] + "…"))
    for kind, pattern in PATTERNS:
        for match in pattern.finditer(text):
            found.append((kind, match.group(0)[:6] + "…"))
    return found


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def refuse(lines):
    print("Kyōkasho — commit refusé (garde-fou anti-fuite) :", file=sys.stderr)
    for line in lines:
        print("  - " + line, file=sys.stderr)
    print("Retire ces éléments. Contournement seulement avec l'accord explicite de NOxygen59.", file=sys.stderr)
    return 1


def load_terms():
    terms = secret_terms()
    if terms is None:
        print(f"Kyōkasho — commit refusé : {SECRET} est absent. Crée-le (un terme privé par ligne, chmod 600).",
              file=sys.stderr)
    return terms


def pre_commit():
    terms = load_terms()
    if terms is None:
        return 1
    problems = []
    for variable in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
        ident = git("var", variable).rsplit(">", 1)[0] + ">"
        problems += [f"identité git ({variable}) : {kind} {shown}" for kind, shown in findings(ident, terms)]
    path, number = None, 0
    for line in git("diff", "--cached", "-U0", "--no-color", "--diff-filter=ACMR").splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else line[4:]
        elif line.startswith("@@"):
            number = int(re.search(r"\+(\d+)", line).group(1)) - 1
        elif line.startswith("+"):
            number += 1
            problems += [f"{path}:{number} : {kind} {shown}" for kind, shown in findings(line[1:], terms, path)]
    return refuse(problems) if problems else 0


def commit_msg(message_file):
    terms = load_terms()
    if terms is None:
        return 1
    text = Path(message_file).read_text(encoding="utf-8")
    text = "\n".join(l for l in text.splitlines() if not l.startswith("#"))
    problems = [f"message du commit : {kind} {shown}" for kind, shown in findings(text, terms)]
    return refuse(problems) if problems else 0


def final_review_ok(sha):
    """La relecture finale de ce commit existe et conclut `VERDICT : OK`."""
    report = REVIEWS / f"REVUE-FINALE-{sha[:7]}.md"
    if not report.is_file():
        return f"aucune relecture finale pour {sha[:7]} ({report})"
    if not re.search(r"^\s*VERDICT\s*:\s*OK\b", report.read_text(encoding="utf-8"), re.M):
        return f"la relecture finale de {sha[:7]} ne conclut pas « VERDICT : OK » ({report})"
    return None


def pre_push(stdin):
    problems = []
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) != 4 or set(parts[1]) == {"0"} or not parts[2].startswith("refs/heads/"):
            continue  # suppression d'une branche, étiquette : rien à relire
        problem = final_review_ok(parts[1])
        if problem:
            problems.append(problem)
    if problems:
        print("Kyōkasho — push refusé : relecture finale par un autre modèle manquante.", file=sys.stderr)
        for problem in problems:
            print("  - " + problem, file=sys.stderr)
        print("Lancer : python3 ~/Documents/Codex/Kyokasho-Pont/outils/revue_finale.py --base <sha publié>",
              file=sys.stderr)
        return 1
    return 0


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "pre-commit":
        return pre_commit()
    if mode == "commit-msg":
        return commit_msg(argv[2])
    if mode == "pre-push":
        return pre_push(sys.stdin.read())
    if mode == "final-review":
        problem = final_review_ok(argv[2])
        if problem:
            print("Kyōkasho — " + problem, file=sys.stderr)
            return 1
        return 0
    print("usage : kyokasho_hooks.py pre-commit | commit-msg <fichier> | pre-push | final-review <sha>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
