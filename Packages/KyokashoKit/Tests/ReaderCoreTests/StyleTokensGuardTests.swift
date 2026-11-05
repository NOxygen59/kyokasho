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

    /// Revue Codex de 40952cf : un calcul de furigana annulé à la fermeture ne doit pas être publié. Contrôle du source :
    /// le contrôleur dépend de PDFKit et n'a pas de test d'exécution ici.
    func testCancelledPageFuriganaIsNotPublished() throws {
        let reader = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Reader").standardizedFileURL
        let display = try String(contentsOf: reader.appendingPathComponent("ReaderController+Display.swift"), encoding: .utf8)
        XCTAssertTrue(display.contains("guard !closed, !Task.isCancelled, furiganaGeneration[source] == generation else { return }"))
        XCTAssertEqual(display.components(separatedBy: "FuriganaLayer.set(").count, 3, "publication de showOCR et de scheduleFurigana, pas d'autre")
        let close = try String(contentsOf: reader.appendingPathComponent("ReaderController+OCR.swift"), encoding: .utf8)
        XCTAssertTrue(close.contains("for page in furiganaGeneration.keys { furiganaGeneration[page, default: 0] += 1 }"))
    }

    /// Optimisation du lecteur : les résultats de fond regroupent leurs redessins, et une page aux mêmes données n'est
    /// pas recalculée. Contrôle du source : ces chemins passent par PDFKit.
    func testBackgroundResultsShareOneRedrawAndSkipKnownPages() throws {
        let reader = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Reader").standardizedFileURL
        let display = try String(contentsOf: reader.appendingPathComponent("ReaderController+Display.swift"), encoding: .utf8)
        XCTAssertFalse(display.contains("await self?.pdfView.redrawVisiblePages()"))
        XCTAssertTrue(display.contains("guard FuriganaLayer.signature(for: key) != signature else { return }"))
        XCTAssertTrue(display.contains("hasher.combine(frame.box.width)"), "PDF remplacé : l'empreinte doit suivre le cadre")
        let package = try String(contentsOf: reader.appendingPathComponent("../Library/DocumentPackageService.swift").standardizedFileURL, encoding: .utf8)
        XCTAssertTrue(package.contains("FuriganaLayer.clearMemory()"))
        let layer = try String(contentsOf: reader.appendingPathComponent("FuriganaLayer.swift"), encoding: .utf8)
        XCTAssertFalse(layer.contains("CTFontCreateWithName(\"HiraginoSans-W5\" as CFString, size, nil)"), "pas de police par lecture au dessin")
        // Revue Codex de 502383c : les fils de dessin ne partagent pas de ligne Core Text, réservée à un seul fil.
        XCTAssertFalse(layer.contains("CTLineDraw("))
        XCTAssertFalse(layer.contains("(line: CTLine"), "pas de ligne gardée dans la page préparée")
    }

    /// Comics : aucune porte vers l'OCR, l'IA ou le panneau d'étude. Contrôle du source : ces chemins passent par PDFKit.
    func testComicsCannotReachOCROrAI() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        for (file, guardText) in [
            ("Reader/ReaderController+OCR.swift", "func runOCR(engine: String? = nil, force: Bool = false) {\n        guard document.capabilities.textAnalysis"),
            ("Reader/ReaderController+OCR.swift", "func ensureOCR(_ pages: [Int]) {\n        guard document.capabilities.textAnalysis"),
            ("Reader/ReaderController.swift", "tapGeneration: Int? = nil) async {\n        guard document.capabilities.textAnalysis"),
            ("Reader/ReaderController+Search.swift", "guard documentOCRTask == nil, document.capabilities.textAnalysis"),
            ("Reader/ReaderScreen.swift", "private func openStudy(_ tab: StudyPanel.Tab) {\n        guard capabilities.study"),
            ("Library/DocumentScan.swift", "guard document.capabilities.study, UserDefaults"),
            ("Reader/ReaderController+Search.swift", "func search(_ query: String) {\n        guard document.capabilities.textAnalysis"),
            ("Reader/ReaderController+OCR.swift", "func ocr(engine: String) async throws -> OCRPage {\n        guard document.capabilities.textAnalysis"),
            ("Reader/ReaderController+OCR.swift", "if document.capabilities.textAnalysis {\n            let url = fileURL\n            pageTextTask"),
            ("AppModel.swift", "capabilities.pageEditing == true else { return }"),
            ("Reader/ReaderScreen.swift", "if capabilities.pageEditing {\n                                    // #49"),
        ] {
            let source = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(source.contains(guardText), "\(file) : \(guardText)")
        }
    }

    /// Revue Codex : un OCR lent ne doit pas rouvrir le mot d'une page quittée. Chaque fenêtre de la recherche passe le contrôle.
    func testStaleLookupNeverPresents() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Reader/ReaderController.swift").standardizedFileURL
        let source = try String(contentsOf: app, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "func lookup(at point: CGPoint"))
        let end = try XCTUnwrap(source.range(of: "nonisolated static func glyphToStringMap"))
        let body = source[start.upperBound..<end.lowerBound]
        let presents = body.components(separatedBy: "present(text:").count - 1
        XCTAssertEqual(presents, 2)
        // Chaque garde collée à sa publication : deux gardes dans la même branche ne passeraient pas.
        let guarded = try NSRegularExpression(pattern: #"guard !isStale\(\) else \{ return \}[^\n]*\n\s*present\(text:"#)
        XCTAssertEqual(guarded.numberOfMatches(in: String(body), range: NSRange(body.startIndex..., in: body)), presents)
        XCTAssertTrue(body.contains("if let ocr, !isStale() {"))
        XCTAssertTrue(body.contains("guard let ocr, !isStale() else { return }"))
    }

    /// Une analyse OvisOCR2 doit pouvoir s'arrêter depuis la liste des IA, et sa durée être annoncée.
    func testOvisAnalysisCanBeStoppedAndAnnouncesItsDuration() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App").standardizedFileURL
        let tasks = try String(contentsOf: app.appendingPathComponent("Reader/AITaskCenter.swift"), encoding: .utf8)
        XCTAssertTrue(tasks.contains("analysis.cancel()"))
        XCTAssertTrue(tasks.contains("confirmAnalysisStop = true }"), "L'alerte doit attendre la fermeture de la bulle")
        let root = try String(contentsOf: app.appendingPathComponent("KyokashoApp.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains("AnalysisDurationBanner()"))
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

    /// Revue Claude de 05108d3 : un univers n'impose pas son fond à toutes les palettes, et aucun aperçu n'utilise un
    /// symbole absent d'iOS 16 (nom en simple chaîne : ni le compilateur ni un rendu Mac ne le voient).
    func testPaletteKeepsItsBackdropAndSymbolsExistOnIOS16() throws {
        let design = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Design").standardizedFileURL
        let backdrop = try String(contentsOf: design.appendingPathComponent("ThemeBackdrop.swift"), encoding: .utf8)
        let imposed = try XCTUnwrap(backdrop.range(of: "private var effectiveBackdrop"))
        let end = try XCTUnwrap(backdrop.range(of: "default: return theme.backdrop"))
        let cases = backdrop[imposed.upperBound..<end.lowerBound]
        for id in ["atelier", "wabisabi", "swiss", "brutalism", "synthwave", "luxury"] {
            XCTAssertFalse(cases.contains("\"\(id)\""), "\(id) ne doit pas imposer son fond")
        }
        let themes = try String(contentsOf: design.appendingPathComponent("Themes.swift"), encoding: .utf8)
        XCTAssertFalse(themes.contains("return \"sun.horizon\""))
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
        "Reader/ReaderStatusBadge.swift": 4, // batterie et heure : blanc sur noir translucide, lisibles sur toute page
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
        XCTAssertEqual(try count(#"\.atelierShadow\("#), ["Design/Atelier.swift": 3, "Design/ThemePreview.swift": 1, "Library/LibraryView.swift": 1])
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
