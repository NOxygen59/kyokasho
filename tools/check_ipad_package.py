#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Refuse un paquet iPad contenant ce que seule la version Mac utilise (docs/VERSIONS-PLATEFORMES.md)."""
import argparse
from pathlib import Path
import plistlib


def problems(app):
    """Liste des défauts du dossier `Kyokasho.app`, vide si le paquet convient à l'iPad."""
    found = [f"Chinois présent : {path.relative_to(app)}" for path in app.rglob("zh-Hans.lproj")]
    for name in ("llama-server", "lexique-interieur-zh-Hans.zip"):
        found += [f"Réservé au Mac : {path.relative_to(app)}" for path in app.rglob(name)]
    for name in ("lexique-interieur.zip", "lexique-interieur-en.zip"):
        if not (app / name).is_file():
            found.append(f"Lexique absent : {name}")
    with (app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if "zh-Hans" in info.get("CFBundleLocalizations", []):
        found.append("Chinois déclaré dans Info.plist")
    return found


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    defects = problems(parser.parse_args().app)
    for defect in defects:
        print(defect)
    raise SystemExit(1 if defects else 0)
