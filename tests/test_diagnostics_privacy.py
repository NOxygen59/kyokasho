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
    # Empreintes des documents (revue R2 Codex, B-ID) et noms choisis par l'utilisateur (B-NOMS).
    r"[dD]ocumentId\b", r"\.id\b", r"backupName", r"\bmodelName\(",
]
# Interdits dans tout l'appel, même sans interpolation : messages d'interface qui contiennent une erreur système.
FORBIDDEN_ARGUMENTS = [r"storageRecoveryError", r"localizedDescription"]
# Interpolations sûres en entier : un appel d'une fonction qui rend un texte fermé (argument sans parenthèse imbriquée,
# ou une seule paire), ou un compte `x.y.count`.
SAFE_INTERPOLATION = re.compile(
    r"(?:Diagnostics\.(?:describe|ref)|(?:AITaskCenter|Self)\.diagnosticModelName)\((?:[^()]|\([^()]*\))*\)"
    r"|[A-Za-z_][\w.\[\]]*\.count")


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
                    # Exemption seulement si **toute** l'interpolation est un appel sûr ou un simple compte (F2, réunion
                    # DIAG du 25/11) : jamais par sous-chaîne.
                    if SAFE_INTERPOLATION.fullmatch(value.strip()):
                        continue
                    if any(re.search(p, value) for p in FORBIDDEN):
                        line = text.count("\n", 0, start) + 1
                        problems.append(f"{path.relative_to(ROOT)}:{line}: \\({value})")
                if any(re.search(p, call) for p in FORBIDDEN_ARGUMENTS):
                    line = text.count("\n", 0, start) + 1
                    problems.append(f"{path.relative_to(ROOT)}:{line}: argument {call[:80]}")
        self.assertEqual(problems, [], "\n".join(problems))

    def test_journal_core_uses_the_closed_contract(self):
        core = (ROOT / "App/Settings/Diagnostics.swift").read_text(encoding="utf-8")
        # Récepteur des paquets branché au lancement, avant la restauration ; ancien journal mis à l'écart (DEC-07).
        self.assertIn("DiagnosticCenter.shared.install(sink: { receive($0) }, salt: referenceSalt())", core)
        start = core.split("static func start() {", 1)[1]
        app = (ROOT / "App/KyokashoApp.swift").read_text(encoding="utf-8")
        self.assertLess(app.index("Diagnostics.start()"), app.index("LibraryBackupService.applyPendingRestoreOnce()"))
        # Zones fermées pour les anciennes lignes, journal précédent gardé (DEC-06), jamais l'ancien journal partagé.
        self.assertIn("let zone = DiagnosticZone.legacy(area)", core)
        store = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticStore.swift").read_text(encoding="utf-8")
        self.assertIn("rotated = (try? fm.moveItem(at: journal, to: previousJournal)) != nil", store)
        sharing = core.split("static func filesForSharing() -> [URL] {", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("isolatedFiles", sharing)
        self.assertIn("store.erase(.journal)", core)
        # Mêmes fichiers dans l'app et dans le store.
        self.assertIn('folder.appendingPathComponent("energie.csv")', (ROOT / "App/Settings/EnergyMeter.swift").read_text(encoding="utf-8"))
        self.assertIn('folder.appendingPathComponent("energie.csv")', store)
        # Noms en clair (garde DATA-02) identiques à ceux du paquet.
        policy = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticCenter.swift").read_text(encoding="utf-8")
        for name in ("journal.txt", "journal.1.txt"):
            self.assertIn(f'"{name}"', policy)
            self.assertIn(f'folder.appendingPathComponent("{name}")', core)

    def test_old_files_gate_every_write_read_and_share(self):
        # Réunion DIAG du 25/11, arbitrage D1 : mise à l'écart = condition d'accès, jamais d'effacement implicite.
        core = (ROOT / "App/Settings/Diagnostics.swift").read_text(encoding="utf-8")
        start = core.split("static func start() {", 1)[1]
        self.assertLess(start.index("_ = migrateOldFiles()"), start.index("DiagnosticCenter.shared.install"))
        self.assertLess(start.index("_ = migrateOldFiles()"), start.index("write(launchHeader("))
        migration = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticFileMigration.swift").read_text(encoding="utf-8")
        self.assertNotIn("removeItem", migration)
        operations = store_text = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticStore.swift").read_text(encoding="utf-8")
        operations = store_text.split("func fileSystemOperations(", 1)[1].split("\n    }\n", 1)[0]
        self.assertNotIn("removeItem", operations)
        self.assertNotIn("replaceItemAt", operations)
        enqueue = core.split("private static func enqueue(", 1)[1].split("let accepted", 1)[0]
        self.assertIn("guard filesReady else { return }", enqueue)
        self.assertIn("private static func append(_ text: String) { store.appendJournal(text) }", core)
        self.assertIn("static var filesReady: Bool { store.isReady }", core)
        self.assertIn("static func filesForSharing() -> [URL] { store.shareable() }", core)
        self.assertIn("store.erase(.journal)", core)
        store = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticStore.swift").read_text(encoding="utf-8")
        self.assertIn("guard isReady else { return false }", store)
        self.assertIn("guard isReady else { return [] }", store)
        self.assertIn('guard filesReady else { return .init(lines: [], omittedBytes: 0) }', core)
        energy = (ROOT / "App/Settings/EnergyMeter.swift").read_text(encoding="utf-8")
        append = energy.split("static func append(", 1)[1].split("static func samples", 1)[0]
        # Rejet dès l'arrivée, puis écriture par le store (revérifié sur la file, éprouvé sur vrais fichiers).
        self.assertLess(append.index("guard Diagnostics.filesReady else { return }"), append.index("queue.async"))
        self.assertIn("Diagnostics.store.appendEnergy(line, header: EnergyLog.header, limit: limit)", append)
        # Trois partages : jamais une URL brute, toujours le contrôle commun.
        app = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "App").rglob("*.swift"))
        self.assertNotIn("ShareLink(item: Diagnostics.file)", app)
        self.assertNotIn("ShareLink(item: EnergyFile.url)", app)
        self.assertIn("ShareLink(item: journal)", core)
        self.assertIn("ShareLink(item: energy)", energy)
        # Partage groupé : seulement depuis le contrôle commun.
        self.assertIn("let files = Diagnostics.filesForSharing()", core)
        self.assertIn("ShareLink(items: files)", core)
        self.assertNotIn("ShareLink(items: Diagnostics.", app)

    def test_cpu_thread_names_are_closed_labels(self):
        log = (ROOT / "Packages/KyokashoKit/Sources/ReaderCore/DiagnosticCPULog.swift").read_text(encoding="utf-8")
        label = log.split("private static func threadLabel(", 1)[1].split("return label", 1)[0]
        self.assertIn("DiagnosticThreads.closedLabel(load.name)", label)
        self.assertIn("DiagnosticThreads.closedLabel(load.queue)", label)

    def test_scanner_catches_nested_concatenation(self):
        sample = 'Diagnostics.log("x \\(Diagnostics.describe(e) + (file.lastPathComponent))", "app")'
        found = [v for _, call in calls(sample) for v in interpolations(call)
                 if not SAFE_INTERPOLATION.fullmatch(v.strip()) and any(re.search(p, v) for p in FORBIDDEN)]
        self.assertEqual(len(found), 1)

    def test_safe_interpolation_is_exact(self):
        ok = ["Diagnostics.describe(error)", "Diagnostics.ref(document.id)", "words.count", "Diagnostics.ref(id.prefix(8))"]
        bad = ["Diagnostics.describe(e) + file.lastPathComponent", "file.lastPathComponent + Diagnostics.ref(x)",
               "Diagnostics.describe(e) + (x.count + y.title.count)",
               "flag ? file.lastPathComponent : items.count", "Diagnostics.describe(e).lastPathComponent"]
        for value in ok:
            self.assertTrue(SAFE_INTERPOLATION.fullmatch(value), value)
        for value in bad:
            self.assertFalse(SAFE_INTERPOLATION.fullmatch(value), value)

    def test_review_r2_fixes_stay(self):
        core = (ROOT / "App/Settings/Diagnostics.swift").read_text(encoding="utf-8")
        # B-MLX : jamais le message natif dans le journal.
        self.assertIn("ERREUR FATALE MLX (message natif de \\(text.count) caractères)", core)
        # B-QUARANTAINE : format marqué migré seulement après mise à l'écart réussie.
        # B-ROTATION : en-tête de rotation seulement si le journal a changé de nom.
        store = (ROOT / "Packages/KyokashoKit/Sources/DiagnosticKit/DiagnosticStore.swift").read_text(encoding="utf-8")
        self.assertIn("if rotated && !fm.fileExists(atPath: journal.path) {", store)
        # B-CPU : relevés CPU avec op et étape.
        cpu = (ROOT / "App/Settings/DiagnosticCPU.swift").read_text(encoding="utf-8")
        self.assertIn('Diagnostics.logCPU(line, op: op, step: "releve_cpu")', cpu)
        self.assertIn('op: op, step: "fil_persistant", zone: .cpuPersistant)', cpu)
        # B-IA : fin de tâche IA écrite au journal avec le code d'erreur, pas le message.
        center = (ROOT / "App/Reader/AITaskCenter.swift").read_text(encoding="utf-8")
        self.assertIn("journalFailure = Diagnostics.describe(error)", center)
        self.assertIn("journal: AIActivityText.outcome(seconds: seconds, cancelled: cancelled, error: journalFailure)", center)

    def test_energy_log_never_names_a_document_or_an_imported_model(self):
        meter = (ROOT / "App/Settings/EnergyMeter.swift").read_text(encoding="utf-8")
        self.assertIn("sample.document = model?.openDocumentId.map(Diagnostics.ref)", meter)
        self.assertNotIn("$0.title", meter)
        self.assertIn('LocalModels.specs().map { ($0, "modèle importé") }', meter)


if __name__ == "__main__":
    unittest.main()
