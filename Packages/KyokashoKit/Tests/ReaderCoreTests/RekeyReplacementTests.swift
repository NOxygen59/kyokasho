// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import XCTest
@testable import ReaderCore

/// C2.1 (Lot C2, fiche f85d0c0) — le remplacement d'un cours (nouvelle version d'un PDF Drive)
/// ne doit jamais servir l'OCR de l'ancienne version pour la nouvelle : le cache `(documentId,
/// pageIndex, engine)` porte l'ancien contenu, et le rognage automatique (calculé sur les images
/// d'avant) serait faux. Décision **DEC-C1 = A** : tout l'OCR est relu, le rognage automatique
/// repart de zéro, dans la même transaction que la bascule. Test des **deux** branches de
/// `rekeyDocument` (renommage pur ; fusion dans un identifiant déjà présent).
final class RekeyReplacementTests: XCTestCase {
    private var db: AppDatabase!

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
    }

    override func tearDownWithError() throws {
        db = nil
    }

    /// Un OCR en cache plus un rognage automatique, comme au moment d'un remplacement réel.
    private func seedOCR(documentId: String) throws {
        try db.save(OCRResultRecord(documentId: documentId, pageIndex: 0, engine: "vision",
                                     json: Data("boîtes anciennes".utf8), durationMs: 1))
        try db.save(OCRResultRecord(documentId: documentId, pageIndex: 1, engine: "ppocr5",
                                     json: Data("boîtes anciennes 2".utf8), durationMs: 2))
        // Deux pages avec moteur différent : le cache n'est pas rangé par moteur unique.
        try db.save(OCRResultRecord(documentId: documentId, pageIndex: 1, engine: "vision",
                                     json: Data("boîtes anciennes 3".utf8), durationMs: 3))
        try db.save(PageTransform(documentId: documentId, pageIndex: 0,
                                  autoCrop: .init(x: 0.1, y: 0.2, width: 0.7, height: 0.6)))
        try db.save(PageTransform(documentId: documentId, pageIndex: 1, rotation: 90,
                                  autoCrop: .init(x: 0, y: 0, width: 1, height: 1)))
    }

    private func assertOCRPurged(documentId: String, rotationKept: Bool = true,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let leftovers = try db.ocrResults(documentId: documentId)
        XCTAssertTrue(leftovers.isEmpty, file: file, line: line)
        // DEC-C1 = A porte aussi le rognage automatique ; la rotation (choix manuel) reste.
        let transforms = try db.pageTransforms(documentId: documentId)
        XCTAssertNotNil(transforms[0], file: file, line: line)
        XCTAssertNil(transforms[0]?.autoCrop, file: file, line: line)
        if rotationKept {
            XCTAssertEqual(transforms[1]?.rotation, 90, file: file, line: line)
            XCTAssertNil(transforms[1]?.autoCrop, file: file, line: line)
        }
    }

    /// Branche « renommage » : `UPDATE document SET id = ?` et le grand verrou de l'utilisateur,
    /// le remplacement Drive ordinaire. L'erreur signalée par le lot C2.1 : la clé de cache
    /// `(documentId, pageIndex, engine)` suivait le renommage et servait l'ancienne version.
    func testRekeyToFreeIdClearsOCRAndAutoCropInSameTransaction() throws {
        try db.save(LibraryDocument(id: "old", title: "Cours", originalFileName: "c.pdf", pageCount: 3, fileSize: 1))
        try db.save(Highlight(documentId: "old", pageIndex: 0, rects: [PageRect(x: 1, y: 1, width: 1, height: 1)], color: .yellow, text: "x"))
        try seedOCR(documentId: "old")

        var updated = try XCTUnwrap(db.document(id: "old"))
        updated.id = "new"
        updated.pageCount = 4
        try db.rekeyDocument(from: "old", to: updated)

        XCTAssertNil(try db.document(id: "old"))
        try assertOCRPurged(documentId: "new")
        // Le reste suit (cascade `ON UPDATE`), comme avant : l'effacement est ciblé.
        XCTAssertEqual(try db.highlights(documentId: "new").count, 1)

        // Idempotence des deux effacements si la bascule est rejouée sur un document déjà en place.
        try db.save(OCRResultRecord(documentId: "new", pageIndex: 0, engine: "vision", json: Data("nouveau".utf8), durationMs: 1))
        var again = try XCTUnwrap(db.document(id: "new"))
        again.id = "new"
        try db.rekeyDocument(from: "new", to: again)
        XCTAssertEqual(try db.ocrResults(documentId: "new").count, 1,
                       "même identifiant : contenu inchangé, le cache n'est pas effacé")
    }

    /// Branche « fusion » : le document cible existe déjà (la même version du cours avait été
    /// importée). Annotations rattachées, et **tous** les résultats OCR (celui de l'ancien
    /// identifiant, emporté par la suppression en cascade, et celui du survivant) partent.
    /// P3 n°9 (revue R2) : la rotation/coupure manuelle du document remplacé ne se perd pas
    /// (elle gagne sur la page en conflit) et le survivant garde titre, catégorie, réglages et
    /// position de lecture — seules les mesures du fichier réel suivent.
    func testRekeyToExistingDocumentClearsOCROfBothSides() throws {
        try db.save(LibraryDocument(id: "old", title: "Cours", originalFileName: "c.pdf", pageCount: 3, fileSize: 1))
        var survivor = LibraryDocument(id: "new", title: "Cours", originalFileName: "c.pdf", pageCount: 4, fileSize: 2)
        survivor.category = .textbook
        survivor.lastPageIndex = 2
        try db.save(survivor)
        try db.save(Highlight(documentId: "old", pageIndex: 0, rects: [PageRect(x: 1, y: 1, width: 1, height: 1)], color: .yellow, text: "ancien"))
        try db.save(Highlight(documentId: "new", pageIndex: 0, rects: [PageRect(x: 2, y: 2, width: 1, height: 1)], color: .green, text: "survivant"))
        // Conflit de pageTransform : page 0 double (le remplacé gagne), page 1 gardée du survivant.
        try seedOCR(documentId: "old")
        try seedOCR(documentId: "new")
        try db.save(PageTransform(documentId: "new", pageIndex: 1, rotation: 180))

        var updated = try XCTUnwrap(db.document(id: "old"))
        updated.id = "new"
        updated.pageCount = 3
        updated.fileSize = 42
        try db.rekeyDocument(from: "old", to: updated)

        XCTAssertNil(try db.document(id: "old"))
        try assertOCRPurged(documentId: "new")
        // P3 n°9 : manuel du remplacé sur les pages en conflit (90, pas 180…)…
        let transforms = try db.pageTransforms(documentId: "new")
        XCTAssertEqual(transforms[0]?.rotation, 0, "page en double : la ligne du document remplacé est celle qui reste")
        XCTAssertEqual(transforms[1]?.rotation, 90, "la rotation du remplacé gagne, pas celle du survivant")
        // …et la fiche du survivant est intacte, mesures du fichier réel mises à part.
        let kept = try XCTUnwrap(db.document(id: "new"))
        XCTAssertEqual(kept.title, "Cours")
        XCTAssertEqual(kept.category, .textbook, "catégorie du survivant")
        XCTAssertEqual(kept.lastPageIndex, 2, "position de lecture du survivant")
        XCTAssertEqual(kept.pageCount, 3, "le compte réel du PDF qui reste")
        XCTAssertEqual(kept.fileSize, 42, "la taille du fichier réel")
        XCTAssertNil(kept.driveRevision, "pas de révision Drive ici : jamais écrasée par une valeur absente")
        // Les surlignages des deux versions sont rattachés, comme avant (OR IGNORE garde le survivant).
        XCTAssertEqual(try db.highlights(documentId: "new").count, 2)
    }
}
