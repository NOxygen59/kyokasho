#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

"""Sauvegarde hors ligne d'une COPIE du conteneur ; aucune installation sur appareil."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sqlite3
import tempfile
from urllib.parse import quote


PERSISTENT_DATABASES = (
    "Library/Application Support/Kyokasho/kyokasho.sqlite",
    "Library/Application Support/Kyokasho/Review/review.sqlite",
)
CACHES = ("Library/Caches", "tmp")
MODELS = "Library/Application Support/Kyokasho/Models"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def checked_relative(name):
    value = PurePosixPath(name)
    if not name or value.is_absolute() or ".." in value.parts or "\\" in name or str(value) != name:
        raise ValueError("Chemin invalide dans le manifeste")
    return value


def readonly(path):
    return sqlite3.connect("file:" + quote(str(path.resolve()), safe="/") + "?mode=ro", uri=True)


def is_sqlite(path):
    with path.open("rb") as stream:
        return stream.read(16) == b"SQLite format 3\x00"


def is_sqlite_auxiliary(path):
    signatures = {
        "-wal": (bytes.fromhex("377f0682"), bytes.fromhex("377f0683")),
        "-shm": (bytes.fromhex("18e22d00"), bytes.fromhex("002de218")),
        "-journal": (bytes.fromhex("d9d505f920a163d7"),),
    }
    for suffix, prefixes in signatures.items():
        if path.name.endswith(suffix):
            database = path.with_name(path.name[:-len(suffix)])
            if not database.is_file() or not is_sqlite(database):
                return False
            with path.open("rb") as stream:
                header = stream.read(max(map(len, prefixes)))
            return any(header.startswith(prefix) for prefix in prefixes)
    return False


def check_database(path):
    connection = readonly(path)
    try:
        if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
            raise ValueError("Base SQLite endommagée : " + path.name)
        if connection.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise ValueError("Relations SQLite invalides : " + path.name)
    finally:
        connection.close()


def destinations(source, destination):
    source = Path(source).resolve(strict=True)
    raw_destination = Path(destination)
    if raw_destination.exists() or raw_destination.is_symlink():
        raise ValueError("La destination doit être absente ; aucun écrasement autorisé")
    destination = raw_destination.resolve()
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError("Source et destination doivent être séparées")
    if not source.is_dir() or not destination.parent.is_dir():
        raise ValueError("Source ou dossier parent absent")
    return source, destination


def inventory(root, omit_models=False, snapshot=False):
    files = {}
    omitted = []
    for directory, names, leaves in os.walk(root, followlinks=False):
        directory = Path(directory)
        for name in list(names):
            path = directory / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                raise ValueError("Lien symbolique refusé : " + relative)
            if not snapshot and (relative in CACHES or (omit_models and relative == MODELS)):
                names.remove(name)
                omitted.append(relative)
        for name in leaves:
            path = directory / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink() or not path.is_file():
                raise ValueError("Fichier non régulier : " + relative)
            # Les journaux SQLite sont incorporés par sqlite3_backup, jamais copiés isolément.
            if not snapshot and is_sqlite_auxiliary(path):
                continue
            stat = path.stat()
            files[relative] = (stat.st_size, stat.st_mtime_ns)
    return files, sorted(omitted)


def backup(source, destination, source_stopped=False, omit_models=False):
    if not source_stopped:
        raise ValueError("L'app doit être arrêtée et la source doit être une copie hors ligne")
    source, destination = destinations(source, destination)
    for name in PERSISTENT_DATABASES:
        if not (source / name).is_file():
            raise ValueError("Base essentielle absente : " + name)
    if (source / "Library/Application Support/Kyokasho/page-shift.json").exists():
        raise ValueError("Ajout de pages en attente : conserver la copie, réparer avant sauvegarde logique")
    before, omissions = inventory(source, omit_models)
    # Les WAL sont surveillés séparément : leur contenu est pris en compte par l'API SQLite.
    wal_before = {str(p.relative_to(source)): (p.stat().st_size, p.stat().st_mtime_ns)
                  for p in source.rglob("*-wal") if p.is_file()}
    stage = Path(tempfile.mkdtemp(prefix=destination.name + ".partial-", dir=destination.parent))
    try:
        entries = {}
        for name in sorted(before):
            path = source / name
            target = stage / "files" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            database = is_sqlite(path)
            if name in PERSISTENT_DATABASES and not database:
                raise ValueError("Base essentielle illisible : " + name)
            if database:
                src = readonly(path)
                dst = sqlite3.connect(target)
                try:
                    src.backup(dst)
                    dst.execute("PRAGMA journal_mode=DELETE")
                finally:
                    dst.close()
                    src.close()
                check_database(target)
            else:
                shutil.copyfile(path, target)
            entries[name] = {"sha256": digest(target), "bytes": target.stat().st_size, "sqlite": database}
        after, _ = inventory(source, omit_models)
        wal_after = {str(p.relative_to(source)): (p.stat().st_size, p.stat().st_mtime_ns)
                     for p in source.rglob("*-wal") if p.is_file()}
        if before != after or wal_before != wal_after:
            raise ValueError("La source a changé pendant la copie ; sauvegarde refusée")
        manifest = {"format": 1, "source_stopped": True, "files": entries, "omitted": omissions,
                    "external": ["Trousseau et connexions à rétablir", "Installation TrollStore et droits iOS"]}
        (stage / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        verify(stage)
        # Réserver une destination neuve ; ne jamais remplacer un dossier apparu entre-temps.
        destination.mkdir()
        os.rename(stage, destination / "backup")
        return destination / "backup"
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)  # Uniquement notre dossier temporaire privé.
        raise


def verify(archive):
    archive = Path(archive).resolve(strict=True)
    manifest_path = archive / "manifest.json"
    if manifest_path.is_symlink() or (archive / "files").is_symlink():
        raise ValueError("Lien symbolique dans la sauvegarde")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or manifest.get("source_stopped") is not True:
        raise ValueError("Format de sauvegarde non pris en charge")
    entries = manifest["files"]
    for name in PERSISTENT_DATABASES:
        if name not in entries or entries[name].get("sqlite") is not True:
            raise ValueError("Base essentielle absente du manifeste")
    if "Library/Application Support/Kyokasho/page-shift.json" in entries:
        raise ValueError("Sauvegarde avec reprise de pages inachevée")
    actual, _ = inventory(archive / "files", snapshot=True)
    if set(actual) != set(entries):
        raise ValueError("Inventaire incomplet ou fichiers inattendus")
    for name, expected in entries.items():
        path = archive / "files" / checked_relative(name)
        if path.stat().st_size != expected["bytes"] or digest(path) != expected["sha256"]:
            raise ValueError("Empreinte incorrecte : " + name)
        if expected["sqlite"]:
            check_database(path)
    return manifest


def restore(archive, destination):
    archive, destination = destinations(archive, destination)
    manifest = verify(archive)  # Toutes les vérifications avant la première copie.
    stage = Path(tempfile.mkdtemp(prefix=destination.name + ".partial-", dir=destination.parent))
    try:
        for name in manifest["files"]:
            target = stage / checked_relative(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(archive / "files" / name, target)
            if digest(target) != manifest["files"][name]["sha256"]:
                raise ValueError("Échec de vérification après restauration")
        destination.mkdir()
        os.rename(stage, destination / "container")
        return destination / "container"
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("backup")
    create.add_argument("source")
    create.add_argument("destination")
    create.add_argument("--source-stopped", action="store_true")
    create.add_argument("--omit-models", action="store_true")
    inspect = commands.add_parser("verify")
    inspect.add_argument("archive")
    extract = commands.add_parser("restore")
    extract.add_argument("archive")
    extract.add_argument("destination")
    args = parser.parse_args()
    try:
        if args.command == "backup":
            print(backup(args.source, args.destination, args.source_stopped, args.omit_models))
        elif args.command == "restore":
            print(restore(args.archive, args.destination))
        else:
            print("Sauvegarde vérifiée :", len(verify(args.archive)["files"]), "fichiers")
    except (ValueError, OSError, sqlite3.Error, KeyError, TypeError) as error:
        parser.exit(1, "Échec : " + str(error) + "\n")


if __name__ == "__main__":
    main()
