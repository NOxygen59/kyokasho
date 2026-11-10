// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import PDFKit
import ReaderCore
import ReviewKit
import XCTest

// Décision DEC-C3 (10/11/2026) : quand un cours Drive est remplacé, les lignes corrigées à la
// main de l'ancienne version ne sont plus perdues avec le cache OCR. Elles sont écrites de côté
// (avant l'effacement, jamais écrasées, dans « Corrections-remplacement/<nouvel identifiant>/ »),
// puis remises au moment où le nouveau résultat OCR est enregistré (`OCRService.store`) pour une
// ligne relue dont le texte est identique au texte lu d'origine — jamais pour un texte différent.
// Tout vit dans le dossier temporaire du harnais (aucune bibliothèque réelle).
extension PageShiftRecoveryTests {
    /// Résultat OCR d'une page : `corrected` donne, par ligne, le texte corrigé à la main
    /// (l'opération réelle de l'app, qui pose `originalText`).
    func ocrPage(lines: [String], corrected: [Int: String] = [:], engine: String = "vision") -> OCRPage {
        let box = NormBox(x: 0, y: 0, w: 1, h: 1)
        var page = OCRPage(engine: engine, lines: [], durationMs: 1)
        page.lines = lines.enumerated().map { index, text in
            var line = OCRLine(text: text, box: box,
                               charBoxes: CharacterLayout.proportional(text, in: box, vertical: false),
                               measuredCharBoxes: true, vertical: false, confidence: 0.9)
            if let correction = corrected[index] { line = line.acceptingCorrection(correction) }
            return line
        }
        return page
    }

    func correctionsFolder(_ root: URL, _ newId: String) -> URL {
        root.appendingPathComponent("Corrections-remplacement").appendingPathComponent(newId, isDirectory: true)
    }

    /// La bascule ne perd plus les corrections manuelles : elles sortent du cache OCR avant son
    /// effacement, écrites de côté sous l'identifiant du document relu ensuite.
    func testManualCorrectionsAreWrittenAsideBeforeTheRekey() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            // Une correction à la main réelle : « 相対湿度 » relu par l'OCR, corrigé en « 相対湿度計 ».
            let page = ocrPage(lines: ["手順", "相対湿度"], corrected: [1: "相対湿度計"])
            try model.database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "vision",
                                                    json: try JSONEncoder().encode(page), durationMs: 1))
            // Résultat sans correction : rien à mettre de côté, et un résultat qui ne décode pas
            // (écriture ancienne) ne doit pas arrêter la bascule non plus.
            try model.database.save(OCRResultRecord(documentId: doc.id, pageIndex: 1, engine: "vision",
                                                    json: Data("résultat non décodable".utf8), durationMs: 1))
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId,
                                     asideCorrections: PageShift.asideCorrections)
            }
            try verifyReplacement(model, root: root, old: doc, card: card, plan: plan)
            // La correction est de côté sous le nouvel identifiant, page et moteur d'origine,
            // texte lu d'origine et texte corrigé.
            let pending = CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            XCTAssertEqual(pending.map { $0.entry }, [KeptCorrection(original: "相対湿度", corrected: "相対湿度計")])
            XCTAssertFalse(FileManager.default.fileExists(atPath: correctionsFolder(root, doc.id).path),
                           "le dossier porte l'identifiant du document relu ensuite, pas l'ancien")
        }
    }

    /// Remise : une ligne relue identique au texte lu d'origine reçoit la correction (comme une
    /// correction faite à la main), une ligne différente n'est jamais retouchée ; la correction
    /// appliquée quitte le dossier, les autres restent.
    func testKeptCorrectionIsAppliedOnIdenticalLineOnly() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let page = ocrPage(lines: ["手順", "相対湿度"], corrected: [1: "相対湿度計"])
            try model.database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "vision",
                                                    json: try JSONEncoder().encode(page), durationMs: 1))
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                     driveRevision: "rév. 2", replacingInto: plan.newDocumentId,
                                     asideCorrections: PageShift.asideCorrections)
            }
            // Une autre correction de côté (mise pour la même page et le même moteur) qui ne
            // trouvera pas sa ligne : elle doit rester après la remise.
            try CorrectionAsideStore.shared.keep(pageIndex: 0, engine: "vision",
                                                 entries: [KeptCorrection(original: "未読の行", corrected: "既読の行")],
                                                 documentId: plan.newDocumentId, sourceDocumentId: doc.id)

            // Le nouveau PDF est relu (nouveau résultat OCR enregistré) : la ligne relue porte
            // le texte lu d'origine de la correction → la correction s'applique.
            let reread = ocrPage(lines: ["相対湿度", "別の行"])
            try await model.ocr.store(reread, documentId: plan.newDocumentId, pageIndex: 0)
            let cached: OCRPage? = await model.ocr.cached(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            let stored = try XCTUnwrap(cached)
            XCTAssertEqual(stored.lines.first?.text, "相対湿度計", "correction remise")
            XCTAssertEqual(stored.lines.first?.originalText, "相対湿度", "marquée comme corrigée à la main")
            XCTAssertEqual(stored.lines.last?.text, "別の行", "la ligne différente n'est jamais retouchée")
            var pending = CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            XCTAssertEqual(pending.map { $0.entry }, [KeptCorrection(original: "未読の行", corrected: "既読の行")],
                           "la correction appliquée est retirée du dossier, les autres restent")

            // Une relecture où la même ligne est relue sans son texte d'origine : rien.
            let otherRead = ocrPage(lines: ["湿度を測る"])
            try await model.ocr.store(otherRead, documentId: plan.newDocumentId, pageIndex: 0)
            let cachedSecond: OCRPage? = await model.ocr.cached(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            let secondStored = try XCTUnwrap(cachedSecond)
            XCTAssertEqual(secondStored.lines.map { $0.text }, ["湿度を測る"], "pas de remise sur une ligne différente")
            pending = CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            XCTAssertEqual(pending.map { $0.entry }, [KeptCorrection(original: "未読の行", corrected: "既読の行")],
                           "la correction restante attend toujours sa ligne")
        }
    }

    /// Coupure pendant la bascule : la mise de côté a déjà eu lieu (avant le journal et la
    /// bascule SQL), la reprise au lancement n'en refait **jamais** une seconde copie, et la
    /// correction remise après la reprise s'applique une seule fois.
    func testCutDuringTheRekeyKeepsTheCorrectionsAsideOnce() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let (plan, newPDF) = try replacementPlan(root, pages: 3)
            let modesDone = trackModeKeys(doc.id, plan.newDocumentId)
            defer { modesDone() }
            ReaderToolModeStore().update(documentId: doc.id) { $0.drawing = true; $0.panelMode = "floating" }
            let page = ocrPage(lines: ["手順", "相対湿度"], corrected: [1: "相対湿度計"])
            try model.database.save(OCRResultRecord(documentId: doc.id, pageIndex: 0, engine: "vision",
                                                    json: try JSONEncoder().encode(page), durationMs: 1))
            let importer = DocumentImporter(storage: model.storage, database: model.database)
            PageShift.checkpoint = { if $0 == "cards.after" { throw PowerLoss.simulated } }
            await assertThrowsAsync({
                try await PageShift.withDriveReplacement(model, documentId: doc.id, replacement: plan) {
                    try importer.replace(documentId: doc.id, withFileAt: newPDF,
                                         driveRevision: "rév. 2", replacingInto: plan.newDocumentId,
                                         asideCorrections: PageShift.asideCorrections)
                }
            })
            PageShift.checkpoint = nil
            // Le cache OCR de l'ancienne version est déjà effacé (bascule SQL passée) ; la mise
            // de côté, faite avant, garde la correction.
            XCTAssertTrue(try model.database.ocrResults(documentId: doc.id).isEmpty)
            let before = CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            XCTAssertEqual(before.map { $0.entry }, [KeptCorrection(original: "相対湿度", corrected: "相対湿度計")])

            // Reprise au lancement : la bascule finit ; le dossier de secours n'a pas doublé.
            let restarted = try AppModel(root: root)
            PageShift.reconcile(restarted)
            XCTAssertNil(restarted.storageRecoveryError)
            try verifyReplacement(restarted, root: root, old: doc, card: card, plan: plan)
            let after = CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            XCTAssertEqual(after.map { $0.entry }, [KeptCorrection(original: "相対湿度", corrected: "相対湿度計")],
                           "une reprise ne copie pas deux fois la même correction")

            // Puis la page du nouveau PDF est relue : une seule remise.
            try await restarted.ocr.store(ocrPage(lines: ["相対湿度"]), documentId: plan.newDocumentId, pageIndex: 0)
            let cached: OCRPage? = await restarted.ocr.cached(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision")
            let stored = try XCTUnwrap(cached)
            XCTAssertEqual(stored.lines.first?.text, "相対湿度計")
            XCTAssertTrue(CorrectionAsideStore.shared.pendingCorrections(documentId: plan.newDocumentId, pageIndex: 0, engine: "vision").isEmpty,
                          "la correction appliquée est retirée du dossier")
        }
    }
}
