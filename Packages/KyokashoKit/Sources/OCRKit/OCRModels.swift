// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation

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
    public static let currentVersion = 2

    public var engine: String
    public var lines: [OCRLine]
    public var durationMs: Int
    public var version: Int

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
    }

    /// Texte de la page, une ligne par ligne reconnue.
    public var text: String { lines.map(\.text).joined(separator: "\n") }

    /// Caractère sous un point (coordonnées normalisées) : (ligne, index du caractère).
    public func character(at point: CGPoint) -> (line: Int, index: Int)? {
        for (l, line) in lines.enumerated() where line.box.rect.insetBy(dx: -0.002, dy: -0.002).contains(point) {
            if let i = line.charBoxes.firstIndex(where: { $0.rect.insetBy(dx: -0.001, dy: -0.002).contains(point) }) {
                return (l, i)
            }
            // Entre deux caractères : le plus proche le long de la ligne.
            let distances = line.charBoxes.map { line.vertical ? abs($0.midY - point.y) : abs($0.midX - point.x) }
            if let best = distances.indices.min(by: { distances[$0] < distances[$1] }) { return (l, best) }
        }
        return nil
    }
}

/// Identifiants des moteurs (stockés en base).
public enum OCREngineID {
    public static let pdfText = "pdfText"
    public static let vision = "vision"

    public static func displayName(_ id: String) -> String {
        switch id {
        case pdfText: return "Texte du PDF"
        case vision: return "Apple Vision"
        default: return id
        }
    }
}

public enum OCRError: LocalizedError, Equatable {
    case pageUnavailable
    case noTextLayer
    case renderFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .pageUnavailable: return "Page introuvable dans le PDF."
        case .noTextLayer: return "Cette page n'a pas de texte intégré (c'est probablement une image) : utilise Apple Vision."
        case .renderFailed: return "Impossible de préparer l'image de la page."
        case .cancelled: return "OCR annulé."
        }
    }
}
