// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit

/// Modèles de mise en page (versions ONNX de RapidLayout, Apache-2.0) : zones de la page classées.
/// Pré / post-traitement repris de RapidLayout (`model_handler/pp_doc_layout`, `doc_layout`).
public enum LayoutDetector {
    public enum Engine: String, CaseIterable, Sendable {
        case geometry, ppDocLayout, docLayoutYOLO

        public var spec: ModelSpec? {
            switch self {
            case .geometry: return nil
            case .ppDocLayout: return .ppdoclayout
            case .docLayoutYOLO: return .doclayoutyolo
            }
        }

        public var title: String {
            switch self {
            case .geometry: return String(localized: "Géométrie (intégré)", bundle: .main)
            case .ppDocLayout: return "PP-DocLayout"
            case .docLayoutYOLO: return String(localized: "DocLayout-YOLO (MinerU)", bundle: .main)
            }
        }

        public func isAvailable(store: ModelStore = .shared) -> Bool { spec.map(store.isInstalled) ?? true }
    }

    static let ppLabels = ["abstract", "algorithm", "aside_text", "chart", "content", "display_formula", "doc_title",
                           "figure_title", "footer", "footer_image", "footnote", "formula_number", "header", "header_image",
                           "image", "inline_formula", "number", "paragraph_title", "reference", "reference_content", "seal",
                           "table", "text", "vertical_text", "vision_footnote"]
    static let yoloLabels = ["title", "plain text", "abandon", "figure", "figure_caption", "table", "table_caption",
                             "table_footnote", "isolate_formula", "formula_caption"]

    /// Zones de la page (cadre normalisé, origine en haut à gauche). Vide pour `geometry`.
    public static func regions(_ input: OCRInput, engine: Engine, store: ModelStore = .shared) throws -> [OCRLayout.Region] {
        guard let spec = engine.spec else { return [] }
        guard store.isInstalled(spec) else { throw OCRError.modelMissing(spec.title) }
        let image = try ONNXEngines.pageImage(input, longSide: 1600)
        let model = try SessionCache.shared.model(store.url(spec, "layout.onnx"))
        let W = Double(image.width), H = Double(image.height)
        var found: [(label: String, score: Float, box: CGRect, order: Double?)] = []
        switch engine {
        case .geometry: return []
        case .ppDocLayout:
            // 800 × 800 étiré, pixels / 255 ; boxes rendues dans le repère de l'image d'origine.
            let side = 800
            let tensor = image.resized(width: side, height: side).chw(mean: [0, 0, 0], std: [1, 1, 1])
            let out = try model.run(floats: ["im_shape": ([800, 800], [1, 2]), "image": (tensor, [1, 3, side, side]),
                                             "scale_factor": ([Float(800 / H), Float(800 / W)], [1, 2])])
            guard let rows = out.values.first(where: { $0.shape.count == 2 && $0.shape[1] == 7 }) else { return [] }
            let v = rows.floats
            for r in 0..<rows.shape[0] where (r + 1) * 7 <= v.count {
                let row = Array(v[r * 7..<(r + 1) * 7])
                guard row.allSatisfy(\.isFinite) else { continue }
                let cls = Int(row[0])
                guard cls >= 0, cls < ppLabels.count, row[1] > 0.45 else { continue }
                found.append((ppLabels[cls], row[1], CGRect(x: Double(row[2]), y: Double(row[3]),
                                                             width: Double(row[4] - row[2]), height: Double(row[5] - row[3])),
                              Double(row[6])))
            }
        case .docLayoutYOLO:
            // Image posée en haut à gauche d'un carré 1024 gris (114), pixels / 255 ; sortie : x1 y1 x2 y2 score classe.
            let side = 1024
            let r = Double(side) / max(W, H)
            let w = max(1, Int(W * r)), h = max(1, Int(H * r))
            var square = RGBImage(width: side, height: side, fill: 114)
            let small = image.resized(width: w, height: h)
            for y in 0..<h {
                square.pixels.replaceSubrange(y * side * 3..<(y * side + w) * 3, with: small.pixels[y * w * 3..<(y + 1) * w * 3])
            }
            let tensor = square.chw(mean: [0, 0, 0], std: [1, 1, 1])
            guard let out = try model.run(floats: ["images": (tensor, [1, 3, side, side])]).values.first,
                  out.shape.count == 3, out.shape[2] == 6 else { return [] }
            let v = out.floats
            for k in 0..<out.shape[1] where (k + 1) * 6 <= v.count {
                let row = Array(v[k * 6..<(k + 1) * 6])
                guard row.allSatisfy(\.isFinite) else { continue }
                let cls = Int(row[5])
                guard cls >= 0, cls < yoloLabels.count, row[4] > 0.35 else { continue }
                found.append((yoloLabels[cls], row[4], CGRect(x: Double(row[0]) / r, y: Double(row[1]) / r,
                                                               width: Double(row[2] - row[0]) / r, height: Double(row[3] - row[1]) / r), nil))
            }
        }
        // Doublons d'une même classe (recouvrement > 60 %) : le meilleur score reste.
        found.sort { $0.score > $1.score }
        var kept: [(label: String, score: Float, box: CGRect, order: Double?)] = []
        for f in found where !kept.contains(where: { $0.label == f.label && iou($0.box, f.box) > 0.6 }) { kept.append(f) }
        return kept.compactMap { f in
            guard let kind = kind(f.label) else { return nil }
            let box = NormBox(x: f.box.minX / W, y: f.box.minY / H, w: f.box.width / W, h: f.box.height / H)
            return OCRLayout.Region(box: box, kind: kind, order: f.order)
        }
    }

    static func kind(_ label: String) -> OCRLayout.Region.Kind? {
        switch label {
        case "doc_title": return .title(level: 1)
        case "title", "paragraph_title": return .title(level: 2)
        case "text", "plain text", "vertical_text", "abstract", "content", "reference", "reference_content", "aside_text",
             "footnote", "algorithm", "table_footnote", "vision_footnote": return .text
        case "table": return .table
        case "figure_title", "figure_caption", "table_caption", "formula_caption": return .caption
        case "image", "chart", "figure", "seal": return .figure
        case "display_formula", "isolate_formula", "inline_formula", "formula_number": return .formula
        case "header", "footer", "header_image", "footer_image", "number", "abandon": return .ignored
        default: return nil
        }
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }
}
