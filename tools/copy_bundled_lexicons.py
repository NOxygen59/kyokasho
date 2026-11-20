#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Copy the separately built lexicons into an unsigned app, before signing (iOS or Mac Catalyst)."""
import argparse
import json
from pathlib import Path
import shutil
import zipfile


def revision(path):
    with zipfile.ZipFile(path) as archive:
        return json.loads(archive.read("index.json")).get("revision")


def find_expected(root, expected):
    """Folder under `root` whose French lexicon has the expected revision (newest folder name first)."""
    for candidate in sorted(Path(root).rglob("lexique-interieur.zip"), key=lambda p: str(p.parent), reverse=True):
        if revision(candidate) == expected:
            return candidate.parent
    return None


def copy_lexicons(source, app, platform, french=None, expected=None):
    # Candidate 1.5.8 (13/11/2026) : sans KYOKASHO_LEXIQUE, un ancien lexique (2026-11-04.2) est parti dans le paquet.
    # Avec la révision attendue (packaging/lexique-attendu.txt), le bon dossier est cherché, sinon refus.
    if expected is not None:
        if french is None or not french.is_file() or revision(french) != expected:
            root = french.parent if french is not None else source
            if root.name.startswith("candidat-"):
                root = root.parent
            found = find_expected(root, expected)
            if found is None:
                raise ValueError(f"Lexique {expected} introuvable : construis-le ou donne KYOKASHO_LEXIQUE")
            source, french = found, found / "lexique-interieur.zip"
            print(f"Lexicon {expected} found in {found.name}")
    languages = [("fr", "lexique-interieur"), ("en", "lexique-interieur-en")]
    if platform == "macos":
        languages.append(("zh-Hans", "lexique-interieur-zh-Hans"))
    if platform == "ios" and (app / "lexique-interieur-zh-Hans.zip").exists():
        raise ValueError("Chinese lexicon must not be shipped in the iPad app")
    # Validate all available inputs before copying the first one.
    available = []
    for language, name in languages:
        path = french if language == "fr" and french is not None else source / (name + ".zip")
        if not path.is_file():
            if expected is not None:
                raise ValueError(f"Lexique absent : {path.name} (révision {expected} attendue)")
            print(f"Lexicon absent: {path}")
            continue
        with zipfile.ZipFile(path) as archive:
            index = json.loads(archive.read("index.json"))
        if index.get("targetLanguage") != language:
            raise ValueError(f"Wrong target language in {path}")
        rev = index.get("revision") or ""
        if expected is not None and rev != expected and not rev.startswith(expected + "."):
            raise ValueError(f"Lexique {name} en révision {rev}, attendu {expected}")
        available.append((path, name + ".zip"))
    for path, name in available:
        shutil.copyfile(path, app / name)
        print(f"Lexicon added: {name}")
    return [name for _, name in available]


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", required=True, type=Path)
    p.add_argument("--app", required=True, type=Path, help="Resource directory of the unsigned app")
    p.add_argument("--platform", choices=["ios", "macos"], required=True)
    p.add_argument("--french", type=Path, help="Keep the historical KYOKASHO_LEXIQUE file override")
    p.add_argument("--expected", help="Required revision of the French lexicon (packaging/lexique-attendu.txt)")
    args = p.parse_args()
    copy_lexicons(args.source, args.app, args.platform, args.french, args.expected)
