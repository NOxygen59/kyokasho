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
        let notes = ReleaseNotes.notes(for: "1.4.0")
        XCTAssertFalse(notes?.added.isEmpty ?? true)
        XCTAssertNil(ReleaseNotes.notes(for: "0.0"))
    }

    /// Historique : de la 0.1.0 à la version en cours, 40 versions publiées et les builds de test intercalées.
    func testHistoryIsCompleteAndOrdered() {
        let all = ReleaseNotes.all
        XCTAssertEqual(all.first?.version, "1.4.0")
        XCTAssertEqual(all.last?.version, "0.1.0")
        XCTAssertEqual(all.filter(\.published).count, 40)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.map(\.date), all.map(\.date).sorted(by: >))
        XCTAssertTrue(all.allSatisfy { !($0.added + $0.fixed + $0.removed).isEmpty })
        XCTAssertEqual(ReleaseNotes.notes(for: "1.4.0"), ReleaseNotes.current)
    }
}
