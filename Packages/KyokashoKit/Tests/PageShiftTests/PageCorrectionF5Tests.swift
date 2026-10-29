// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import XCTest

extension PageShiftRecoveryTests {
    func testF5PrintedNumbersRefreshAfterAdditionAndRecovery() async throws {
        for interrupted in [false, true] {
            try await withFixture { model, doc, root in
                _ = try seed(model, doc)
                try await PageShift.removePages(model, document: doc, pages: [0])
                PrintedPageNumbers.set(try model.database.printedNumbers()) // Même état que RemovePagesView.
                defer { PrintedPageNumbers.set([:]) }
                let removed = try XCTUnwrap(model.database.document(id: doc.id))
                let merged = root.appendingPathComponent("merged.pdf")
                try writePDF(merged, pages: 2)
                if interrupted { PageShift.checkpoint = { if $0 == "database.after" { throw PowerLoss.simulated } } }
                do { _ = try await PageShift.apply(model, document: removed, merged: merged, offset: 0, newCount: 2) }
                catch { if !interrupted { throw error } }
                PageShift.checkpoint = nil
                if interrupted { PageShift.reconcile(model) }
                XCTAssertEqual(PrintedPageNumbers.numbers(for: doc.id, pageCount: 2), [2, nil])
                XCTAssertEqual(try model.database.document(id: doc.id)?.pageLabel(0), "2")
            }
        }
    }


}
