// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import PDFKit
import OCRKit
import ReaderCore
import ReviewKit
import XCTest

// Lot C2.3 (fiche f85d0c0, DEC-C2 = A) : le remplacement d'un cours Drive déplace vers le
// nouvel identifiant les brouillons de notes, les lectures IA et corrections, le rapport
// d'analyse et les modes d'outil ; une bascule interrompue reprend au lancement suivant depuis
// le journal `page-shift.json`, sans perte ni double déplacement, et n'écrase jamais un
// fichier déjà présent chez l'identifiant d'arrivée. Tout vit dans le dossier temporaire du
// harnais (aucune bibliothèque réelle).
extension PageShiftRecoveryTests {
    /// P3 n°6 (revue R2) : toutes les frontières d'un remplacement Drive — celles partagées avec
    /// les modifications de pages, plus `journal.before` (écriture du journal) et les noms propres
    /// au remplacement (`files.before`, `modes.before`, `modes.after`) qui n'existent pas dans
    /// `Self.boundaries` : une coupure y est rejouée au même titre que les autres.
    static let replacementBoundaries = ["journal.before", "journal.after", "database.before",
                                        "database.after", "cards.before", "cards.after",
                                        "drafts.before", "drafts.after", "files.before",
                                        "files.installed", "modes.before", "modes.after",
                                        "complete.before"]

    var journalFile: String { "page-shift.json" }

    /// Nouveaux PDF et plan de remplacement (métriques calculées avant le journal, comme DriveViews).
    func replacementPlan(_ root: URL, pages: Int, revision: String = "rév. 2") throws -> (PageShift.DriveReplacement, URL) {
        let merged = root.appendingPathComponent("drive-nouvelle-version-" + UUID().uuidString + ".pdf")
        try writePDF(merged, pages: pages)
        let hash = try DocumentImporter.sha256(of: merged)
        let size = Int64(try merged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let plan = PageShift.DriveReplacement(source: merged, newDocumentId: hash, pageCount: pages,
                                              fileSize: size, driveRevision: revision)
        return (plan, merged)
    }

    /// Écrit un journal de remplacement tel qu'une bascule arrêtée **avant** la bascule SQL l'a laissé :
    /// ni le nouveau PDF dans le stockage, ni changement en base, tout doit sortir du journal seul.
    func writeReplacementJournal(_ root: URL, oldId: String, oldCount: Int, oldSize: Int64,
                                 plan: PageShift.DriveReplacement) throws {
        let p = PageShift.Pending(documentId: oldId, offset: 0, oldCount: oldCount, oldSize: oldSize,
                                  newCount: plan.pageCount, newSize: plan.fileSize, stage: "prepared", version: 3,
                                  transaction: UUID().uuidString, oldHash: nil, newHash: nil,
                                  hasReport: false, kind: "replacement",
                                  newDocumentId: plan.newDocumentId, newRevision: plan.driveRevision,
                                  newSourcePath: plan.source.path)
        try JSONEncoder().encode(p).write(to: root.appendingPathComponent(journalFile))
    }

    func journalExists(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(journalFile).path)
    }

    /// État complet attendu après une bascule finie (premier passage ou reprise, un objet comme l'autre).
    func verifyReplacement(_ model: AppModel, root: URL, old: LibraryDocument, card: StudyCard,
                           plan: PageShift.DriveReplacement) throws {
        let oldId = old.id, newId = plan.newDocumentId
        // Base : la bascule a eu lieu, une et une seule fois.
        XCTAssertNil(try model.database.document(id: oldId))
        var updated = try XCTUnwrap(model.database.document(id: newId))
        XCTAssertEqual(updated.driveRevision, plan.driveRevision)
        XCTAssertFalse(journalExists(root))

        // C2.1 : pas d'OCR de l'ancienne version, rognage auto nul, choix de l'utilisateur gardés.
        XCTAssertTrue(try model.database.ocrResults(documentId: newId).isEmpty)
        XCTAssertTrue(try model.database.ocrResults(documentId: oldId).isEmpty)
        let transforms = try model.database.pageTransforms(documentId: newId)
        XCTAssertNil(transforms[0]?.autoCrop)
        XCTAssertEqual(transforms[1]?.rotation, 90)
        XCTAssertEqual(try model.database.highlights(documentId: newId).first?.pageIndex, 0)

        // C2.2 : la carte suit le nouvel identifiant, page source et planification FSRS intactes.
        var expectedCard = card
        expectedCard.sourceDocumentId = newId
        XCTAssertEqual(try model.review.store.card(id: card.id!), expectedCard)
        XCTAssertEqual(try model.review.store.sourcePages(documentId: newId), [try XCTUnwrap(card.id): 0])
        XCTAssertTrue(try model.review.store.sourcePages(documentId: oldId).isEmpty)

        // C2.3 : fichiers servis par l'identifiant, déplacés une seule fois.
        XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: newId), [0: "brouillon 0", 1: "brouillon 1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: NoteDraftStore.shared.url(documentId: oldId).path))
        let aiOld = DocumentAITextStore.folder.appendingPathComponent(oldId, isDirectory: true)
        let aiNew = DocumentAITextStore.folder.appendingPathComponent(newId, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: aiOld.path))
        XCTAssertEqual(try String(contentsOf: aiNew.appendingPathComponent("ovisocr2-0.md")), "page 0")
        XCTAssertEqual(try String(contentsOf: aiNew.appendingPathComponent("fr-0.md")), "traduction 0")
        let report = try JSONDecoder().decode(DocumentAnalysis.self,
            from: Data(contentsOf: DocumentAnalysisService.folder.appendingPathComponent(newId + ".json")))
        XCTAssertEqual(report.documentId, newId, "le rapport porte le nouvel identifiant")
        XCTAssertEqual(report.pages[0]?.source, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: DocumentAnalysisService.folder.appendingPathComponent(oldId + ".json").path))
        let modes = ReaderToolModeStore().modes(documentId: newId)
        XCTAssertTrue(modes.drawing)
        XCTAssertEqual(modes.panelMode, "floating")
        XCTAssertNil(UserDefaults.standard.data(forKey: ReaderToolModeStore.key(documentId: oldId)))

        // PDF : la nouvelle version est en place, l'ancienne est retirée du stockage.
        XCTAssertEqual(PDFDocument(url: model.storage.url(for: newId))?.pageCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.storage.url(for: oldId).path))

        // Les autres livres ne bougent jamais (seed « other »).
        XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: "other"), [0: "brouillon autre"])
        XCTAssertEqual(try model.database.bookmarks(documentId: "other").first?.pageIndex, 0)
        XCTAssertFalse(PageShift.isBusy(oldId))
        XCTAssertFalse(PageShift.isBusy(newId))
    }

    /// Clés « modes » dans les réglages standard : remises dans l'état d'avant le test (harnais).
    func trackModeKeys(_ oldId: String, _ newId: String) -> () -> () {
        let defaults = UserDefaults.standard
        let keys = [ReaderToolModeStore.key(documentId: oldId), ReaderToolModeStore.key(documentId: newId)]
        let saved = keys.map { (key: $0, value: defaults.object(forKey: $0)) }
        return {
            for entry in saved {
                if let value = entry.value { defaults.set(value, forKey: entry.key) } else { defaults.removeObject(forKey: entry.key) }
            }
        }
    }

    /// Clés « historique des ajouts de pages » (format de PageAdditionHistory : `pages.additions.<id>`)
    /// et « journal des séances de lecture » : état du harnais sauvegardé puis remis exactement.
    func trackPerDocumentDefaults(_ ids: [String]) -> () -> () {
        let defaults = UserDefaults.standard
        let keys = ["pages.additions." + ids[0], "pages.additions." + ids[1], ReadingTimeTracker.sessionsKey]
        let saved = keys.map { (key: $0, value: defaults.object(forKey: $0)) }
        return {
            for entry in saved {
                if let value = entry.value { defaults.set(value, forKey: entry.key) }
                else { defaults.removeObject(forKey: entry.key) }
            }
        }
    }

    /// P3 n°5 (revue R2) : ajoute un historique d'ajouts et une séance de lecture pour l'ancienne
    /// version, à raccrocher à l'identifiant d'arrivée par la bascule.
    func seedPerDocumentHistories(_ oldId: String, additionDate: Date) {
        PageAdditionHistory.record(PageAddition(date: additionDate, added: 2, insertedBefore: 0,
                                                totalAfter: 4, sources: ["f.pdf"]), documentId: oldId)
        var sessions = ReadingSessionLog()
        sessions.record(documentId: oldId, start: additionDate, end: additionDate.addingTimeInterval(180))
        UserDefaults.standard.set(sessions.encoded(), forKey: ReadingTimeTracker.sessionsKey)
    }

    /// P3 n°5 : après la bascule, les deux historiques vivent sous le nouvel identifiant,
    /// et rien ne reste sous l'ancien.
    func verifyHistoriesFollowTheReplacement(_ oldId: String, _ newId: String) throws {
        XCTAssertEqual(PageAdditionHistory.load(newId).entries.map(\.added), [2], "historique des ajouts suivi")
        XCTAssertTrue(PageAdditionHistory.load(oldId).entries.isEmpty, "ancienne clé retirée")
        let sessions = ReadingSessionLog.decode(UserDefaults.standard.data(forKey: ReadingTimeTracker.sessionsKey))
        XCTAssertEqual(sessions.sessions.map(\.documentId), [newId], "temps de lecture suivi, durées intactes")
        XCTAssertEqual(sessions.sessions.map(\.seconds), [180])
    }

    /// Bas­cule complète : la version Drive remplace le cours et tout suit (retrace le lot C2.3 au fil du code).
    func testDriveReplacementFollowsEverything() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            XCTAssertNil(UserDefaults.standard.data(forKey: ReaderToolModeStore.key(documentId: plan.newDocumentId)))
            // P2 n°2 : la langue OCR a été choisie pour l'ancienne version (import initial).
            OCRTargetLanguage.set(.automatic, forDocument: doc.id)
            defer { OCRTargetLanguage.forget(plan.newDocumentId); OCRTargetLanguage.forget(doc.id) }
            DocumentScan.started = []
            // P3 n°5 : historique des ajouts et temps de lecture, à faire suivre à la bascule.
            let defaultsDone = trackPerDocumentDefaults([doc.id, plan.newDocumentId])
            defer { defaultsDone() }
            seedPerDocumentHistories(doc.id, additionDate: Date(timeIntervalSince1970: 500))
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            // Rognage automatique calculé sur l'ancienne version : il repart à zéro (C2.1 sur la bascule).
            try model.database.save(PageTransform(documentId: doc.id, pageIndex: 0,
                                                  autoCrop: .init(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))

            let importer = DocumentImporter(storage: model.storage, database: model.database)
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
            }
            try verifyReplacement(model, root: root, old: doc, card: card, plan: plan)
            try verifyHistoriesFollowTheReplacement(doc.id, plan.newDocumentId)
            // P2 n°2 : la langue OCR du livre suit le nouvel identifiant, et la lecture IA est relancée.
            XCTAssertEqual(OCRTargetLanguage.forDocument(plan.newDocumentId), .automatic)
            XCTAssertEqual(OCRTargetLanguage.forDocument(doc.id), .japanese, "ancienne clé retirée")
            XCTAssertTrue(DocumentScan.started.contains(model.storage.url(for: plan.newDocumentId).path),
                          "lecture IA relancée pour le nouveau document")
        }
    }

    /// Interruption après la bascule SQL (cartes Déplacées, fichiers pas encore) : le redémarrage
    /// finit via le journal, puis un second redémarrage n'ajoute rien (pas de double par déplacement).
    func testInterruptedDriveReplacementResumesAtLaunchOnce() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            PageShift.checkpoint = { if $0 == "cards.after" { throw PowerLoss.simulated } }
            await assertThrowsAsync({
                try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                    try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                         driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
                }
            }, "cards.after")
            PageShift.checkpoint = nil
            // Bascule SQL passée : le nouveau document est en base, cartes suivies, journal en place.
            XCTAssertNotNil(try model.database.document(id: plan.newDocumentId))
            XCTAssertNil(try model.database.document(id: doc.id))
            XCTAssertEqual(try model.review.store.sourcePages(documentId: plan.newDocumentId), [try XCTUnwrap(card.id): 0])
            XCTAssertTrue(journalExists(root))
            XCTAssertNotNil(model.storageRecoveryError, "l'écran se souvient qu'une reprise est attendue")
            // Fichiers pas encore déplacés : donnée intacte sous l'ancien identifiant.
            XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: doc.id), [0: "brouillon 0", 1: "brouillon 1"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: DocumentAnalysisService.folder.appendingPathComponent(doc.id, isDirectory: true).path))

            let restarted = try AppModel(root: root)
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
            // Deuxième lancement : il n'y a plus rien à rejouer.
            PageShift.reconcile(restarted)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
        }
    }

    /// Interruption avant la bascule SQL (journal seul, le PDF d'arrivée pas copié dans le stockage) :
    /// la reprise termine depuis le journal seul, avec la copie depuis le fichier téléchargé.
    func testResumeBeforeTheSQLSwitchFinishesFromTheJournalAlone() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, _) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            // P2 n°2 : le choix de langue OCR (fait à l'import initial) attend la reprise de la bascule.
            OCRTargetLanguage.set(.automatic, forDocument: doc.id)
            defer { OCRTargetLanguage.forget(plan.newDocumentId); OCRTargetLanguage.forget(doc.id) }
            DocumentScan.started = []
            // P3 n°5 : les historiques restent sous l'ancien identifiant jusqu'à la reprise.
            let defaultsDone = trackPerDocumentDefaults([doc.id, plan.newDocumentId])
            defer { defaultsDone() }
            seedPerDocumentHistories(doc.id, additionDate: Date(timeIntervalSince1970: 500))
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            // Protection : l'ancien PDF n'est pas encore remplacé dans le stockage.
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertFalse(FileManager.default.fileExists(atPath: model.storage.url(for: plan.newDocumentId).path))

            let restarted = try AppModel(root: root)
            DocumentScan.started = []
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
            // P2 n°2 : finie par la reprise au lancement, la langue suit quand même le document,
            // et la lecture IA est bien (re)lancée pour le nouveau fichier.
            XCTAssertEqual(OCRTargetLanguage.forDocument(plan.newDocumentId), .automatic,
                           "langue appliquée par la reprise, pas seulement par l'écran d'import")
            XCTAssertEqual(OCRTargetLanguage.forDocument(doc.id), .japanese)
            XCTAssertTrue(DocumentScan.started.contains(restarted.storage.url(for: plan.newDocumentId).path),
                          "la reprise relance la lecture IA du document")
            // P3 n°5 : les historiques suivent le nouvel identifiant, reprise incluse.
            try verifyHistoriesFollowTheReplacement(doc.id, plan.newDocumentId)
        }
    }

    /// Échec avant la bascule SQL : l'invariant « document d'origine en base = rien appliqué » fait
    /// retirer le journal ; la mise à jour peut être relancée, rien n'a changé.
    func testFailureBeforeTheSQLSwitchReleasesTheJournal() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            let importer = DocumentImporter(storage: model.storage, database: model.database)

            await assertThrowsAsync {
                try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                    throw PowerLoss.simulated
                }
            }
            XCTAssertNil(model.storageRecoveryError, "rien n'était en cours : pas d'écran de reprise")
            XCTAssertFalse(journalExists(root))
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
            XCTAssertEqual(try model.review.store.card(id: card.id!), card)
            XCTAssertTrue(FileManager.default.fileExists(atPath: model.storage.url(for: doc.id).path))

            // Relance : la même mise à jour passe alors.
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
            }
            try verifyReplacement(model, root: root, old: doc, card: card, plan: plan)
        }
    }

    /// P3 n°6 (revue R2) — une coupure à chaque frontière du remplacement laisse soit tout
    /// intact (avant la bascule SQL : journal retiré, mise à jour relançable), soit un journal
    /// rejoué au lancement — même motif exhaustif que les autres opérations de pages.
    func testReplacementSurvivesAPowerCutAtEveryStep() async throws {
        for point in Self.replacementBoundaries {
            try await withFixture { model, doc, root in
                let card = try seed(model, doc)
                let (plan, newPDF) = try replacementPlan(root, pages: 3)
                let importer = DocumentImporter(storage: model.storage, database: model.database)
                let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
                defer { modesDone() }
                ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
                PageShift.checkpoint = { if $0 == point { throw PowerLoss.simulated } }
                await assertThrowsAsync({
                    try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                        try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                             driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
                    }
                }, point)
                PageShift.checkpoint = nil
                if try model.database.document(id: plan.newDocumentId) != nil {
                    // Coupe après la bascule SQL : la reprise finit, puis un second lancement n'ajoute rien.
                    XCTAssertTrue(journalExists(root), point)
                    let restarted = try AppModel(root: root)
                    PageShift.reconcile(restarted)
                    XCTAssertNil(restarted.storageRecoveryError, point)
                    try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
                    PageShift.reconcile(restarted)
                    try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
                } else {
                    // Coupe avant la bascule : rien d'appliqué, le journal est retiré, la relance passe.
                    XCTAssertNil(model.storageRecoveryError, point)
                    XCTAssertFalse(journalExists(root), point)
                    try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                        try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                             driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
                    }
                    try verifyReplacement(model, root: root, old: doc, card: card, plan: plan)
                }
            }
        }
    }

    /// P3 n°10 (revue R2) — pendant la bascule (et sa reprise), une tâche IA visant le **nouvel**
    /// identifiant est refusée comme celle de l'ancien ; la réserve est levée une fois la reprise finie.
    func testNewIdIsReservedAgainstAITasksDuringTheReplacement() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            PageShift.checkpoint = { if $0 == "cards.after" { throw PowerLoss.simulated } }
            await assertThrowsAsync({
                try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                    try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                         driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
                }
            })
            PageShift.checkpoint = nil
            XCTAssertTrue(PageShift.blocksAI(jobKey: "review|\(doc.id)"), "ancien identifiant déjà réservé")
            XCTAssertTrue(PageShift.blocksAI(jobKey: "review|\(plan.newDocumentId)"),
                          "le nouvel identifiant est réservé pendant les déplacements")
            XCTAssertFalse(PageShift.blocksAI(jobKey: "review|other"), "les autres livres ne sont pas touchés")

            let restarted = try AppModel(root: root)
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            XCTAssertFalse(PageShift.blocksAI(jobKey: "review|\(plan.newDocumentId)"),
                           "reprise finie : la réserve est levée")
            XCTAssertFalse(PageShift.blocksAI(jobKey: "review|\(doc.id)"))
        }
    }

    /// P2 n°3 (revue R2 F3) — un journal qui désigne un fichier qui n'est pas le nouveau PDF est
    /// refusé à la reprise : rien n'est déplacé ni retiré, le journal reste ; la reprise
    /// authentique remise en place finit normalement.
    func testTamperedReplacementSourceFileIsRefusedAtRecovery() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, _) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            // Leurre : PDF honnête de 3 pages, mais son empreinte ne vaut pas `newDocumentId`.
            let decoy = root.appendingPathComponent("leurre-" + UUID().uuidString + ".pdf")
            try writePDF(decoy, pages: 3)
            defer { try? FileManager.default.removeItem(at: decoy) }
            var tampered = try journal(root)
            tampered.newSourcePath = decoy.path
            try JSONEncoder().encode(tampered).write(to: root.appendingPathComponent(journalFile))
            let tamperedBytes = try Data(contentsOf: root.appendingPathComponent(journalFile))
            let before = try inventory(root)

            let restarted = try AppModel(root: root)
            for _ in 0..<2 { PageShift.reconcile(restarted) }
            XCTAssertNotNil(restarted.storageRecoveryError, "un journal altéré arrête la reprise")
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(journalFile)), tamperedBytes)
            XCTAssertEqual(try inventory(root), before, "aucun fichier déplacé ni retiré par un journal altéré")
            try assertUnshifted(restarted, doc, card)
            XCTAssertNil(try restarted.database.document(id: plan.newDocumentId))

            // Journal authentique remis en place : la reprise finit, rien n'a été abîmé entre-temps.
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
        }
    }

    /// Fichiers déjà présents chez l'identifiant d'arrivée (version re-importée après avoir été
    /// retirée) : jamais écrasés ; les données de l'ancienne version sont mises de côté dans
    /// `Conflits-remplacement/<ancien identifiant>/` (P2 n°4 de la revue R2), comptées pour le
    /// rapport de fin, et la bascule finit quand même.
    func testExistingTargetFilesAreNeverOverwrittenAndSourceKept() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            try NoteDraftStore.shared.write([4: "ancienne donnée"], documentId: plan.newDocumentId)
            let aiNew = DocumentAITextStore.folder.appendingPathComponent(plan.newDocumentId, isDirectory: true)
            try FileManager.default.createDirectory(at: aiNew, withIntermediateDirectories: true)
            try Data("ancienne lecture".utf8).write(to: aiNew.appendingPathComponent("ovisocr2-0.md"))

            let importer = DocumentImporter(storage: model.storage, database: model.database)
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
            }

            // L'arrivée reste intacte.
            XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: plan.newDocumentId), [4: "ancienne donnée"])
            XCTAssertEqual(try String(contentsOf: aiNew.appendingPathComponent("ovisocr2-0.md")), "ancienne lecture")
            // P2 n°4 : la donnée de l'ancienne version n'est ni écrasée ni perdue — mise de côté
            // dans « Conflits-remplacement », sous le support injecté du harnais.
            let kept = root.appendingPathComponent("Conflits-remplacement").appendingPathComponent(doc.id, isDirectory: true)
            let draftsAside = kept.appendingPathComponent("Brouillons").appendingPathComponent(doc.id + ".json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: draftsAside.path), "brouillons de l'ancienne version gardés")
            XCTAssertEqual(try NoteDraftStore.decode(Data(contentsOf: draftsAside)), [0: "brouillon 0", 1: "brouillon 1"])
            XCTAssertEqual(try String(contentsOf: kept.appendingPathComponent("Lectures-IA")
                .appendingPathComponent("ovisocr2-0.md")), "page 0", "lecture IA de l'ancienne version gardée")
            // Le rapport, sans cible en place, suit normalement le document : le dossier « Rapport »
            // du conflit n'existe pas et la donnée mise de côté a quitté sa place d'origine.
            XCTAssertFalse(FileManager.default.fileExists(atPath: kept.appendingPathComponent("Rapport").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: NoteDraftStore.shared.url(documentId: doc.id).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: DocumentAnalysisService.folder
                .appendingPathComponent(doc.id, isDirectory: true).path), "dossier lectures IA vidé par les déplacements")
            // Le rapport vu par l'utilisateur compte le conflit, une seule fois (consommation unique).
            XCTAssertEqual(PageShift.consumeReplacementConflicts(for: doc.id), 2)
            XCTAssertEqual(PageShift.consumeReplacementConflicts(for: doc.id), 0)
            // La bascule finit comme prévu : base et journal consommés.
            XCTAssertNil(try model.database.document(id: doc.id))
            XCTAssertNotNil(try model.database.document(id: plan.newDocumentId))
            XCTAssertFalse(journalExists(root))
        }
    }

    /// N1 (revue R2) — bascule directe : la lecture IA du nouveau PDF est relancée **après** la
    /// levée de la réservation du nouvel identifiant. Dans la version P2 n°2, l'appel se trouvait
    /// avant la levée (`completeReplacement` finit par retirer le journal, dernier gardien) : la
    /// relance était refusée à chaque fois, et en reprise au lancement rien ne la relançait.
    func testDirectReplacementRestartsTheAIScanAfterTheReservationIsLifted() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            DocumentScan.started = []
            DocumentScan.startedWhileReserved = []
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId)
            }
            XCTAssertEqual(DocumentScan.started, [model.storage.url(for: plan.newDocumentId).path],
                           "une seule relance, pour le nouveau document")
            XCTAssertEqual(DocumentScan.startedWhileReserved, [false],
                           "la relance n'est plus faite sous la réservation")
        }
    }

    /// N1 (revue R2) — reprise au lancement : la lecture IA du nouveau PDF part après la levée
    /// de la réservation, donc n'est plus refusée par le gardien des tâches IA.
    func testRecoveredReplacementRestartsTheAIScanAfterTheReservationIsLifted() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let (plan, _) = try replacementPlan(root, pages: 3)
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            let restarted = try AppModel(root: root)
            DocumentScan.started = []
            DocumentScan.startedWhileReserved = []
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            XCTAssertEqual(DocumentScan.started, [restarted.storage.url(for: plan.newDocumentId).path],
                           "la reprise relance la lecture IA du document")
            XCTAssertEqual(DocumentScan.startedWhileReserved, [false],
                           "la relance n'est plus faite sous la réservation")
        }
    }

    /// N2 (revue R2) — fusion (l'identifiant d'arrivée existe déjà) : quand les deux versions ont
    /// un dessin d'encre sur la même page, le dessin du livre remplacé reste (règle P3 n°9) et
    /// celui du survivant est mis de côté dans `Conflits-remplacement/<ancien identifiant>/Encre/`,
    /// tel quel, jamais écrasé — rien n'est abandonné en silence.
    func testInkCollisionInAFusionIsKeptAside() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            // Le document d'arrivée existe déjà (la même version du cours avait été importée) :
            // la bascule SQL est une fusion. Un dessin du survivant sur la page 1, disputée
            // (le seed pose déjà celui du remplacé sur la même page).
            try model.database.save(LibraryDocument(id: plan.newDocumentId, title: doc.title,
                                                    originalFileName: doc.originalFileName, pageCount: 3, fileSize: 2))
            let survivorInk = Data([3, 4, 5])
            try model.database.save(InkDrawing(documentId: plan.newDocumentId, pageIndex: 1, data: survivorInk), isEmpty: false)

            let importer = DocumentImporter(storage: model.storage, database: model.database)
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId,
                                     asideCorrections: PageShift.asideCorrections,
                                     asideInk: PageShift.asideInkDrawing)
            }
            // La page disputée garde le dessin du remplacé (seed)…
            XCTAssertEqual(try model.database.inkDrawing(documentId: plan.newDocumentId, pageIndex: 1)?.data, Data([1, 2, 3]),
                           "le dessin du livre remplacé reste sur la page")
            // …et celui du survivant est de côté, octet pour octet, dans le dossier des conflits.
            let inkAside = root.appendingPathComponent("Conflits-remplacement").appendingPathComponent(doc.id, isDirectory: true)
                .appendingPathComponent("Encre").appendingPathComponent("page-1.ink")
            XCTAssertEqual(try Data(contentsOf: inkAside), survivorInk, "le dessin perdant est mis de côté, jamais écrasé")
            XCTAssertEqual(CorrectionAsideStore.shared.consumeTally(documentId: doc.id).conflicts, 1,
                           "la perte de côté est comptée pour le rapport")
        }
    }

    /// N4 (revue R2) : un journal refusé (ici : fichier source altéré) laissait l'app bloquée sur
    /// « Réessayer la reprise », qui rejoue le même refus à chaque fois — une seule action, une
    /// impasse. Le journal peut être mis de côté : fichier déplacé (jamais effacé, jamais
    /// écrasé), l'app démarre normalement, la mise à jour reste relançable depuis l'état d'origine.
    func testARejectedJournalCanBeSetAsideToRestart() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, _) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            // Leurre : PDF honnête, empreinte différente de celle du journal → refus à la reprise.
            let decoy = root.appendingPathComponent("leurre-" + UUID().uuidString + ".pdf")
            try writePDF(decoy, pages: 3)
            defer { try? FileManager.default.removeItem(at: decoy) }
            var tampered = try journal(root)
            tampered.newSourcePath = decoy.path
            try JSONEncoder().encode(tampered).write(to: root.appendingPathComponent(journalFile))
            let restarted = try AppModel(root: root)
            PageShift.reconcile(restarted)
            XCTAssertNotNil(restarted.storageRecoveryError, "le refus bloque d'abord (P2 n°3)")

            // Pendant une sauvegarde : la mise de côté est refusée (le journal y est encore jouable).
            LibraryBackupService.inProgress = true
            PageShift.setAsideRejectedJournal(restarted)
            LibraryBackupService.inProgress = false
            XCTAssertTrue(journalExists(root), "garde réciproque : rien n'est déplacé pendant une sauvegarde")
            XCTAssertNotNil(restarted.storageRecoveryError)

            // La mise de côté : le fichier part renommé dans « journaux-refusés », jamais effacé ;
            // la reprise est suspendue sans erreur et l'app démarre normalement.
            PageShift.setAsideRejectedJournal(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            XCTAssertFalse(journalExists(root))
            let refused = root.appendingPathComponent("Conflits-remplacement").appendingPathComponent("journaux-refusés", isDirectory: true)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: refused, includingPropertiesForKeys: nil).count, 1)
            // Sans journal en place, un nouvel appel ne fait rien (aucun dossier en plus).
            PageShift.setAsideRejectedJournal(restarted)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: refused, includingPropertiesForKeys: nil).count, 1)

            // Le démarrage suivant ne rejoue rien, la bibliothèque est intacte et la mise à jour
            // de ce cours reste relançable (le même journal authentique, remis en place, finit).
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try assertUnshifted(restarted, doc, card)
            try writeReplacementJournal(root, oldId: doc.id, oldCount: doc.pageCount, oldSize: doc.fileSize, plan: plan)
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
        }
    }
}
