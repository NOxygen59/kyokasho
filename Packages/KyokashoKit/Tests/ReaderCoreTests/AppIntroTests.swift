// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// Visite guidée et nouveautés.
final class AppIntroTests: XCTestCase {
    func testNewUserSeesTourOnce() {
        XCTAssertEqual(IntroGate.decide(tourSeen: false, lastSeen: nil, current: "1.3.2 (65)", hasNotes: true, hasLibrary: false), .tour)
        XCTAssertEqual(IntroGate.decide(tourSeen: true, lastSeen: "1.3.2 (65)", current: "1.3.2 (65)", hasNotes: true, hasLibrary: true), .none)
    }

    func testExistingUserSeesWhatsNewAfterEachUpdate() {
        XCTAssertEqual(IntroGate.decide(tourSeen: false, lastSeen: nil, current: "1.3.2 (65)", hasNotes: true, hasLibrary: true), .whatsNew)
        XCTAssertEqual(IntroGate.decide(tourSeen: true, lastSeen: "1.3.2 (64)", current: "1.3.2 (65)", hasNotes: true, hasLibrary: true), .whatsNew)
        XCTAssertEqual(IntroGate.decide(tourSeen: true, lastSeen: "1.3.2 (64)", current: "1.4.0 (70)", hasNotes: false, hasLibrary: true), .none)
    }

    func testContentIsFilled() {
        XCTAssertGreaterThanOrEqual(AppTour.steps.count, 6)
        XCTAssertTrue(AppTour.steps.allSatisfy { !$0.how.isEmpty && !$0.why.isEmpty })
        XCTAssertEqual(Set(AppTour.steps.map(\.id)).count, AppTour.steps.count)
        let notes = ReleaseNotes.notes(for: "1.3.2")
        XCTAssertFalse(notes?.added.isEmpty ?? true)
        XCTAssertNil(ReleaseNotes.notes(for: "0.0"))
    }
}
