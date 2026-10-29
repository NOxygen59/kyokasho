// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest

extension PageShiftRecoveryTests {
    func testF4DriveReservationExcludesPagesAndReleasesOnFailure() async throws {
        try await withFixture { model, doc, root in
            _ = try seed(model, doc)
            await assertThrowsAsync {
                try await PageShift.withDriveReplacement(model, documentId: doc.id) {
                    await Task.yield() // Le remplacement a quitté le MainActor, comme l'importeur détaché.
                    XCTAssertTrue(PageShift.isBusy(doc.id))
                    XCTAssertTrue(PageShift.blocksAI(jobKey: "scan|" + doc.id))
                    XCTAssertFalse(PageShift.blocksAI(jobKey: "scan|other"))
                    await assertThrowsAsync { try await PageShift.removePages(model, document: doc, pages: [0]) }
                    await assertThrowsAsync {
                        try await PageShift.withDriveReplacement(model, documentId: doc.id) { XCTFail("deux remplacements") }
                    }
                    throw PowerLoss.simulated
                }
            }
            XCTAssertFalse(PageShift.isBusy(doc.id))
            XCTAssertEqual(try model.database.document(id: doc.id)?.pageCount, 2)
        }
    }
    func testF4PagesExcludeDriveAndRecheckIAAfterPDFBuild() async throws {
        try await withFixture { model, doc, root in
            let card = try seed(model, doc)
            let before = try pageState(model, doc, card)
            model.onDrain = {
                await self.assertThrowsAsync {
                    try await PageShift.withDriveReplacement(model, documentId: doc.id) { XCTFail("Drive pendant une suppression") }
                }
            }
            PageShift.checkpoint = { point in
                if point == "build.after" { AITaskCenter.shared.jobs = [.init(key: "scan|" + doc.id)] }
            }
            defer { AITaskCenter.shared.jobs = []; model.onDrain = nil }
            await assertThrowsAsync { try await PageShift.removePages(model, document: doc, pages: [0]) }
            XCTAssertEqual(try pageState(model, doc, card), before)
            XCTAssertFalse(PageShift.isBusy(doc.id))
        }
    }

}
