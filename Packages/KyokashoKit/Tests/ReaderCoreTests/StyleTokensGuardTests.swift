// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest

/// Chantier des styles, S1b : l'interface ne doit plus écrire de blanc ou de noir en dur, sinon un style clair
/// afficherait du texte blanc sur fond clair. Seuls restent les usages liés à la page ou au papier (fond de page,
/// encre des notes, furigana sur la page, exports), qui ne dépendent pas du style, et les valeurs du style lui-même.
final class StyleTokensGuardTests: XCTestCase {
    /// Fichier → nombre d'usages permis, chacun vérifié à la main le 29/10/2026.
    private let allowed: [String: Int] = [
        "Design/Styles.swift": 4,            // valeurs du style Atelier
        "Design/ThemeBackdrop.swift": 1,     // dessin du fond « collines », propre à ce motif
        "Reader/ResourceMonitor.swift": 2,   // masque de dégradé (opacité seulement)
        "Reader/ReaderController+Display.swift": 1, // fond de page noir choisi par l'utilisateur
        "Reader/ReaderController.swift": 6,  // papier, fonds de page, astérisque dessiné sur la page
        "Reader/InkOverlay.swift": 1,        // encre par défaut sur la page
        "Reader/NoteWindow.swift": 3,        // stylo noir et texte de la note (papier)
        "Reader/FuriganaLayer.swift": 3,     // couleur des furigana sur la page
        "Settings/SettingsView.swift": 4,    // noms des fonds de page
        "Library/DocumentExport.swift": 2,   // dessin dans le PDF exporté
    ]

    func testInterfaceUsesStyleTokensInsteadOfWhiteOrBlack() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        let pattern = try NSRegularExpression(pattern: #"\.(white|black)\b"#)
        var found: [String: Int] = [:]
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if count > 0 { found[String(url.path.dropFirst(app.path.count + 1))] = count }
        }
        XCTAssertEqual(found, allowed, "Blanc ou noir en dur dans l'interface : utiliser Atelier.onAccentInk, shadow, scrim ou contrastInk")
    }

    /// Lot 2a : les arrondis de l'interface passent par `Atelier.corner`, `radius` ou `smallRadius`, pour qu'un style
    /// puisse les changer (angles droits, formes gonflées). Seuls les dessins posés sur la page restent en dur.
    func testInterfaceCornersUseStyleTokens() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        let pattern = try NSRegularExpression(pattern: #"cornerRadius(: | = )[0-9]"#)
        var found: [String: Int] = [:]
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if count > 0 { found[String(url.path.dropFirst(app.path.count + 1))] = count }
        }
        // Sélection OCR et repères dessinés sur la page (`Path(roundedRect:)`).
        XCTAssertEqual(found, ["Reader/ReaderScreen.swift": 2], "Arrondi en dur dans l'interface : utiliser Atelier.corner(_:)")
    }
}
