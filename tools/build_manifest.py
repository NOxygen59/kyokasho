#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Fiche d'identité d'un paquet (lot B1 du plan de professionnalisation, accord de NOxygen59 du 13/11/2026).

Deux usages, appelés par `build_ipa.sh` :
- `app` : avant la signature, écrit `MANIFESTE.json` dans l'app (version, commit, outils, dépendances, lexiques) ;
- `paquet` : après le zip, écrit `dist/Kyokasho-<version>.manifeste.json` = la même fiche + taille et SHA-256 du
  `.tipa` + UUID des symboles (dSYM) et contrôle qu'ils correspondent au binaire.

Aucune donnée personnelle : pas de chemin absolu, pas de nom d'utilisateur ni de machine ; seulement des noms de
fichiers relatifs, des versions et des empreintes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def run(*command):
    try:
        return subprocess.run(command, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def lexicons(app):
    found = []
    for path in sorted(Path(app).glob("lexique-interieur*.zip")):
        with zipfile.ZipFile(path) as archive:
            index = json.loads(archive.read("index.json"))
        found.append({"fichier": path.name, "revision": index.get("revision"), "sha256": sha256(path)})
    return found


def uuids(binary):
    """UUID par architecture d'un binaire ou d'un dSYM (`dwarfdump --uuid`)."""
    text = run("dwarfdump", "--uuid", str(binary)) or ""
    return sorted(set(re.findall(r"UUID: ([0-9A-F-]{36})", text)))


def app_manifest(root, app, version, build, review):
    root = Path(root)
    git = lambda *a: run("git", "-C", str(root), *a)
    return {
        "app": "Kyōkasho",
        "version": version,
        "build": build,
        "commit": git("rev-parse", "HEAD"),
        "branche": git("branch", "--show-current"),
        "arbre_propre": git("status", "--porcelain", "--untracked-files=no") == "",
        "relecture_finale": review,
        "outils": {
            "xcode": (run("xcodebuild", "-version") or "").replace("\n", " "),
            "swift": (run("xcrun", "swift", "--version") or "").splitlines()[0:1],
            "sdk_ios": run("xcrun", "--sdk", "iphoneos", "--show-sdk-version"),
        },
        "dependances": {name: sha256(root / name) for name in
                        ["Packages/KyokashoKit/Package.resolved", "Packages/GLMOCRKit/Package.resolved"]
                        if (root / name).is_file()},
        "lexiques": lexicons(app),
        "commande": "./build_ipa.sh",
    }


def package_manifest(manifest, tipa, binary, dsym):
    result = dict(manifest)
    result["paquet"] = {"fichier": Path(tipa).name, "octets": Path(tipa).stat().st_size, "sha256": sha256(tipa)}
    binary_ids = uuids(binary)
    dsym_ids = uuids(dsym) if dsym and Path(dsym).exists() else []
    result["symboles"] = {
        "binaire_uuid": binary_ids,
        "dsym": Path(dsym).name if dsym_ids else None,
        "dsym_uuid": dsym_ids,
        # Jamais « présent » sans contrôle : vrai seulement si les UUID du binaire et du dSYM sont identiques.
        "correspondent": bool(binary_ids) and binary_ids == dsym_ids,
    }
    return result


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="mode", required=True)
    a = sub.add_parser("app")
    a.add_argument("--root", required=True)
    a.add_argument("--app", required=True)
    a.add_argument("--version", required=True)
    a.add_argument("--build", required=True)
    a.add_argument("--review", required=True, help="Nom du rapport de relecture finale")
    k = sub.add_parser("paquet")
    k.add_argument("--manifest", required=True, help="MANIFESTE.json écrit dans l'app")
    k.add_argument("--tipa", required=True)
    k.add_argument("--binary", required=True)
    k.add_argument("--dsym")
    k.add_argument("--out", required=True)
    args = p.parse_args()
    if args.mode == "app":
        data = app_manifest(args.root, args.app, args.version, args.build, args.review)
        if not data["arbre_propre"]:
            raise SystemExit("Arbre modifié : pas de fiche d'identité pour un commit non relu.")
        Path(args.app, "MANIFESTE.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    else:
        data = package_manifest(json.loads(Path(args.manifest).read_text(encoding="utf-8")), args.tipa, args.binary, args.dsym)
        Path(args.out).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Fiche : {Path(args.out).name} — dSYM {'OK' if data['symboles']['correspondent'] else 'ABSENT ou différent'}")
