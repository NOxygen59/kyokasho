// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest

extension PageShiftRecoveryTests {
    func testF6CopiesFollowDriveReplacementAcrossRestartAndDeletion() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            try await PageShift.removePages(model, document: doc, pages: [0])
            let archive = try archiveId(model, doc)
            XCTAssertGreaterThan(PageShift.copiesSize(documentId: doc.id), 0)
            let source = root.appendingPathComponent("drive.pdf")
            try writePDF(source, pages: 3)
            let updated = try DocumentImporter(storage: model.storage, database: model.database).replace(documentId: doc.id, withFileAt: source)
            let restarted = try AppModel(root: root)
            PageShift.reconcile(restarted) // Simule une interruption juste après le rekey SQL.
            XCTAssertGreaterThan(PageShift.copiesSize(documentId: updated.id), 0)
            XCTAssertEqual(PageShift.copiesSize(documentId: updated.id), PageShift.copiesSize())
            XCTAssertEqual(PageShift.copiesSize(documentId: doc.id), 0)
            XCTAssertThrowsError(try restarted.database.restorationPlan(documentId: updated.id, archiveId: archive))
            try restarted.database.deleteDocument(id: updated.id)
            PageShift.removeCopies(documentId: updated.id)
            XCTAssertEqual(PageShift.copiesSize(), 0)
        }
    }

}
