// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest

/// Chantier des styles, S1b : l'interface ne doit plus écrire de blanc ou de noir en dur, sinon un style clair
/// afficherait du texte blanc sur fond clair. Seuls restent les usages liés à la page ou au papier (fond de page,
/// encre des notes, furigana sur la page, exports), qui ne dépendent pas du style, et les valeurs du style lui-même.
final class StyleTokensGuardTests: XCTestCase {
    /// Changer de style ou de palette doit rafraîchir l'apparence sans remplacer la racine SwiftUI. Une nouvelle
    /// identité de racine détruit les présentations en cours et ferme notamment Réglages → Thèmes.
    func testThemeSelectionKeepsPresentedSettingsOpen() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/KyokashoApp.swift").standardizedFileURL
        let source = try String(contentsOf: app, encoding: .utf8)
        XCTAssertFalse(source.contains(".id(themes.identity)") || source.contains(".id(themes.appearanceRevision)"),
                       "Ne pas remplacer la racine au changement de thème : la feuille Réglages se fermerait")
        // Revue Claude de 41e2ba5 : sans reconstruction, des vues gardent l'ancienne palette ; elle se fait à la
        // fermeture des Réglages.
        XCTAssertTrue(source.contains(".id(themes.appliedAppearance)"), "La racine doit suivre l'apparence appliquée")
        let library = try String(contentsOf: app.deletingLastPathComponent().appendingPathComponent("Library/LibraryView.swift"), encoding: .utf8)
        XCTAssertTrue(library.contains("onDismiss: { themes.applyAppearance() }"), "Appliquer l'apparence à la fermeture des Réglages")
    }

    /// Un `.sheet` posé sur une `Section` est recopié sur chaque ligne : sur Mac, ouvrir « Voir le résumé » fermait toute
    /// la feuille Réglages (essai du 04/11/2026). Ces présentations doivent rester sur le `Form`.
    func testSettingsSectionsDoNotOwnPresentations() throws {
        let settings = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Settings").standardizedFileURL
        let diagnostics = try String(contentsOf: settings.appendingPathComponent("Diagnostics.swift"), encoding: .utf8)
        let section = try XCTUnwrap(diagnostics.range(of: "struct DiagnosticsSection: View"))
        let next = try XCTUnwrap(diagnostics.range(of: "private struct OvisReadingExportView"))
        XCTAssertFalse(diagnostics[section.upperBound..<next.lowerBound].contains(".sheet("))
        XCTAssertTrue(diagnostics.contains("OvisReadingExportView().environmentObject(model)"),
                      "Sans le modèle transmis à la feuille, l'extraction plante à l'ouverture")
        let intro = try String(contentsOf: settings.appendingPathComponent("IntroViews.swift"), encoding: .utf8)
        XCTAssertFalse(intro.contains("struct IntroSettingsSection"), "La feuille des nouveautés doit rester sur le Form")
    }

    /// Mac Intel (décision de NOxygen59, 04/11/2026) : ni chat, ni gros modèles, ni lien qui lance un téléchargement.
    func testIntelMacHidesChatHeavyModelsAndDownloadLinks() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        func source(_ path: String) throws -> String {
            try String(contentsOf: app.appendingPathComponent(path), encoding: .utf8)
        }
        XCTAssertTrue(try source("Study/StudyPanel.swift").contains("localAIAvailable ? [(.chat"))
        let settings = try source("Settings/SettingsView.swift")
        XCTAssertFalse(settings.contains("llama-server -hf"), "OvisOCR2 ne doit plus demander le Terminal")
        XCTAssertTrue(try source("Settings/OCRModelsView.swift").contains("row(.ovisocr2GGUF"), "OvisOCR2 garde son bouton sur Mac")
        XCTAssertTrue(settings.contains(".filter(\\.runsOnThisDevice)"))
        let models = try source("Settings/OCRModelsView.swift")
        XCTAssertTrue(models.contains("if localAIAvailable, let file = spec.mainDownload"))
        XCTAssertTrue(models.contains("files.contains { $0.name.hasSuffix(\".onnx\")"), "NDLOCR et PP-OCR ont des fichiers annexes")
    }

    /// La liste demandée reste complète : un oubli dans `all` rendrait un style impossible à choisir.
    func testStylePickerContainsEveryRequestedStyle() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Design/Styles.swift").standardizedFileURL
        let source = try String(contentsOf: file, encoding: .utf8)
        let expected = [("atelier", "atelier"), ("brutalism", "brutalism"), ("glass", "glass"),
                        ("synthwave", "synthwave"), ("swiss", "swiss"), ("wabisabi", "wabiSabi"),
                        ("clay", "clay"), ("neumorphism", "neumorphism"), ("ethereal", "ethereal"),
                        ("minimalism", "minimalism"), ("editorial", "editorial"), ("luxury", "luxury"),
                        ("victorian", "victorian"), ("maximalism", "maximalism"), ("cybercore", "cybercore"),
                        ("cyberpunk", "cyberpunk"), ("y2k", "y2k"), ("pixel", "pixel"),
                        ("scrapbook", "scrapbook"), ("sketch", "sketch"), ("bohemian", "bohemian"),
                        ("surrealism", "surrealism"), ("bento", "bento")]
        for (id, symbol) in expected {
            XCTAssertTrue(source.contains("AppStyle(id: \"\(id)\""), "Style absent : \(id)")
            XCTAssertTrue(source.contains(".\(symbol)"), "Style non exposé dans AppStyle.all : \(id)")
        }
    }

    /// Fichier → nombre d'usages permis, chacun vérifié à la main le 29/10/2026.
    private let allowed: [String: Int] = [
        "Design/Styles.swift": 1,            // voile du style Atelier
        "Design/Themes.swift": 3,            // encres par défaut des palettes nuit
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

    /// Lot 2b : ombres par `atelierShadow`, matières par `Atelier.material`, bordures par `Atelier.border`.
    func testInterfaceReliefAndBordersUseStyleTokens() throws {
        XCTAssertEqual(try count(#"\.shadow\("#), [:], "Ombre en dur : utiliser atelierShadow")
        // Sur un contenu avec du texte, l'ombre franche le dédouble : passer par atelierShapeShadow.
        XCTAssertEqual(try count(#"\.atelierShadow\("#), ["Design/Atelier.swift": 3, "Library/LibraryView.swift": 1])
        XCTAssertEqual(try count(#"\.background\(\.[A-Za-z]+Material"#), [:], "Matière en dur : utiliser Atelier.material")
        // Fond dessiné du thème (motifs) et trait posé sur la page.
        XCTAssertEqual(try count(#"lineWidth: [0-9]"#), ["Design/ThemeBackdrop.swift": 13, "Reader/ReaderScreen.swift": 1],
                       "Bordure en dur : utiliser Atelier.border(_:)")
    }

    /// Lot 2c : le texte latin de l'interface passe par `Atelier.font` (famille du style). Restent `.system` les
    /// textes à famille voulue (`design:` chasse fixe, arrondie) et le texte de la page choisi dans les réglages.
    func testInterfaceFontsUseStyleToken() throws {
        XCTAssertEqual(try count(#"\.system\(size: (?:(?!design:)[^)])*\)"#), ["Reader/OCRTextViews.swift": 1],
                       "Police système en dur : utiliser Atelier.font(_:weight:)")
    }

    /// Recette 69 : un arrondi UIKit n'est pas limité par le système ; il doit passer par `corner(_:height:)`.
    func testUIKitCornersAreClampedToHalfHeight() throws {
        XCTAssertEqual(try count(#"layer\.cornerRadius = (?!Atelier\.corner\([^)]*height:)"#), [:],
                       "layer.cornerRadius sans limite : utiliser Atelier.corner(_:height:)")
    }

    private func count(_ regex: String) throws -> [String: Int] {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        let pattern = try NSRegularExpression(pattern: regex)
        var found: [String: Int] = [:]
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in walk where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let n = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if n > 0 { found[String(url.path.dropFirst(app.path.count + 1))] = n }
        }
        return found
    }
}
