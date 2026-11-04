#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Copy the separately built lexicons into an unsigned app, before signing (iOS or Mac Catalyst)."""
import argparse
import json
from pathlib import Path
import shutil
import zipfile


def copy_lexicons(source, app, platform, french=None):
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
            print(f"Lexicon absent: {path}")
            continue
        with zipfile.ZipFile(path) as archive:
            index = json.loads(archive.read("index.json"))
        if index.get("targetLanguage") != language:
            raise ValueError(f"Wrong target language in {path}")
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
    args = p.parse_args()
    copy_lexicons(args.source, args.app, args.platform, args.french)
