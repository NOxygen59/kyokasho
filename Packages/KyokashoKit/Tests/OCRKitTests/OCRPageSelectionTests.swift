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

    /// Contre-revue Codex de 51f8a2d, F1 : le choix du menu écrit le moteur demandé, pas le moteur affiché. Le passage
    /// NDLOCR → texte du PDF doit encore signaler que les furigana NDLOCR sont à retirer.
    func testPublicationReportsTheReplacedEngineEvenAfterPin() {
        var selection = OCRPageSelection()
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 0)))
        XCTAssertNil(selection.publish(OCREngineID.ndlocr, source: 0))
        selection.pin(OCREngineID.pdfText, source: 0)
        XCTAssertEqual(selection.published[0], OCREngineID.ndlocr)
        XCTAssertTrue(selection.adopt(OCREngineID.pdfText, ticket: selection.ticket(for: 0)))
        XCTAssertEqual(selection.publish(OCREngineID.pdfText, source: 0), OCREngineID.ndlocr)
        // Rafraîchissement du même moteur : rien à retirer.
        XCTAssertNil(selection.publish(OCREngineID.pdfText, source: 0))
    }

    /// F1, échec du nouveau moteur : l'ancienne lecture reste retenue explicitement, sans état hybride.
    func testFailedIntentRevertsToThePreviousReading() {
        var selection = OCRPageSelection()
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 2)))
        selection.publish(OCREngineID.ndlocr, source: 2)
        let intent = selection.pin(OCREngineID.vision, source: 2)
        XCTAssertTrue(selection.revert(intent))
        XCTAssertNil(selection.pinned[2])
        XCTAssertEqual(selection.selected[2], OCREngineID.ndlocr)
        XCTAssertFalse(selection.isCurrent(intent.ticket), "une lecture Vision encore en route reste refusée")
        // Une intention plus récente ne peut pas être annulée par l'échec d'une plus ancienne.
        let older = selection.pin(OCREngineID.vision, source: 2)
        selection.pin(OCREngineID.glmocr, source: 2)
        XCTAssertFalse(selection.revert(older))
        XCTAssertEqual(selection.selected[2], OCREngineID.glmocr)
    }

    /// Rotation et nouveau réglage : plus rien n'est affiché pour la page, donc rien à signaler comme remplacé.
    func testForgetAndResetClearThePublishedEngine() {
        var selection = OCRPageSelection()
        selection.publish(OCREngineID.vision, source: 1)
        selection.forget(1)
        XCTAssertNil(selection.published[1])
        selection.publish(OCREngineID.vision, source: 1)
        selection.reset()
        XCTAssertNil(selection.published[1])
    }

    /// F4 : une version corrigée peut être adoptée malgré le moteur choisi pour la page ; une version non corrigée, non.
    func testCorrectedReadingOverridesThePin() {
        var selection = OCRPageSelection()
        selection.pin(OCREngineID.ndlocr, source: 7)
        XCTAssertFalse(selection.adopt(OCREngineID.vision, ticket: selection.ticket(for: 7)))
        XCTAssertTrue(selection.adopt(OCREngineID.vision, ticket: selection.ticket(for: 7), overridingPin: true))
        XCTAssertEqual(selection.selected[7], OCREngineID.vision)
        XCTAssertEqual(selection.pinned[7], OCREngineID.ndlocr, "le choix du menu est gardé pour les pages sans correction")
    }

    /// Contre-revue Codex de 4522367 (P2, scénario 2) : NDLOCR affiché, choix Vision puis GLM-OCR dans le menu, GLM-OCR
    /// échoue. Le retour rétablit ce qui est **affiché** (NDLOCR), pas l'intention Vision annulée et jamais publiée.
    func testRevertRestoresThePublishedEngineNotACancelledIntent() {
        var selection = OCRPageSelection()
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 0)))
        selection.publish(OCREngineID.ndlocr, source: 0)
        selection.pin(OCREngineID.vision, source: 0)
        let glm = selection.pin(OCREngineID.glmocr, source: 0)
        XCTAssertTrue(selection.revert(glm))
        XCTAssertEqual(selection.selected[0], OCREngineID.ndlocr)
        XCTAssertNil(selection.pinned[0], "l'intention Vision annulée n'est pas restaurée")
    }

    /// Scénario 1 : NDLOCR affiché, choix Vision ; un autre chemin adopte et dessine Vision ; puis la demande Vision
    /// échoue. Rien n'est rétabli : l'intention est déjà satisfaite par ce qui est affiché.
    func testRevertKeepsAnIntentAlreadySatisfiedByAnotherPath() {
        var selection = OCRPageSelection()
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 1)))
        selection.publish(OCREngineID.ndlocr, source: 1)
        let intent = selection.pin(OCREngineID.vision, source: 1)
        XCTAssertTrue(selection.adopt(OCREngineID.vision, ticket: selection.ticket(for: 1)))
        selection.publish(OCREngineID.vision, source: 1)
        XCTAssertFalse(selection.revert(intent))
        XCTAssertEqual(selection.selected[1], OCREngineID.vision)
        XCTAssertEqual(selection.pinned[1], OCREngineID.vision)
    }

    /// Échec simple : un choix antérieur qui correspond à l'affichage est gardé.
    func testRevertKeepsAPreviousPinThatMatchesTheDisplay() {
        var selection = OCRPageSelection()
        selection.pin(OCREngineID.ndlocr, source: 2)
        XCTAssertTrue(selection.adopt(OCREngineID.ndlocr, ticket: selection.ticket(for: 2)))
        selection.publish(OCREngineID.ndlocr, source: 2)
        let intent = selection.pin(OCREngineID.vision, source: 2)
        XCTAssertTrue(selection.revert(intent))
        XCTAssertEqual(selection.pinned[2], OCREngineID.ndlocr)
        XCTAssertEqual(selection.selected[2], OCREngineID.ndlocr)
    }
}
