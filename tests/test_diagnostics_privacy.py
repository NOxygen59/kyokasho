# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""PLAN-DIAG-001, E1 (DEC-01) : aucune donnée personnelle n'entre dans le journal, le relevé de batterie ni la
mémoire des dernières tâches. Garde du source : chaque appel au journal, même écrit sur plusieurs lignes, est relu
et ne doit interpoler ni titre, ni chemin, ni nom de fichier, ni message d'erreur système, ni texte."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CALL = re.compile(r"(?:Diagnostics\.(?:log|error|alert|write|remember|measure|logCPU)|(?<![\w.])remember)\(")
# Interpolations interdites dans un appel au journal (`\(…)`).
FORBIDDEN = [
    r"\.title\b", r"localizedDescription", r"lastPathComponent", r"\.path\b", r"[fF]ileName", r"\.url\b",
    r"\bmanifest\b", r"\.text\b", r"\bentry\.name\b", r"\bprepared\.name\b", r"\bspec\.title\b",
]


def calls(text):
    """Chaque appel au journal avec ses arguments complets (parenthèses équilibrées, chaînes comprises)."""
    return calls_of(text, CALL)


def calls_of(text, pattern):
    for match in re.finditer(pattern, text):
        depth, i, in_string = 1, match.end(), False
        while i < len(text) and depth:
            c = text[i]
            if c == "\\" and in_string:
                i += 2
                continue
            if c == '"':
                in_string = not in_string
            elif not in_string and c in "([{":
                depth += 1
            elif not in_string and c in ")]}":
                depth -= 1
            i += 1
        yield match.start(), text[match.start():i]


def interpolations(call):
    """Contenu des `\\(…)` d'un appel (parenthèses imbriquées comprises)."""
    out, i = [], 0
    while True:
        i = call.find("\\(", i)
        if i < 0:
            return out
        depth, j = 1, i + 2
        while j < len(call) and depth:
            depth += {"(": 1, ")": -1}.get(call[j], 0)
            j += 1
        out.append(call[i + 2:j - 1])
        i = j


class DiagnosticsPrivacyTests(unittest.TestCase):
    def test_no_personal_data_is_interpolated_into_the_journal(self):
        problems = []
        for path in sorted((ROOT / "App").rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            for start, call in calls(text):
                for value in interpolations(call):
                    # Fonctions qui rendent un texte sûr, et nombres (`….count`).
                    if "Diagnostics.describe(" in value or "Diagnostics.ref(" in value or value.endswith(".count"):
                        continue
                    if any(re.search(p, value) for p in FORBIDDEN):
                        line = text.count("\n", 0, start) + 1
                        problems.append(f"{path.relative_to(ROOT)}:{line}: \\({value})")
        self.assertEqual(problems, [], "\n".join(problems))

    def test_journal_core_uses_the_closed_contract(self):
        core = (ROOT / "App/Settings/Diagnostics.swift").read_text(encoding="utf-8")
        # Récepteur des paquets branché au lancement, avant la restauration ; ancien journal mis à l'écart (DEC-07).
        self.assertIn("DiagnosticCenter.shared.install(sink: { receive($0) }, salt: referenceSalt())", core)
        start = core.split("static func start() {", 1)[1]
        self.assertLess(start.index("quarantineOldJournalIfNeeded()"), start.index("DiagnosticCenter.shared.install"))
        app = (ROOT / "App/KyokashoApp.swift").read_text(encoding="utf-8")
        self.assertLess(app.index("Diagnostics.start()"), app.index("LibraryBackupService.applyPendingRestoreOnce()"))
        # Zones fermées pour les anciennes lignes, journal précédent gardé (DEC-06), jamais l'ancien journal partagé.
        self.assertIn("let zone = DiagnosticZone.legacy(area)", core)
        self.assertIn("try? fm.moveItem(at: file, to: previousFile)", core)
        sharing = core.split("static func filesForSharing() -> [URL] {", 1)[1].split("}", 1)[0]
        self.assertNotIn("quarantinedFile", sharing)
        self.assertIn("for url in [file, previousFile, quarantinedFile]", core)
        # Noms en clair (garde DATA-02) identiques à ceux du paquet.
        policy = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticCenter.swift").read_text(encoding="utf-8")
        for name in ("journal.txt", "journal.1.txt", "journal-avant-diagnostics.txt"):
            self.assertIn(f'"{name}"', policy)
            self.assertIn(f'folder.appendingPathComponent("{name}")', core)

    def test_ai_task_lines_reach_the_journal_without_titles_or_raw_errors(self):
        center = (ROOT / "App/Reader/AITaskCenter.swift").read_text(encoding="utf-8")
        self.assertNotIn("jobs[i].title", center.split("func log(", 1)[1].split("\n    }", 1)[0])
        self.assertIn("· \\(journal ?? line)\", \"ia\")", center)
        for path in sorted((ROOT / "App").rglob("*.swift")):
            for start, call in calls_of(path.read_text(encoding="utf-8"), r"(?:AITaskCenter\.shared|center)\.log\("):
                if "localizedDescription" in call:
                    self.assertIn("journal: ", call, f"{path.relative_to(ROOT)} : erreur brute sans version journal")

    def test_energy_log_never_names_a_document_or_an_imported_model(self):
        meter = (ROOT / "App/Settings/EnergyMeter.swift").read_text(encoding="utf-8")
        self.assertIn("sample.document = model?.openDocumentId.map(Diagnostics.ref)", meter)
        self.assertNotIn("$0.title", meter)
        self.assertIn('LocalModels.specs().map { ($0, "modèle importé") }', meter)


if __name__ == "__main__":
    unittest.main()
