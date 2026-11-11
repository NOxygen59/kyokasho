// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import ReaderCore

/// FEAT-AIDE : l'aide aux gestes ne montre que ce que le document propose, et ses références au code restent vraies.
final class ReaderGestureHelpTests: XCTestCase {
    private func context(text: Bool = true, annotations: Bool = true, continuous: Bool = false, rtl: Bool = false,
                         doubleTap: Bool = true) -> ReaderGestureHelp.Context {
        .init(textAnalysis: text, annotations: annotations, continuousScroll: continuous, rightToLeft: rtl,
              doubleTapZoom: doubleTap)
    }

    func testAPDFShowsBetweenFiveAndEightGesturesInReadingOrder() {
        let items = ReaderGestureHelp.items(context())
        XCTAssertEqual(items.map(\.kind), [.turnPage, .bars, .zoom, .selectText, .lookup, .highlight, .draw])
        XCTAssertTrue((5...8).contains(items.count))
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        for item in items {
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.detail.isEmpty)
            XCTAssertFalse(item.icon.isEmpty)
        }
    }

    func testAComicArchiveOnlyShowsWhatItCanDo() {
        // CBZ : ni texte, ni dictionnaire, ni barre d'outils (`DocumentCapabilities`).
        let items = ReaderGestureHelp.items(context(text: false, annotations: false))
        XCTAssertEqual(items.map(\.kind), [.turnPage, .bars, .zoom])
    }

    func testTextsFollowTheReaderSettings() {
        func detail(_ kind: ReaderGestureHelp.Item.Kind, _ c: ReaderGestureHelp.Context) -> String {
            ReaderGestureHelp.items(c).first { $0.kind == kind }?.detail ?? ""
        }
        // Sens de lecture, défilement continu et double toucher changent ce qui est vrai : le texte suit.
        XCTAssertNotEqual(detail(.turnPage, context()), detail(.turnPage, context(rtl: true)))
        XCTAssertNotEqual(detail(.turnPage, context()), detail(.turnPage, context(continuous: true)))
        XCTAssertEqual(detail(.turnPage, context(continuous: true)), detail(.turnPage, context(continuous: true, rtl: true)))
        XCTAssertNotEqual(detail(.zoom, context()), detail(.zoom, context(doubleTap: false)))
    }

    /// Garde de source : chaque geste décrit est toujours branché dans le lecteur. Si un de ces noms disparaît,
    /// l'aide doit être relue avant de corriger ce test.
    func testEveryDescribedGestureStillExistsInTheReader() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        func read(_ path: String) throws -> String { try String(contentsOf: app.appendingPathComponent(path), encoding: .utf8) }
        let navigation = try read("Reader/ReaderController+Navigation.swift")
        for name in ["func handleSwipe(", "func handleTap(", "func handleDoubleTap(", "func handleLongPress(",
                     "func handleHover(", "barsVisible.toggle()", "if lookupMode {", "gesture.modifierFlags.contains(.shift)"] {
            XCTAssertTrue(navigation.contains(name), name)
        }
        XCTAssertTrue(try read("Reader/ReaderController+OCRHighlight.swift").contains("func handleHighlightPan("))
        XCTAssertTrue(try read("Reader/ReaderArrowKeys.swift").contains("forward ? reader.next() : reader.previous()"))
        let screen = try read("Reader/ReaderScreen.swift")
        for name in ["reader.lookupMode.toggle()", "private var restoreBarsButton", "private func pageArrow(left: Bool)",
                     "Picker(\"Couleur\", selection: $ocrHighlightColor)", "Button(\"Supprimer le surlignage\"",
                     "reader.setDrawing(!reader.isDrawing)",
                     // Point d'accès et feuille de l'aide.
                     "Button { sheet = .gestureHelp }", "case .gestureHelp: ReaderGestureHelpSheet("] {
            XCTAssertTrue(screen.contains(name), name)
        }
        XCTAssertTrue(try read("Reader/ReaderController+Display.swift").contains("doubleTap.isEnabled = s.doubleTapZoom"))
    }
}
