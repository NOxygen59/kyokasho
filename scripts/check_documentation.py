#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Vérifie, sans réseau, les liens locaux des Markdown suivis par Git et les documents de pilotage obligatoires."""

import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit


# Documents de pilotage qui doivent exister, et texte que chacun doit citer pour
# qu'un nouvel agent retrouve le point d'entrée sans connaître les anciens chats.
REQUIRED = {
    "AGENTS.md": ["docs/PLAN-DIRECTEUR.md", "docs/FEUILLE-DE-ROUTE.md", "docs/INDEX.md"],
    "docs/PLAN-DIRECTEUR.md": ["../AGENTS.md", "FEUILLE-DE-ROUTE.md", "CI-ROADMAP.md", "## 8. Point de reprise"],
    "docs/INDEX.md": ["PLAN-DIRECTEUR.md", "CI-ROADMAP.md", "../AGENTS.md"],
    "docs/FEUILLE-DE-ROUTE.md": [],
    "docs/GOUVERNANCE-ET-REPRISE.md": [],
    "docs/CI-ROADMAP.md": [],
}


def check_required(root: Path) -> list[str]:
    errors = []
    for name, needles in REQUIRED.items():
        path = root / name
        if not path.is_file():
            errors.append(f"document obligatoire absent : {name}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                errors.append(f"{name}: renvoi obligatoire absent : {needle}")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "*.md"], cwd=root
    ).decode().split("\0")
    errors = []
    checked = 0
    for name in filter(None, tracked):
        source = root / name
        text = source.read_text(encoding="utf-8")
        # Les exemples dans les blocs de code ne sont pas des liens navigables.
        text = re.sub(r"^```[^\n]*\n.*?^```[^\n]*$", "", text, flags=re.M | re.S)
        for match in re.finditer(r"\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+\"[^\"]*\")?\)", text):
            destination = match.group(1).strip("<>")
            parsed = urlsplit(destination)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = (source.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(root):
                errors.append(f"{name}: lien hors dépôt : {destination}")
            elif not target.exists():
                errors.append(f"{name}: destination absente : {destination}")
            checked += 1
    errors += check_required(root)
    for error in errors:
        print(error)
    print(f"{checked} liens locaux examinés ; {len(errors)} erreur(s).")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
