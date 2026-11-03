// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import ReaderCore

/// Rectangle normalisé (0…1) dans la page source, **origine en haut à gauche**, y vers le bas.
/// Référence : la `cropBox` d'origine de la page (avant rognage, découpe ou rotation de l'app),
/// pour que les résultats restent valables quels que soient les réglages d'affichage.
public struct NormBox: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }

    /// Depuis un rectangle normalisé de Vision (origine en bas à gauche).
    public static func fromVision(_ r: CGRect) -> NormBox {
        NormBox(x: r.minX, y: 1 - r.minY - r.height, w: r.width, h: r.height)
    }

    public func contains(_ point: CGPoint) -> Bool { rect.contains(point) }
}

/// Une ligne de texte reconnue.
public struct OCRLine: Codable, Hashable, Sendable {
    public var text: String
    public var box: NormBox
    /// Une boîte par caractère (graphème) de `text`, dans l'ordre. Toujours présentes : mesurées
    /// par le moteur quand c'est fiable, sinon estimées (voir `CharacterLayout`).
    public var charBoxes: [NormBox]
    /// Les boîtes viennent du moteur (vrai) ou d'un découpage proportionnel (faux).
    public var measuredCharBoxes: Bool
    public var vertical: Bool
    public var confidence: Double
    /// Caractères douteux après relecture (index de graphème), `nil` si la ligne n'a pas été relue.
    public var doubt: [Int]?
    /// Ligne corrigée à la main (jamais retouchée ensuite par la relecture automatique).
    public var edited: Bool?

    /// Choix explicite de l'utilisateur, y compris « Garder tel quel » : persiste l'acceptation.
    /// Les positions mesurées restent utilisables si la longueur ne change pas.
    public func acceptingCorrection(_ text: String) -> OCRLine {
        var line = self
        if text.count != line.charBoxes.count {
            line.charBoxes = CharacterLayout.proportional(text, in: line.box, vertical: line.vertical)
            line.measuredCharBoxes = false
        }
        line.text = text
        line.edited = true
        line.doubt = []
        return line
    }

    public init(text: String, box: NormBox, charBoxes: [NormBox], measuredCharBoxes: Bool, vertical: Bool, confidence: Double) {
        self.text = text
        self.box = box
        self.charBoxes = charBoxes
        self.measuredCharBoxes = measuredCharBoxes
        self.vertical = vertical
        self.confidence = confidence
    }
}

/// Résultat OCR d'une page.
public struct OCRPage: Codable, Hashable, Sendable {
    /// Version du format/rendu : un résultat plus ancien en cache est refait automatiquement.
    /// 4 : boîtes de caractères de NDLOCR mesurées par PP-OCRv5 (si installé).
    /// 5 : texte intégré dans le repère tourné (pages /Rotate), comme le rendu OCR.
    /// 6 : la rotation supplémentaire choisie dans Kyōkasho entre dans le rendu et les boîtes OCR.
    public static let currentVersion = 6
    /// Les résultats v5 restent valides tant qu'aucune rotation propre à Kyōkasho n'est appliquée à la page.
    public static let unrotatedMinimumVersion = 5

    public var engine: String
    public var lines: [OCRLine]
    public var durationMs: Int
    public var version: Int
    /// Relecture faite (dictionnaire, paires de caractères) ; `reread` : lignes douteuses relues par GLM-OCR.
    public var proofread: Bool?
    public var reread: Bool?

    public init(engine: String, lines: [OCRLine], durationMs: Int, version: Int = OCRPage.currentVersion) {
        self.engine = engine
        self.lines = lines
        self.durationMs = durationMs
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decode(String.self, forKey: .engine)
        lines = try c.decode([OCRLine].self, forKey: .lines)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        proofread = try c.decodeIfPresent(Bool.self, forKey: .proofread)
        reread = try c.decodeIfPresent(Bool.self, forKey: .reread)
    }

    /// Texte de la page, une ligne par ligne reconnue.
    public var text: String { lines.map(\.text).joined(separator: "\n") }

    /// Caractère sous un point (coordonnées normalisées) : (ligne, index du caractère).
    /// Caractère sous le point (repère normalisé de la page). `tolerance` : marge autorisée autour des
    /// lignes (un doigt est moins précis qu'un curseur ; les petits caractères sont vite manqués).
    /// La ligne la plus proche gagne ; à distance égale, la plus fine (petits caractères, furigana).
    public func character(at point: CGPoint, tolerance: Double = 0.002) -> (line: Int, index: Int)? {
        var best: (line: Int, distance: Double, thickness: Double)?
        for (l, line) in lines.enumerated() where !line.charBoxes.isEmpty {
            let r = line.box.rect
            let dx = max(r.minX - point.x, 0, point.x - r.maxX)
            let dy = max(r.minY - point.y, 0, point.y - r.maxY)
            let distance = (dx * dx + dy * dy).squareRoot()
            let thickness = line.vertical ? r.width : r.height
            // Marge : au moins `tolerance`, et jusqu'à 60 % de l'épaisseur de la ligne.
            guard distance <= max(tolerance, thickness * 0.6) else { continue }
            if let b = best, distance > b.distance + 1e-6 || (abs(distance - b.distance) <= 1e-6 && thickness >= b.thickness) { continue }
            best = (l, Double(distance), Double(thickness))
        }
        guard let l = best?.line else { return nil }
        let line = lines[l]
        if let i = line.charBoxes.firstIndex(where: { $0.rect.contains(point) }) { return (l, i) }
        // Entre deux caractères (ou à côté de la ligne) : le plus proche le long de la ligne.
        let distances = line.charBoxes.map { line.vertical ? abs($0.midY - point.y) : abs($0.midX - point.x) }
        guard let i = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return nil }
        return (l, i)
    }
}

public extension OCRPage {
    /// Tourne les boîtes normalisées déjà extraites (cas du texte intégré au PDF).
    func rotatedClockwise(_ degrees: Int) -> OCRPage {
        let rotation = PageTransform.normalizedRotation(degrees)
        guard rotation != 0 else { return self }
        func rotate(_ box: NormBox) -> NormBox {
            switch rotation {
            case 90: return NormBox(x: 1 - box.y - box.h, y: box.x, w: box.h, h: box.w)
            case 180: return NormBox(x: 1 - box.x - box.w, y: 1 - box.y - box.h, w: box.w, h: box.h)
            case 270: return NormBox(x: box.y, y: 1 - box.x - box.w, w: box.h, h: box.w)
            default: return box
            }
        }
        var page = self
        page.lines = lines.map { source in
            var line = source
            line.box = rotate(line.box)
            line.charBoxes = line.charBoxes.map(rotate)
            if rotation == 90 || rotation == 270 { line.vertical.toggle() }
            return line
        }
        return page
    }
}

public extension OCRPage {
    var hasManualEdits: Bool { lines.contains { $0.edited == true } }

    /// Résultat utilisable sur une page portant cette rotation Kyōkasho, ou `nil` s'il faut refaire l'OCR.
    /// Un résultat v5 ignorait cette rotation : refait, sauf s'il porte des corrections manuelles, qui ne se
    /// recalculent pas. Ses boîtes sont alors remises dans le repère tourné.
    func readable(atAdditionalRotation rotation: Int) -> OCRPage? {
        if rotation % 360 == 0 { return version >= Self.unrotatedMinimumVersion ? self : nil }
        if version >= Self.currentVersion { return self }
        guard version >= Self.unrotatedMinimumVersion, hasManualEdits else { return nil }
        var page = rotatedClockwise(rotation)
        page.version = Self.currentVersion
        return page
    }

    /// JSON à garder en base quand la rotation d'une page change : seuls les résultats corrigés à la main sont
    /// conservés, tournés avec la page. `nil` : le résultat est à effacer, l'OCR sera refait.
    /// Un résultat trop ancien pour être converti sans risque, ou illisible, est gardé tel quel : une rotation ne
    /// doit jamais être ce qui efface une correction. Il reste ignoré à l'affichage, comme avant la rotation.
    static func jsonKeepingManualEdits(_ json: Data, fromRotation previous: Int, toRotation new: Int) -> Data? {
        guard let stored = try? JSONDecoder().decode(OCRPage.self, from: json) else { return json }
        guard stored.hasManualEdits else { return nil }
        guard let current = stored.readable(atAdditionalRotation: previous) else { return json }
        var page = current.rotatedClockwise(new - previous)
        page.version = currentVersion
        return try? JSONEncoder().encode(page)
    }
}

/// Identifiants des moteurs (stockés en base).
public enum OCREngineID {
    public static let pdfText = "pdfText"
    public static let vision = "vision"
    public static let ppocr5 = "ppocr5"
    public static let ndlocr = "ndlocr"
    public static let glmocr = "glmocr"

    public static func displayName(_ id: String) -> String {
        switch id {
        case pdfText: return "Texte du PDF"
        case vision: return "Apple Vision"
        case ppocr5: return "PP-OCRv5"
        case ndlocr: return "NDLOCR-Lite"
        case glmocr: return "GLM-OCR (IA)"
        default: return id
        }
    }
}

public enum OCRError: LocalizedError, Equatable {
    case pageUnavailable
    case noTextLayer
    case renderFailed
    case cancelled
    case modelMissing(String)
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .pageUnavailable: return "Page introuvable dans le PDF."
        case .noTextLayer: return "Cette page n'a pas de texte intégré (c'est probablement une image) : utilise Apple Vision."
        case .renderFailed: return "Impossible de préparer l'image de la page."
        case .cancelled: return "OCR annulé."
        case .modelMissing(let name): return "Modèle « \(name) » pas téléchargé : Réglages → Modèles d'IA et outils."
        case .engineFailed(let message): return message
        }
    }
}

/// Repère des résultats OCR d'une page : sa `cropBox` d'origine **et sa rotation intrinsèque** (/Rotate du PDF,
/// fréquente sur les photos de pages). Le rendu pour l'OCR applique cette rotation : les boîtes normalisées
/// sont dans le sens affiché, alors que PDFKit donne les points dans le repère non tourné de la page.
public struct PageFrame: Sendable, Equatable {
    public var box: CGRect
    /// 0, 90, 180 ou 270 (sens horaire, comme `PDFPage.rotation`).
    public var rotation: Int

    public init(box: CGRect, rotation: Int) {
        self.box = box
        self.rotation = ((rotation % 360) + 360) % 360
    }

    /// Point de la page (repère PDF, y vers le haut) → point normalisé du rendu OCR (haut-gauche, y vers le bas).
    public func normalized(_ p: CGPoint) -> CGPoint {
        let px = (p.x - box.minX) / max(box.width, 1e-9), py = (p.y - box.minY) / max(box.height, 1e-9)
        switch rotation {
        case 90: return CGPoint(x: py, y: px)
        case 180: return CGPoint(x: 1 - px, y: py)
        case 270: return CGPoint(x: 1 - py, y: 1 - px)
        default: return CGPoint(x: px, y: 1 - py)
        }
    }

    /// Inverse de `normalized`.
    public func pagePoint(_ n: CGPoint) -> CGPoint {
        let px: CGFloat, py: CGFloat
        switch rotation {
        case 90: px = n.y; py = n.x
        case 180: px = 1 - n.x; py = n.y
        case 270: px = 1 - n.y; py = 1 - n.x
        default: px = n.x; py = 1 - n.y
        }
        return CGPoint(x: box.minX + px * box.width, y: box.minY + py * box.height)
    }

    /// Boîte normalisée (OCR, mise en page) → rectangle dans le repère de la page.
    public func pageRect(_ n: NormBox) -> CGRect {
        let a = pagePoint(CGPoint(x: n.x, y: n.y)), b = pagePoint(CGPoint(x: n.x + n.w, y: n.y + n.h))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
