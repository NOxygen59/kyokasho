#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Vérifie les destinations locales des liens Markdown suivis par Git, sans réseau."""

import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit


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
    for error in errors:
        print(error)
    print(f"{checked} liens locaux examinés ; {len(errors)} erreur(s).")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
