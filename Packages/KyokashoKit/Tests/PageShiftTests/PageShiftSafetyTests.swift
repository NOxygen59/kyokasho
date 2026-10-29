// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import PDFKit
import OCRKit
import ReaderCore
import ReviewKit
import XCTest
import Darwin

// Cadrage de l'Issue #73 : sécurité (S1 à S7) et reprise (R1 à R8) de PageShift, sur données synthétiques.
// Extension de `PageShiftRecoveryTests` pour réutiliser `withFixture`, `seed` et `verify` ; aucun accès à une
// bibliothèque réelle : tout vit dans le dossier temporaire du harnais.
extension PageShiftRecoveryTests {
    static let boundaries = ["journal.after", "database.before", "database.after", "pdf.before", "pdf.after",
                             "report.before", "report.after", "drafts.before", "drafts.after", "files.backup",
                             "files.installed", "cards.before", "cards.after", "complete.before"]

    var journalName: String { "page-shift.json" }

    func journal(_ root: URL) throws -> PageShift.Pending {
        try JSONDecoder().decode(PageShift.Pending.self, from: Data(contentsOf: root.appendingPathComponent(journalName)))
    }

    func writeJournal(_ p: PageShift.Pending, _ root: URL) throws {
        try JSONEncoder().encode(p).write(to: root.appendingPathComponent(journalName))
    }

    /// Lance un ajout de 2 pages devant le document et l'interrompt au point donné ; le journal reste.
    func interruptedApply(_ model: AppModel, _ doc: LibraryDocument, _ root: URL, at point: String,
                          offset: Int = 2) async throws {
        let merged = root.appendingPathComponent("input.pdf")
        try writePDF(merged, pages: 4)
        PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
        await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: offset, newCount: 4) }, point)
        PageShift.checkpoint = nil
    }

    /// Contenu de chaque fichier sous `dir` (chemin relatif → SHA-256). Les fichiers annexes de SQLite
    /// (`-wal`, `-shm`) sont exclus : leur état est vérifié par les requêtes, pas octet par octet.
    func inventory(_ dir: URL) throws -> [String: String] {
        var out: [String: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys) else { return out }
        let base = dir.resolvingSymlinksInPath().path
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(base.count))
            if path.hasSuffix("-wal") || path.hasSuffix("-shm") { continue }
            if values.isSymbolicLink == true {
                out[path] = "lien:" + ((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?")
            } else if values.isRegularFile == true {
                out[path] = try DocumentImporter.sha256(of: url)
            } else {
                out[path] = "dossier"
            }
        }
        return out
    }

    /// Emplacement du PDF d'un identifiant donné, calculé comme `DocumentStorage.url(for:)`.
    func restartedStorageURL(_ root: URL, _ documentId: String) -> URL {
        DocumentStorage(root: root.appendingPathComponent("Documents")).url(for: documentId)
    }

    /// Données d'origine du document de test, intactes (aucune mutation).
    func assertUnshifted(_ model: AppModel, _ doc: LibraryDocument, _ card: StudyCard,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2, file: file, line: line)
        XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 0, file: file, line: line)
        XCTAssertEqual(PDFDocument(url: model.storage.url(for: doc.id))?.pageCount, 2, file: file, line: line)
        XCTAssertEqual(try model.review.store.card(id: card.id!), card, file: file, line: line)
    }

    // MARK: Sécurité (S) — l'opération s'arrête, garde le journal et les copies, n'écrit rien ailleurs.

    /// S1 — `documentId` du journal modifié : jamais utilisé comme chemin.
    func testS1TamperedJournalDocumentIdIsRefusedWithoutWriting() async throws {
        let escape = "evil-" + UUID().uuidString
        for bad in ["../" + escape, "a/b", "..", ".", ""] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try await interruptedApply(model, doc, root, at: "journal.after")
                var p = try journal(root)
                let original = p
                p.documentId = bad
                try writeJournal(p, root)
                // Leurre : un PDF identique à l'original là où mènerait l'identifiant détourné, pour que seul le
                // contrôle du nom (et non l'absence du fichier) puisse arrêter la reprise.
                let decoy = restartedStorageURL(root, bad)
                if bad.hasPrefix("../") { try FileManager.default.copyItem(at: model.storage.url(for: doc.id), to: decoy) }
                let tampered = try Data(contentsOf: root.appendingPathComponent(journalName))
                let before = try inventory(root)
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNotNil(restarted.storageRecoveryError, bad)
                XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(journalName)), tampered, bad)
                XCTAssertEqual(try inventory(root), before, bad)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent(escape).path))
                try assertUnshifted(restarted, doc, card)
                // Le journal authentique remis en place, la reprise aboutit : rien n'a été abîmé.
                try writeJournal(original, root)
                PageShift.reconcile(restarted)
                XCTAssertNil(restarted.storageRecoveryError, bad)
                try verify(restarted, doc, card)
            }
        }
    }

    /// S1 (complément) — un identifiant de document hostile est refusé avant toute copie ou journal.
    func testS1HostileDocumentIdIsRefusedBeforeAnyCopy() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            let before = try inventory(root)
            for bad in ["../evil", "a/b", "..", "a\\b"] {
                let hostile = LibraryDocument(id: bad, title: "Hostile", originalFileName: "h.pdf", pageCount: 2, fileSize: 1)
                await assertThrowsAsync({ try await PageShift.apply(model, document: hostile, merged: merged, offset: 2, newCount: 4) }, bad)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            XCTAssertEqual(try inventory(root), before)
        }
    }

    /// S2 — `transaction` du journal modifiée ou absente : aucun chemin de travail construit avec.
    func testS2TamperedJournalTransactionIsRefusedWithoutWriting() async throws {
        let escape = "x-" + UUID().uuidString
        for bad in ["../../" + escape, "abc", nil] as [String?] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try await interruptedApply(model, doc, root, at: "journal.after")
                var p = try journal(root)
                // Leurre : copie authentique de l'espace de travail là où mènerait la transaction détournée, pour
                // que seul le contrôle de l'UUID (et non l'absence des copies) puisse arrêter la reprise.
                let escaped = root.deletingLastPathComponent().appendingPathComponent(escape)
                // Nettoyage enregistré avant la copie : même une copie partielle qui lève une erreur est retirée.
                defer { try? FileManager.default.removeItem(at: escaped) }
                if bad?.hasPrefix("../") == true {
                    try FileManager.default.copyItem(at: root.appendingPathComponent("PageShift/" + p.transaction!), to: escaped)
                }
                let escapedBefore = try inventory(escaped)
                p.transaction = bad
                try writeJournal(p, root)
                let before = try inventory(root)
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNotNil(restarted.storageRecoveryError, bad ?? "nil")
                XCTAssertEqual(try inventory(root), before, bad ?? "nil")
                XCTAssertEqual(try inventory(escaped), escapedBefore, bad ?? "nil")
                try assertUnshifted(restarted, doc, card)
            }
        }
    }

    /// S3 — lien symbolique dans les lectures IA : refus, cible intacte, aucun journal.
    func testS3SymlinkInAIReadingsStopsTheAdditionAndLeavesTargetIntact() async throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("page-shift-outside-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("secret.md")
        try Data("secret".utf8).write(to: target)
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let link = DocumentAnalysisService.folder.appendingPathComponent(doc.id).appendingPathComponent("ovisocr2-0.md")
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) })
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
            try assertUnshifted(model, doc, card)
        }
        XCTAssertEqual(try String(contentsOf: target), "secret")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["secret.md"])
    }

    /// S4 — lecture IA numérotée hors des pages du document : refus avant toute mutation.
    func testS4OutOfRangeAIReadingStopsTheAddition() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
            try Data("fantôme".utf8).write(to: folder.appendingPathComponent("x-9.md"))
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) })
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("x-9.md")), "fantôme")
            XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("ovisocr2-0.md")), "page 0")
            try assertUnshifted(model, doc, card)
        }
    }

    /// S4 — noms inhabituels : seul le dernier numéro est décalé ; sans numéro, copie à l'identique.
    /// `x--1.md` se lit « préfixe `x-`, page 1 » (le tiret n'est jamais un signe moins).
    func testS4UnusualAIReadingNamesShiftOnlyTheTrailingPageNumber() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let folder = DocumentAnalysisService.folder.appendingPathComponent(doc.id)
            let names = ["a-b-1.md": "a-b-3.md", "x--1.md": "x--3.md", "notes.md": "notes.md", "data.json": "data.json"]
            for name in names.keys { try Data(name.utf8).write(to: folder.appendingPathComponent(name)) }
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4)
            for (from, to) in names {
                XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(to)), from, from)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a-b-1.md").path))
            try verify(model, doc, card)
        }
    }

    /// #49 — un journal v2 écrit par une version précédente de l'app est toujours repris par l'ancien chemin.
    func testVersion2JournalFromAnEarlierBuildIsStillCompleted() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await interruptedApply(model, doc, root, at: "journal.after")
            var p = try journal(root)
            XCTAssertEqual(p.version, 3)
            p.version = 2
            p.cardPages = p.cardTargets?.compactMapValues { $0 }
            p.cardTargets = nil
            p.mapping = nil
            p.expectedLayoutVersion = nil
            try writeJournal(p, root)
            let restarted = try AppModel(root: root)
            for _ in 0..<3 { PageShift.reconcile(restarted) }
            XCTAssertNil(restarted.storageRecoveryError)
            try verify(restarted, doc, card)
            XCTAssertNil(try restarted.database.pageEdit(id: p.transaction!), "v2 : pas d'opération enregistrée")
        }
    }

    /// Revue Codex F4 — journal v3 d'un ajout : une carte mise à `null`, ou une page d'origine falsifiée, est refusée
    /// avant toute modification ; la reprise authentique reste possible ensuite.
    func testF4CardTargetsMustBeTheExactImageOfTheirSourcePage() async throws {
        for tamper in ["nil", "source", "inventaire"] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try await interruptedApply(model, doc, root, at: "journal.after")
                let authentic = try journal(root)
                var p = authentic
                switch tamper {
                case "nil": p.cardTargets = [card.id!: nil]
                case "source": p.cardSources = [card.id!: 1]
                default: p.cardTargets = [:]; p.cardSources = [:]
                }
                try writeJournal(p, root)
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNotNil(restarted.storageRecoveryError, tamper)
                try assertUnshifted(restarted, doc, card)
                try writeJournal(authentic, root)
                PageShift.reconcile(restarted)
                XCTAssertNil(restarted.storageRecoveryError, tamper)
                try verify(restarted, doc, card)
            }
        }
    }

    /// v2 repris après des effets déjà commis (base et PDF installés, puis coupure) : rien n'est décalé deux fois.
    func testVersion2JournalResumedAfterCommittedEffects() async throws {
        for point in ["pdf.after", "files.backup", "cards.after"] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try await interruptedApply(model, doc, root, at: "journal.after")
                var p = try journal(root)
                p.version = 2
                p.cardPages = p.cardTargets?.compactMapValues { $0 }
                p.cardTargets = nil; p.cardSources = nil; p.mapping = nil; p.expectedLayoutVersion = nil
                try writeJournal(p, root)
                let restarted = try AppModel(root: root)
                PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
                PageShift.reconcile(restarted)
                PageShift.checkpoint = nil
                XCTAssertNotNil(restarted.storageRecoveryError, point)
                let again = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(again) }
                XCTAssertNil(again.storageRecoveryError, point)
                try verify(again, doc, card)
                XCTAssertEqual(try again.database.layoutVersion(documentId: doc.id), 0, "v2 : pas de nouvelle version")
            }
        }
    }

    /// #49 — journal v3 : l'opération est enregistrée une seule fois, même après plusieurs reprises.
    func testVersion3RecordsTheEditOnceAcrossRepeatedRecoveries() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await interruptedApply(model, doc, root, at: "pdf.after")
            let p = try journal(root)
            let restarted = try AppModel(root: root)
            for _ in 0..<3 { PageShift.reconcile(restarted) }
            XCTAssertNil(restarted.storageRecoveryError)
            try verify(restarted, doc, card)
            let edit = try XCTUnwrap(restarted.database.pageEdit(id: p.transaction!))
            XCTAssertEqual(edit.kind, .insertion)
            XCTAssertEqual([edit.versionBefore, edit.versionAfter], [0, 1])
            XCTAssertEqual(try restarted.database.layoutVersion(documentId: doc.id), 1)
            XCTAssertEqual(try restarted.database.pageIdentities(documentId: doc.id).count, 4)
        }
    }

    /// S5 — pages de cartes du journal modifiées hors plage : blocage, FSRS et annotations intacts.
    func testS5TamperedCardPagesInJournalAreRefused() async throws {
        for bad in [99, 0, 1, 4] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try await interruptedApply(model, doc, root, at: "journal.after")
                var p = try journal(root)
                p.cardPages = [card.id!: bad]
                p.cardTargets = [card.id!: bad] // Journal v3 (#49) : même refus.
                try writeJournal(p, root)
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNotNil(restarted.storageRecoveryError, "\(bad)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
                try assertUnshifted(restarted, doc, card)
            }
        }
    }

    /// S6 — le PDF actif remplacé par un troisième PDF avant la reprise : blocage, rien n'est écrasé.
    func testS6ThirdPDFBeforeRecoveryIsNeverOverwritten() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await interruptedApply(model, doc, root, at: "journal.after")
            let pdf = model.storage.url(for: doc.id)
            try writePDF(pdf, pages: 3)
            let third = try DocumentImporter.sha256(of: pdf)
            let restarted = try AppModel(root: root)
            for _ in 0..<3 { PageShift.reconcile(restarted) }
            XCTAssertNotNil(restarted.storageRecoveryError)
            XCTAssertEqual(try DocumentImporter.sha256(of: pdf), third)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            XCTAssertEqual(try restarted.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertEqual(try restarted.database.bookmarks(documentId: doc.id).first?.pageIndex, 0)
            XCTAssertEqual(try restarted.review.store.card(id: card.id!), card)
        }
    }

    /// S7 — rapport d'analyse portant une page hors du document : comme les brouillons et les lectures IA,
    /// l'ajout s'arrête avant toute mutation. Régression de RET-048 (#74), corrigé : ce test était marqué
    /// `XCTExpectFailure` tant que le rapport était décalé sans contrôle.
    func testS7ReportPageOutsideTheDocumentStopsTheAddition() async throws {
        for page in [7, 2, -1] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                let url = DocumentAnalysisService.folder.appendingPathComponent(doc.id + ".json")
                var report = try JSONDecoder().decode(DocumentAnalysis.self, from: Data(contentsOf: url))
                report.pages[page] = .init(source: page, baseEngine: "test")
                let bytes = try JSONEncoder().encode(report)
                try bytes.write(to: url)
                let merged = root.appendingPathComponent("input.pdf")
                try writePDF(merged, pages: 4)
                await assertThrowsAsync({ try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4) },
                                        "Rapport avec une page \(page) sur 2 : l'ajout aurait dû s'arrêter")
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path), "\(page)")
                XCTAssertEqual(try Data(contentsOf: url), bytes, "\(page)")
                XCTAssertNil(model.storageRecoveryError, "\(page)")
                try assertUnshifted(model, doc, card)
            }
        }
    }

    // MARK: Reprise (R) — après reprise, `verify` passe : rien de perdu, rien de décalé deux fois.

    /// R1 — interruption au point a, reprise interrompue au point b, puis reprise libre : 14 × 13 = 182 couples.
    /// `journal.after` n'existe que dans `apply` (écriture du journal) : la reprise ne le traverse jamais, il est donc
    /// exclu de l'axe b. Chaque couple prouve que la seconde interruption a eu lieu et a laissé le journal.
    func testR1DoubleInterruptionMatrix() async throws {
        final class Reached { var hit = false }
        for a in Self.boundaries {
            for b in Self.boundaries where b != "journal.after" {
                try await withFixture { model, doc, root in
                    let card = try seed(model, doc)
                    try await interruptedApply(model, doc, root, at: a)
                    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path), "\(a)")
                    let restarted = try AppModel(root: root)
                    let reached = Reached()
                    PageShift.checkpoint = { if $0 == b { reached.hit = true; throw PowerLoss.simulated } }
                    PageShift.reconcile(restarted)
                    PageShift.checkpoint = nil
                    XCTAssertTrue(reached.hit, "\(a) puis \(b) : seconde interruption non atteinte")
                    XCTAssertNotNil(restarted.storageRecoveryError, "\(a) puis \(b)")
                    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path), "\(a) puis \(b)")
                    let again = try AppModel(root: root)
                    for _ in 0..<2 { PageShift.reconcile(again) }
                    XCTAssertNil(again.storageRecoveryError, "\(a) puis \(b)")
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path), "\(a) puis \(b)")
                    try verify(again, doc, card)
                }
            }
        }
    }

    /// R2 — document sans rapport, sans brouillons et sans lectures IA, interrompu à chaque frontière.
    func testR2BareDocumentInterruptedAtEveryBoundary() async throws {
        for point in Self.boundaries {
            try await withFixture { model, doc, root in
                try writePDF(model.storage.url(for: doc.id), pages: 2)
                try FileManager.default.removeItem(at: DocumentAnalysisService.folder.appendingPathComponent(doc.id))
                try model.database.save(Bookmark(documentId: doc.id, pageIndex: 1, title: "Seul"))
                try await interruptedApply(model, doc, root, at: point)
                XCTAssertNil(try journal(root).hasDrafts, point)
                XCTAssertEqual(try journal(root).hasReport, false, point)
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNil(restarted.storageRecoveryError, point)
                XCTAssertEqual(PDFDocument(url: restarted.storage.url(for: doc.id))?.pageCount, 4, point)
                XCTAssertEqual(try restarted.database.document(id: doc.id)?.pageCount, 4, point)
                XCTAssertEqual(try restarted.database.bookmarks(documentId: doc.id).first?.pageIndex, 3, point)
                XCTAssertFalse(FileManager.default.fileExists(atPath: DocumentAnalysisService.folder
                    .appendingPathComponent(doc.id + ".json").path), point)
                XCTAssertTrue(NoteDraftStore.shared.drafts(documentId: doc.id).isEmpty, point)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: DocumentAnalysisService.folder
                    .appendingPathComponent(doc.id).path), [], point)
            }
        }
    }

    /// R3 — décalages 0, 1 et 2, interrompus à chaque frontière.
    func testR3EveryOffsetInterruptedAtEveryBoundary() async throws {
        for offset in 0...2 {
            for point in Self.boundaries {
                try await withFixture { model, doc, root in
                    let card = try seed(model, doc)
                    try await interruptedApply(model, doc, root, at: point, offset: offset)
                    let restarted = try AppModel(root: root)
                    for _ in 0..<3 { PageShift.reconcile(restarted) }
                    XCTAssertNil(restarted.storageRecoveryError, "\(offset) \(point)")
                    try verify(restarted, doc, card, offset: offset)
                }
            }
        }
    }

    /// R4 — deux ajouts simultanés sur le même document : un seul aboutit, l'autre est refusé par le garde de
    /// concurrence (`applyingDocuments`, « déjà en cours ») et non par un autre contrôle ; un seul décalage.
    /// Ordre : le premier ajout insère le document puis se suspend (`beginPageMutation`, autre acteur) avant toute
    /// mutation ; le second démarre pendant cette suspension. Une autre erreur ferait échouer le test, pas le valider.
    func testR4ConcurrentAdditionsOnTheSameDocumentApplyOnce() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let merged = root.appendingPathComponent("input.pdf")
            try writePDF(merged, pages: 4)
            async let first: String? = { do { _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4); return nil } catch { return error.localizedDescription } }()
            async let second: String? = { do { _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4); return nil } catch { return error.localizedDescription } }()
            let errors = await [first, second]
            XCTAssertEqual(errors.filter { $0 == nil }.count, 1, "\(errors)")
            XCTAssertEqual(errors.compactMap { $0 }, ["Un ajout de pages de ce document est déjà en cours."], "\(errors)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            try verify(model, doc, card)
        }
    }

    /// R5 — un journal du livre A en attente bloque tout ajout sur B ; après la reprise de A, B passe.
    func testR5PendingJournalOfOneDocumentBlocksAnotherUntilRecovered() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let other = try XCTUnwrap(model.database.document(id: "other"))
            try writePDF(model.storage.url(for: other.id), pages: 2)
            try await interruptedApply(model, doc, root, at: "database.after")
            let otherMerged = root.appendingPathComponent("other-input.pdf")
            try writePDF(otherMerged, pages: 4)
            await assertThrowsAsync({ try await PageShift.apply(model, document: other, merged: otherMerged, offset: 2, newCount: 4) })
            XCTAssertEqual(try journal(root).documentId, doc.id)
            XCTAssertEqual(try model.database.document(id: other.id)?.pageCount, 2)
            XCTAssertEqual(try model.database.bookmarks(documentId: other.id).first?.pageIndex, 0)
            PageShift.reconcile(model)
            XCTAssertNil(model.storageRecoveryError)
            try verify(model, doc, card)
            _ = try await PageShift.apply(model, document: other, merged: otherMerged, offset: 2, newCount: 4)
            XCTAssertEqual(try model.database.document(id: other.id)?.pageCount, 4)
            XCTAssertEqual(try model.database.bookmarks(documentId: other.id).first?.pageIndex, 2)
            XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: other.id), [2: "brouillon autre"])
            XCTAssertEqual(try model.database.bookmarks(documentId: doc.id).first?.pageIndex, 2)
        }
    }

    /// R6 — copie de travail orpheline (interruption avant le journal) : l'ajout suivant réussit avec une
    /// nouvelle transaction ; l'orpheline reste en place, jamais réutilisée.
    func testR6OrphanWorkspaceBeforeJournalIsNeitherReusedNorBlocking() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await interruptedApply(model, doc, root, at: "journal.before")
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(journalName).path))
            let workspaces = root.appendingPathComponent("PageShift")
            let orphans = try FileManager.default.contentsOfDirectory(atPath: workspaces.path)
            XCTAssertEqual(orphans.count, 1)
            let orphanContent = try inventory(workspaces.appendingPathComponent(orphans[0]))
            try assertUnshifted(model, doc, card)
            let merged = root.appendingPathComponent("input.pdf")
            _ = try await PageShift.apply(model, document: doc, merged: merged, offset: 2, newCount: 4)
            try verify(model, doc, card)
            let after = try FileManager.default.contentsOfDirectory(atPath: workspaces.path)
            XCTAssertEqual(after.count, 2)
            XCTAssertEqual(try inventory(workspaces.appendingPathComponent(orphans[0])), orphanContent)
        }
    }

    /// R7 — fichier d'installation du PDF déjà présent à la reprise : remplacé, PDF final = `newHash`.
    func testR7LeftoverPDFInstallFileIsReplacedOnRecovery() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            try await interruptedApply(model, doc, root, at: "pdf.before")
            let p = try journal(root)
            let pdf = model.storage.url(for: doc.id)
            let leftover = pdf.deletingLastPathComponent().appendingPathComponent(".page-shift-\(p.transaction!).pdf")
            try Data("copie interrompue".utf8).write(to: leftover)
            let restarted = try AppModel(root: root)
            for _ in 0..<3 { PageShift.reconcile(restarted) }
            XCTAssertNil(restarted.storageRecoveryError)
            XCTAssertEqual(try DocumentImporter.sha256(of: pdf), p.newHash)
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
            try verify(restarted, doc, card)
        }
    }

    /// R8 — arrêt brutal du processus (SIGKILL) aux frontières que `testAbruptProcessDeathAfterCommittedEffects`
    /// ne couvre pas encore. Le processus enfant réutilise ce test (mêmes variables d'environnement).
    func testR8AbruptProcessDeathAtRemainingBoundaries() async throws {
        guard ProcessInfo.processInfo.environment["KYOKASHO_CRASH_ROOT"] == nil else { return }
        let lookup = Process()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        lookup.arguments = ["--find", "xctest"]
        let location = Pipe()
        lookup.standardOutput = location
        try lookup.run()
        lookup.waitUntilExit()
        let executable = String(decoding: location.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for point in ["journal.after", "report.after", "drafts.after", "cards.before", "complete.before"] {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                try writePDF(root.appendingPathComponent("input.pdf"), pages: 4)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = ["-XCTest", "PageShiftTests.PageShiftRecoveryTests/testAbruptProcessDeathAfterCommittedEffects",
                                     Bundle(for: Self.self).bundleURL.path]
                var env = ProcessInfo.processInfo.environment
                env["KYOKASHO_CRASH_ROOT"] = root.path
                env["KYOKASHO_CRASH_POINT"] = point
                let sanitizer = Bundle(for: Self.self).bundleURL
                    .appendingPathComponent("Contents/Frameworks/libclang_rt.asan_osx_dynamic.dylib")
                if FileManager.default.fileExists(atPath: sanitizer.path) { env["DYLD_INSERT_LIBRARIES"] = sanitizer.path }
                process.environment = env
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                try process.run()
                process.waitUntilExit()
                let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                XCTAssertEqual(process.terminationReason, .uncaughtSignal, "\(point)\n\(log)")
                XCTAssertEqual(process.terminationStatus, SIGKILL, "\(point)\n\(log)")
                let restarted = try AppModel(root: root)
                for _ in 0..<3 { PageShift.reconcile(restarted) }
                XCTAssertNil(restarted.storageRecoveryError, point)
                try verify(restarted, doc, card)
            }
        }
    }
}
