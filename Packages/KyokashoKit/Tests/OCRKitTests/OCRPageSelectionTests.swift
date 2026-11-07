// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

@testable import OCRKit
import XCTest

/// État de sélection OCR versionné (revue Codex de d87e048, R1 et §3) : un résultat demandé avant une intention plus
/// récente ne peut plus se redonner l'autorité d'être affiché, dans un sens comme dans l'autre.
final class OCRPageSelectionTests: XCTestCase {
    /// R1 : lecture Vision suspendue, choix NDLOCR dans le menu, puis retour de la lecture Vision.
    func testStaleVisionResultCannotReplaceExplicitNDLOCR() {
        var selection = OCRPageSelection()
        let ticket = selection.ticket(for: 3)
        selection.pin(OCREngineID.ndlocr, source: 3)
        XCTAssertFalse(selection.adopt(OCREngineID.vision, ticket: ticket))
        XCTAssertEqual(selection.selected[3], OCREngineID.ndlocr)
        XCTAssertEqual(selection.pinned[3], OCREngineID.ndlocr)
    }

    /// R1, sens inverse : ce n'est pas une question de rang des moteurs.
    func testStaleNDLOCRResultCannotReplaceExplicitVision() {
        var selection = OCRPageSelection()
        let ticket = selection.ticket(for: 3)
        selection.pin(OCREngineID.vision, source: 3)
        XCTAssertFalse(selection.adopt(OCREngineID.ndlocr, ticket: ticket))
        XCTAssertEqual(selection.selected[3], OCREngineID.vision)
    }

    /// Changement du réglage du moteur : la sélection est vide, mais une ancienne réponse n'est pas admise pour autant.
    func testResetMakesEveryOlderTicketStaleEvenWithAnEmptySelection() {
        var selection = OCRPageSelection()
        let ticket = selection.ticket(for: 0)
        selection.reset()
        XCTAssertNil(selection.selected[0])
        XCTAssertFalse(selection.adopt(OCREngineID.vision, ticket: ticket))
        XCTAssertNil(selection.selected[0])
        XCTAssertTrue(selection.adopt(OCREngineID.vision, ticket: selection.ticket(for: 0)))
    }

    /// §3 : consulter n'a pas d'effet ; une adoption acceptée périme les demandes plus anciennes de la même page,
    /// pas celles des autres pages (double page).
    func testAdoptionSupersedesOlderTicketsAndReadingHasNoEffect() {
        var selection = OCRPageSelection()
        let older = selection.ticket(for: 1)
        let other = selection.ticket(for: 2)
        _ = selection.ticket(for: 1)
        XCTAssertTrue(selection.isCurrent(older))
        XCTAssertNil(selection.selected[1])
        let newer = selection.ticket(for: 1)
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: newer))
        XCTAssertFalse(selection.adopt(OCREngineID.vision, ticket: older))
        XCTAssertEqual(selection.selected[1], OCREngineID.ndlocr)
        XCTAssertTrue(selection.adopt(OCREngineID.vision, ticket: other))
    }

    /// Une adoption du moteur déjà retenu (page posée pendant un « Relancer ») ne périme pas la lecture forcée attendue.
    func testSameEngineAdoptionKeepsPendingReadOfThatEngine() {
        var selection = OCRPageSelection()
        selection.retain(OCREngineID.ndlocr, source: 6)
        let forced = selection.ticket(for: 6)
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 6)))
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: forced))
    }

    /// Un moteur épinglé pour la page n'accepte que lui-même, même avec un ticket courant.
    func testPinnedPageOnlyAcceptsItsEngine() {
        var selection = OCRPageSelection()
        selection.pin(OCREngineID.glmocr, source: 4)
        XCTAssertFalse(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 4)))
        XCTAssertTrue(selection.adopt(OCREngineID.glmocr, ticket: selection.ticket(for: 4)))
    }

    /// « Relancer » (`retain`) et rotation (`forget`) : nouvelle intention, sans épingle.
    func testRetainAndForgetInvalidateWithoutPinning() {
        var selection = OCRPageSelection()
        let before = selection.ticket(for: 5)
        selection.retain(OCREngineID.vision, source: 5)
        XCTAssertNil(selection.pinned[5])
        XCTAssertEqual(selection.selected[5], OCREngineID.vision)
        XCTAssertFalse(selection.isCurrent(before))
        let afterRetain = selection.ticket(for: 5)
        selection.forget(5)
        XCTAssertNil(selection.selected[5])
        XCTAssertFalse(selection.isCurrent(afterRetain))
        let afterForget = selection.ticket(for: 5)
        selection.invalidate(5)
        XCTAssertFalse(selection.isCurrent(afterForget))
    }
}
