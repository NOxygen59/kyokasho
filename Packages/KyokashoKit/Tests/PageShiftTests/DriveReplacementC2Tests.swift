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

    /// Fichiers déjà présents chez l'identifiant d'arrivée (version re-importée après avoir été
    /// retirée) : jamais écrasés, source gardée en secours, conflit signalé, bascule finie quand même.
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
            // La source est gardée sous l'ancien identifiant, jamais effacée en passant.
            XCTAssertEqual(NoteDraftStore.shared.drafts(documentId: doc.id), [0: "brouillon 0", 1: "brouillon 1"])
            XCTAssertEqual(try String(contentsOf: DocumentAITextStore.folder.appendingPathComponent(doc.id, isDirectory: true).appendingPathComponent("ovisocr2-0.md")), "page 0")
            // Le reste suit : journal consommé.
            XCTAssertNil(try model.database.document(id: doc.id))
            XCTAssertFalse(journalExists(root))
        }
    }
}
