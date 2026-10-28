# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59

import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import unicodedata
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import backup_container as storage


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kyokasho-backup-synthetic-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.support = self.source / "Library/Application Support/Kyokasho"
        self.support.mkdir(parents=True)
        self.connections = []
        for name in storage.PERSISTENT_DATABASES:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            connection = sqlite3.connect(path)
            self.connections.append(connection)
            self.addCleanup(connection.close)
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("CREATE TABLE sample(id INTEGER PRIMARY KEY, page INTEGER, note TEXT, stability REAL)")
            connection.execute("INSERT INTO sample VALUES (1, 2, '図 : note et OCR retouché', 12.25)")
            connection.commit()
        self.payloads = {
            "Library/Application Support/Kyokasho/Documents/test.pdf": b"PDF synthetique",
            "Library/Application Support/Kyokasho/Review/Media/image.png": b"image-test",
            "Library/Application Support/Analysis/test/ovisocr2-2.md": "図 : lecture brute".encode(),
            "Library/Application Support/Analysis/test.json": b'{"pages":{"2":{"source":2}}}',
            "Library/Application Support/Kyokasho/lexique.json": b'{"term":"test"}',
            "Library/Application Support/Kyokasho/Chats/qwen-test.json": b'[{"text":"question"}]',
            "Library/Preferences/fr.noxygen59.kyokasho.plist": b"preferences-test",
            "Documents/Diagnostics/journal.txt": b"diagnostic synthetique",
        }
        for name, value in self.payloads.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)

    def create(self, **kwargs):
        return storage.backup(self.source, self.root / "sauvegarde", source_stopped=True, **kwargs)

    def test_roundtrip_captures_wal_and_preserves_all_payloads(self):
        self.assertTrue(any(self.source.rglob("*-wal")))
        archive = self.create()
        restored = storage.restore(archive, self.root / "restauration")
        for name, value in self.payloads.items():
            self.assertEqual((restored / name).read_bytes(), value)
        for name in storage.PERSISTENT_DATABASES:
            with sqlite3.connect(restored / name) as connection:
                self.assertEqual(connection.execute("SELECT * FROM sample").fetchall(),
                                 [(1, 2, "図 : note et OCR retouché", 12.25)])
            self.assertFalse(Path(str(restored / name) + "-wal").exists())
        storage.verify(archive)

    def test_requires_stopped_source(self):
        with self.assertRaises(ValueError):
            storage.backup(self.source, self.root / "no")

    def test_pending_page_shift_is_refused_without_deleting_it(self):
        marker = self.support / "page-shift.json"
        marker.write_text('{"stage":"cards"}')
        with self.assertRaises(ValueError):
            self.create()
        self.assertEqual(marker.read_text(), '{"stage":"cards"}')

    def test_missing_essential_database_is_refused(self):
        empty = self.root / "empty"
        empty.mkdir()
        with self.assertRaises(ValueError):
            storage.backup(empty, self.root / "no", source_stopped=True)

    def test_modified_payload_prevents_any_restore(self):
        archive = self.create()
        (archive / "files" / next(iter(self.payloads))).write_bytes(b"corrupted")
        target = self.root / "restauration"
        with self.assertRaises(ValueError):
            storage.restore(archive, target)
        self.assertFalse(target.exists())

    def test_missing_payload_is_detected(self):
        archive = self.create()
        (archive / "files" / next(iter(self.payloads))).unlink()
        with self.assertRaises(ValueError):
            storage.verify(archive)

    def test_unexpected_sqlite_wal_is_not_ignored(self):
        archive = self.create()
        (archive / "files" / (storage.PERSISTENT_DATABASES[0] + "-wal")).write_bytes(b"unexpected")
        with self.assertRaises(ValueError):
            storage.verify(archive)

    def test_ordinary_files_with_sqlite_suffixes_survive_restore(self):
        base = self.source / "Documents/notes"
        base.parent.mkdir(parents=True, exist_ok=True)
        base.write_text("texte personnel, pas une base SQLite")
        names = ["Documents/notes" + suffix for suffix in ("-wal", "-shm", "-journal")]
        for name in names:
            (self.source / name).write_text("donnée persistante : " + name)
        archive = self.create()
        manifest = storage.verify(archive)
        restored = storage.restore(archive, self.root / "restauration")
        for name in names:
            self.assertIn(name, manifest["files"])
            self.assertNotIn(name, manifest["omitted"])
            self.assertEqual((restored / name).read_bytes(), (self.source / name).read_bytes())

    def test_real_wal_and_shared_memory_are_folded_into_sqlite_backup(self):
        database = storage.PERSISTENT_DATABASES[0]
        self.assertTrue((self.source / (database + "-wal")).exists())
        self.assertTrue((self.source / (database + "-shm")).exists())
        archive = self.create()
        manifest = storage.verify(archive)
        restored = storage.restore(archive, self.root / "restauration")
        for suffix in ("-wal", "-shm"):
            self.assertNotIn(database + suffix, manifest["files"])
            self.assertFalse((restored / (database + suffix)).exists())
        with sqlite3.connect(restored / database) as connection:
            self.assertEqual(connection.execute("SELECT note FROM sample").fetchone()[0],
                             "図 : note et OCR retouché")

    def test_existing_destination_is_never_overwritten(self):
        archive = self.create()
        target = self.root / "occupied"
        target.mkdir()
        (target / "personal").write_text("intact")
        with self.assertRaises(ValueError):
            storage.restore(archive, target)
        self.assertEqual((target / "personal").read_text(), "intact")

    def test_symbolic_link_source_is_rejected(self):
        (self.support / "link").symlink_to(self.root)
        with self.assertRaises(ValueError):
            self.create()

    def test_path_traversal_is_rejected_before_writing(self):
        archive = self.create()
        manifest_path = archive / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["files"]["../outside"] = {"bytes": 0, "sha256": "", "sqlite": False}
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            storage.restore(archive, self.root / "no")
        self.assertFalse((self.root / "outside").exists())

    def test_optional_models_and_regenerable_caches_are_listed(self):
        for name in [storage.MODELS + "/weight", "Library/Caches/thumb", "tmp/work"]:
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("synthetique")
        archive = self.create(omit_models=True)
        manifest = storage.verify(archive)
        self.assertEqual(set(manifest["omitted"]), set(storage.CACHES + (storage.MODELS,)))
        restored = storage.restore(archive, self.root / "restauration")
        self.assertFalse((restored / storage.MODELS).exists())

    def test_copy_failure_never_publishes_backup(self):
        with patch.object(storage.shutil, "copyfile", side_effect=OSError("disque plein")):
            with self.assertRaises(OSError):
                self.create()
        self.assertFalse((self.root / "sauvegarde").exists())
        for name, value in self.payloads.items():
            self.assertEqual((self.source / name).read_bytes(), value)

    def test_restore_copy_failure_never_publishes_container(self):
        archive = self.create()
        with patch.object(storage.shutil, "copyfile", side_effect=OSError("disque plein")):
            with self.assertRaises(OSError):
                storage.restore(archive, self.root / "restauration")
        self.assertFalse((self.root / "restauration").exists())
        storage.verify(archive)

    def test_source_mutation_is_detected(self):
        original_copy = storage.shutil.copyfile
        name = next(iter(self.payloads))
        def changing_copy(src, dst):
            result = original_copy(src, dst)
            (self.source / name).write_bytes(b"changed during backup")
            return result
        with patch.object(storage.shutil, "copyfile", side_effect=changing_copy):
            with self.assertRaises(ValueError):
                self.create()
        self.assertFalse((self.root / "sauvegarde").exists())


    # --- DATA-02 (Issue #83) : noms, fichiers particuliers, arrêt brutal, limite du manifeste ---

    def test_r1_japanese_unicode_and_long_names_roundtrip_exactly(self):
        """Octets de chaque nom conservés. NFC et NFD sont dans deux dossiers : APFS ne permet pas de créer les deux
        formes dans le même dossier, l'absence de collision n'est donc pas testée ici."""
        nfc = unicodedata.normalize("NFC", "が教科書.md")
        nfd = unicodedata.normalize("NFD", "が教科書.md")
        self.assertNotEqual(nfc.encode(), nfd.encode())
        names = {
            "Library/Application Support/Analysis/教科書 1/ovisocr2-1.md": "図 : lecture".encode(),
            "Library/Application Support/Kyokasho/Chats/nfc/" + nfc: b"forme NFC",
            "Library/Application Support/Kyokasho/Chats/nfd/" + nfd: b"forme NFD",
            "Library/Application Support/Kyokasho/NoteDrafts/doc avec espaces.json": b'{"0":"brouillon"}',
            "Library/Application Support/Kyokasho/Chats/" + "a" * 196 + ".txt": b"nom de 200 caracteres",
        }
        for name, value in names.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        restored = storage.restore(self.create(), self.root / "restauration")
        for name, value in names.items():
            self.assertEqual((restored / name).read_bytes(), value, name)
        # Octets exacts des noms : aucune normalisation silencieuse NFC/NFD.
        chats = restored / "Library/Application Support/Kyokasho/Chats"
        self.assertEqual(os.listdir(os.fsencode(chats / "nfc")), [os.fsencode(nfc)])
        self.assertEqual(os.listdir(os.fsencode(chats / "nfd")), [os.fsencode(nfd)])

    def test_r2_empty_large_and_read_only_files_roundtrip(self):
        """Contenus identiques. Les permissions ne sont pas conservées (`shutil.copyfile`) : un fichier 0444 ressort
        selon l'umask ; seule la lisibilité est garantie."""
        large = bytes(range(256)) * (64 * 1024 * 1024 // 256)
        files = {
            "Library/Application Support/Kyokasho/vide.json": b"",
            "Library/Application Support/Kyokasho/Documents/gros.pdf": large,
            "Library/Application Support/Kyokasho/lecture-seule.json": b'{"lecture":"seule"}',
        }
        for name, value in files.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
        os.chmod(self.source / "Library/Application Support/Kyokasho/lecture-seule.json", 0o444)
        restored = storage.restore(self.create(), self.root / "restauration")
        for name, value in files.items():
            self.assertEqual((restored / name).read_bytes(), value, name)

    def run_killed(self, call, point):
        """Exécute `call` dans un processus enfant tué par SIGKILL au point demandé (vraie mort, pas d'exception)."""
        tools = Path(storage.__file__).resolve().parent
        code = textwrap.dedent(f"""
            import os, signal, sys
            sys.path.insert(0, {str(tools)!r})
            import backup_container as s
            from pathlib import Path
            point, calls = {point!r}, [0]
            real_copy, real_rename = s.shutil.copyfile, s.os.rename
            def copy(src, dst):
                result = real_copy(src, dst)
                calls[0] += 1
                if (point == "first-copy" and calls[0] == 1) or (point == "mid-copy" and calls[0] == 4):
                    os.kill(os.getpid(), signal.SIGKILL)
                return result
            def rename(old, new):
                if point == "before-publish":
                    os.kill(os.getpid(), signal.SIGKILL)
                return real_rename(old, new)
            s.shutil.copyfile, s.os.rename = copy, rename
            {call}
            """)
        process = subprocess.run([sys.executable, "-I", "-c", code], capture_output=True, text=True)
        self.assertEqual(process.returncode, -signal.SIGKILL, point + "\n" + process.stderr)

    def test_r3_backup_killed_never_publishes_and_source_stays_intact(self):
        for index, point in enumerate(("first-copy", "mid-copy", "before-publish")):
            destination = self.root / f"sauvegarde-{index}"
            self.run_killed(f"s.backup(Path({str(self.source)!r}), Path({str(destination)!r}), source_stopped=True)", point)
            self.assertFalse((destination / "backup").exists(), point)
            if destination.exists():  # Arrêt entre la réservation et la publication : dossier vide, jamais écrasé.
                self.assertEqual(list(destination.iterdir()), [], point)
                with self.assertRaises(ValueError):
                    storage.backup(self.source, destination, source_stopped=True)
            for name, value in self.payloads.items():
                self.assertEqual((self.source / name).read_bytes(), value, point)
        archive = storage.backup(self.source, self.root / "relance", source_stopped=True)
        storage.verify(archive)

    def test_r3_restore_killed_never_publishes_container(self):
        archive = self.create()
        for index, point in enumerate(("first-copy", "mid-copy", "before-publish")):
            destination = self.root / f"restauration-{index}"
            self.run_killed(f"s.restore(Path({str(archive)!r}), Path({str(destination)!r}))", point)
            self.assertFalse((destination / "container").exists(), point)
            storage.verify(archive)
        restored = storage.restore(archive, self.root / "relance")
        for name, value in self.payloads.items():
            self.assertEqual((restored / name).read_bytes(), value)

    def test_r4_known_limit_archive_changed_with_recomputed_manifest_is_accepted(self):
        """Limite connue (PHASE2-SAUVEGARDE) : le manifeste prouve la cohérence, pas l'authenticité."""
        archive = self.create()
        name = "Library/Application Support/Kyokasho/lexique.json"
        forged = b'{"term":"modifie"}'
        (archive / "files" / name).write_bytes(forged)
        manifest = json.loads((archive / "manifest.json").read_text(encoding="utf-8"))
        manifest["files"][name].update(sha256=storage.digest(archive / "files" / name), bytes=len(forged))
        (archive / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
        storage.verify(archive)
        restored = storage.restore(archive, self.root / "restauration")
        self.assertEqual((restored / name).read_bytes(), forged)

if __name__ == "__main__":
    unittest.main()
