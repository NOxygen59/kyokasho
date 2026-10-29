// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

final class PageMappingTests: XCTestCase {
    func testRemovalOfOnePageRangeAndScatteredPages() throws {
        XCTAssertEqual(try PageMapping.removal(oldCount: 5, removing: [2]).targets, [0, 1, nil, 2, 3])
        XCTAssertEqual(try PageMapping.removal(oldCount: 6, removing: [1, 2, 3]).targets, [0, nil, nil, nil, 1, 2])
        let scattered = try PageMapping.removal(oldCount: 6, removing: [0, 3, 5])
        XCTAssertEqual(scattered.targets, [nil, 0, 1, nil, 2, nil])
        XCTAssertEqual(scattered.newCount, 3)
        XCTAssertEqual(scattered.removed, [0, 3, 5])
        XCTAssertEqual(scattered.inserted, [])
    }

    func testRemovalOfFirstLastAndAllButOne() throws {
        XCTAssertEqual(try PageMapping.removal(oldCount: 3, removing: [0]).targets, [nil, 0, 1])
        XCTAssertEqual(try PageMapping.removal(oldCount: 3, removing: [2]).targets, [0, 1, nil])
        XCTAssertEqual(try PageMapping.removal(oldCount: 3, removing: [0, 2]).targets, [nil, 0, nil])
    }

    func testInvalidSelectionsAreRefusedBeforeAnyEffect() {
        XCTAssertThrowsError(try PageMapping.removal(oldCount: 3, removing: [])) { XCTAssertEqual($0 as? PageMapping.Failure, .emptySelection) }
        XCTAssertThrowsError(try PageMapping.removal(oldCount: 3, removing: [0, 1, 2])) { XCTAssertEqual($0 as? PageMapping.Failure, .removesEverything) }
        XCTAssertThrowsError(try PageMapping.removal(oldCount: 3, removing: [3])) { XCTAssertEqual($0 as? PageMapping.Failure, .pageOutOfRange(3)) }
        XCTAssertThrowsError(try PageMapping.removal(oldCount: 3, removing: [-1])) { XCTAssertEqual($0 as? PageMapping.Failure, .pageOutOfRange(-1)) }
        XCTAssertThrowsError(try PageMapping.insertion(oldCount: 3, inserted: 0, at: 0))
        XCTAssertThrowsError(try PageMapping.insertion(oldCount: 3, inserted: 2, at: 4))
    }

    func testRawTargetsMustBeUniqueOrderedAndInRange() {
        XCTAssertThrowsError(try PageMapping(oldCount: 3, newCount: 3, targets: [0, 0, 1]))   // doublon
        XCTAssertThrowsError(try PageMapping(oldCount: 3, newCount: 3, targets: [1, 0, 2]))   // ordre inversé
        XCTAssertThrowsError(try PageMapping(oldCount: 3, newCount: 2, targets: [0, 1, 2]))   // hors du nouveau total
        XCTAssertThrowsError(try PageMapping(oldCount: 3, newCount: 3, targets: [0, 1]))      // page oubliée
        XCTAssertThrowsError(try PageMapping(oldCount: 2, newCount: 1, targets: [nil, nil]))  // plus aucune page
    }

    func testInsertionMatchesTheOldOffsetShift() throws {
        let start = try PageMapping.insertion(oldCount: 3, inserted: 2, at: 0)
        XCTAssertEqual(start.targets, [2, 3, 4])
        XCTAssertEqual(start.inserted, [0, 1])
        XCTAssertEqual(try PageMapping.insertion(oldCount: 3, inserted: 1, at: 1).targets, [0, 2, 3])
        XCTAssertEqual(try PageMapping.insertion(oldCount: 3, inserted: 1, at: 3).targets, [0, 1, 2])
    }

    func testDecodingRevalidatesAnAlteredJournal() throws {
        let good = try JSONEncoder().encode(PageMapping.removal(oldCount: 4, removing: [1]))
        XCTAssertEqual(try JSONDecoder().decode(PageMapping.self, from: good).targets, [0, nil, 1, 2])
        let altered = Data(#"{"oldCount":3,"newCount":3,"targets":[2,1,0]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PageMapping.self, from: altered))
    }

    func testCompositionFollowsAPageThroughSeveralEdits() throws {
        let removal = try PageMapping.removal(oldCount: 5, removing: [1])        // [0, nil, 1, 2, 3]
        let insertion = try PageMapping.insertion(oldCount: 4, inserted: 2, at: 0)
        let both = try removal.then(insertion)
        XCTAssertEqual(both.targets, [2, nil, 3, 4, 5])
        XCTAssertEqual(both.inserted, [0, 1])
        XCTAssertThrowsError(try removal.then(PageMapping.removal(oldCount: 5, removing: [0])))
    }
}
