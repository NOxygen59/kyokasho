// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import Foundation
import OCRKit
import OnnxRuntimeBindings

// Moteurs OCR sur l'iPad avec ONNX Runtime (CPU). Les modèles sont téléchargés à la demande
// (`ModelStore`). Code écrit pour Kyōkasho d'après la description des modèles :
// PP-OCRv5 (PaddleOCR / RapidOCR, Apache-2.0) et NDLOCR-Lite (NDL, CC-BY-4.0).

// MARK: - Session ONNX

final class ONNXModel: @unchecked Sendable {
    private static let env = try? ORTEnv(loggingLevel: .warning)
    private let session: ORTSession
    private let lock = NSLock()

    /// `coreML` : GPU / Neural Engine (formes d'entrée fixes seulement) ; le CPU prend le relais sinon.
    init(path: URL, threads: Int = 3, coreML: Bool = false) throws {
        guard let env = Self.env else { throw OCRError.renderFailed }
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(Int32(threads))
        try options.setGraphOptimizationLevel(.all)
        if coreML { try? options.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions()) }
        session = try ORTSession(env: env, modelPath: path.path, sessionOptions: options)
    }

    struct Tensor {
        var data: Data
        var shape: [Int]
    }

    /// Lance le modèle. Entrées Float32 (`floats`) ou Int64 (`ints`), sorties brutes + forme.
    func run(floats: [String: ([Float], [Int])], ints: [String: ([Int64], [Int])] = [:]) throws -> [String: Tensor] {
        try lock.withLock {
            var inputs: [String: ORTValue] = [:]
            for (name, (values, shape)) in floats {
                let data = values.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * 4) }
                inputs[name] = try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
            }
            for (name, (values, shape)) in ints {
                let data = values.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * 8) }
                inputs[name] = try ORTValue(tensorData: data, elementType: .int64, shape: shape.map { NSNumber(value: $0) })
            }
            let names = try session.outputNames()
            let outputs = try session.run(withInputs: inputs, outputNames: Set(names), runOptions: nil)
            var result: [String: Tensor] = [:]
            for (name, value) in outputs {
                let shape = try value.tensorTypeAndShapeInfo().shape.map(\.intValue)
                result[name] = Tensor(data: try value.tensorData() as Data, shape: shape)
            }
            return result
        }
    }

    func inputNames() throws -> [String] { try session.inputNames() }
    func outputNames() throws -> [String] { try session.outputNames() }
}

extension ONNXModel.Tensor {
    var floats: [Float] { data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
    var int64s: [Int64] { data.withUnsafeBytes { Array($0.bindMemory(to: Int64.self)) } }
}

/// Sessions ouvertes une fois (chargement ≈ 1 s), gardées tant que l'app tourne.
final class SessionCache: @unchecked Sendable {
    static let shared = SessionCache()
    private let lock = NSLock()
    private var models: [URL: ONNXModel] = [:]
    private var texts: [URL: [String]] = [:]

    func model(_ url: URL, coreML: Bool = false) throws -> ONNXModel {
        if let m = lock.withLock({ models[url] }) { return m }
        let m = try ONNXModel(path: url, coreML: coreML)
        lock.withLock { models[url] = m }
        return m
    }

    func charset(_ url: URL, parse: (String) -> [String]?) throws -> [String] {
        if let c = lock.withLock({ texts[url] }) { return c }
        guard let c = parse(try String(contentsOf: url, encoding: .utf8)) else { throw OCRError.renderFailed }
        lock.withLock { texts[url] = c }
        return c
    }

    func clear() { lock.withLock { models = [:]; texts = [:] } }
}

public enum ONNXEngines {
    /// Libère la mémoire des modèles (avertissement mémoire, modèle supprimé).
    public static func unload() { SessionCache.shared.clear() }

    static func pageImage(_ input: OCRInput, longSide: Int) throws -> RGBImage {
        let cg: CGImage
        switch input {
        case .pdfPage(let url, let index): cg = try PageRenderer.render(url: url, pageIndex: index, longSide: longSide)
        case .image(let image): cg = image
        }
        guard let rgb = RGBImage(cg) else { throw OCRError.renderFailed }
        return rgb
    }

    static func normalized(_ r: CGRect, in image: RGBImage) -> NormBox {
        NormBox(x: r.minX / Double(image.width), y: r.minY / Double(image.height),
                w: r.width / Double(image.width), h: r.height / Double(image.height))
    }
}

// MARK: - PP-OCRv5

/// PP-OCRv5 mobile : détecteur DB (lignes) + reconnaissance CTC (18 383 caractères, dont kana et kanji).
public struct PPOCREngine: OCREngine {
    public let id = OCREngineID.ppocr5
    let store: ModelStore

    public init(store: ModelStore = .shared) {
        self.store = store
    }

    public var isAvailable: Bool { store.isInstalled(.ppocr5) }

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.ppocr5.title) }
        let start = Date()
        // Page en haute définition (les petits caractères restent lisibles dans les découpes de lignes) ;
        // la détection, elle, travaille sur une version réduite.
        let image = try ONNXEngines.pageImage(input, longSide: 3000)
        let boxes = try detect(image)
        try Task.checkCancellation()
        let rec = try SessionCache.shared.model(store.url(.ppocr5, "rec.onnx"))
        let charset = try SessionCache.shared.charset(store.url(.ppocr5, "dict.txt")) { SequenceDecoder.paddleCharset(dict: $0) }
        var lines: [OCRLine] = []
        for box in boxes {
            try Task.checkCancellation()
            if let line = try recognize(box.rect, in: image, model: rec, charset: charset) { lines.append(line) }
        }
        return OCRPage(engine: id, lines: NeuralLayout.readingOrder(lines), durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Lignes de texte (repère de `image`), comme PaddleOCR : côté court ≥ 736, multiples de 32.
    func detect(_ image: RGBImage) throws -> [DBPostprocess.Box] {
        let det = try SessionCache.shared.model(store.url(.ppocr5, "det.onnx"))
        let shortSide = min(image.width, image.height), longSide = max(image.width, image.height)
        // Côté court ≥ 736 (comme PaddleOCR), côté long ≤ 2400 (temps de calcul).
        let ratio = shortSide < 736 ? 736 / Double(shortSide) : min(1, 2400 / Double(longSide))
        let w = max(32, Int((Double(image.width) * ratio / 32).rounded()) * 32)
        let h = max(32, Int((Double(image.height) * ratio / 32).rounded()) * 32)
        let tensor = image.resized(width: w, height: h).chw(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5])
        let name = try det.inputNames().first ?? "x"
        guard let out = try det.run(floats: [name: (tensor, [1, 3, h, w])]).values.first else { return [] }
        let mapH = out.shape.count >= 4 ? out.shape[2] : h, mapW = out.shape.count >= 4 ? out.shape[3] : w
        return DBPostprocess.boxes(map: out.floats, width: mapW, height: mapH,
                                   outputSize: CGSize(width: image.width, height: image.height))
    }

    func recognize(_ rect: CGRect, in image: RGBImage, model: ONNXModel, charset: [String]) throws -> OCRLine? {
        var crop = image.cropped(x: Int(rect.minX), y: Int(rect.minY), width: Int(rect.width.rounded(.up)),
                                 height: Int(rect.height.rounded(.up)))
        // Colonne verticale : tournée pour devenir une ligne (le haut passe à gauche).
        let vertical = Double(crop.height) / Double(max(crop.width, 1)) >= 1.5
        if vertical { crop = crop.rotatedCounterClockwise() }
        let targetH = 48
        let ratio = Double(crop.width) / Double(max(crop.height, 1))
        let inputW = Int((Double(targetH) * max(320.0 / 48.0, ratio)).rounded(.up))
        let resizedW = min(inputW, Int((Double(targetH) * ratio).rounded(.up)))
        // Fond 128 ≈ 0 une fois normalisé, comme le remplissage de PaddleOCR.
        let tensorImage = crop.resized(width: max(1, resizedW), height: targetH).padded(width: inputW, height: targetH, fill: 128)
        let tensor = tensorImage.chw(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5])
        let name = try model.inputNames().first ?? "x"
        guard let out = try model.run(floats: [name: (tensor, [1, 3, targetH, inputW])]).values.first,
              out.shape.count == 3 else { return nil }
        let steps = out.shape[1], classes = out.shape[2]
        let decoded = SequenceDecoder.ctc(out.floats, steps: steps, classes: classes, charset: charset)
        let text = decoded.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, decoded.confidence >= 0.5 else { return nil }
        let box = ONNXEngines.normalized(rect, in: image)
        // Centre de chaque caractère : position de son pas de temps sur la largeur utile.
        var centers = decoded.positions.map { t in
            min(1, max(0, (Double(t) + 0.5) * Double(inputW) / Double(steps) / Double(max(resizedW, 1))))
        }
        let characters = Array(decoded.text)
        if characters.count != centers.count || decoded.text != text { centers = [] }
        let charBoxes = centers.isEmpty
            ? CharacterLayout.proportional(text, in: box, vertical: vertical)
            : NeuralLayout.characterBoxes(count: characters.count, centers: centers, in: box, vertical: vertical)
        return OCRLine(text: text, box: box, charBoxes: charBoxes, measuredCharBoxes: !centers.isEmpty,
                       vertical: vertical, confidence: decoded.confidence)
    }
}

// MARK: - NDLOCR-Lite

/// NDLOCR-Lite : détecteur DEIM (mise en page, 17 classes) + PARSeq (7 141 caractères) en cascade
/// selon la longueur prévue de la ligne (30, 50 ou 100 caractères).
public struct NDLOCREngine: OCREngine {
    public let id = OCREngineID.ndlocr
    let store: ModelStore

    /// Classes « ligne » du détecteur : corps, légende, publicité, note, note en cours, titre.
    static let lineClasses: Set<Int> = [1, 2, 3, 4, 5, 16]

    public init(store: ModelStore = .shared) {
        self.store = store
    }

    public var isAvailable: Bool { store.isInstalled(.ndlocr) }

    public func recognize(_ input: OCRInput) async throws -> OCRPage {
        guard isAvailable else { throw OCRError.modelMissing(ModelSpec.ndlocr.title) }
        let start = Date()
        let image = try ONNXEngines.pageImage(input, longSide: 3000)
        let detections = try detect(image)
        let charset = try SessionCache.shared.charset(store.url(.ndlocr, "NDLmoji.yaml")) { SequenceDecoder.ndlCharset(yaml: $0) }
        var lines: [OCRLine] = []
        for d in detections {
            try Task.checkCancellation()
            let crop = image.cropped(x: Int(d.rect.minX), y: Int(d.rect.minY), width: Int(d.rect.width.rounded(.up)),
                                     height: Int(d.rect.height.rounded(.up)))
            let text = try read(crop, charCount: d.charCount, charset: charset).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let box = ONNXEngines.normalized(d.rect, in: image)
            let vertical = d.rect.height > d.rect.width
            lines.append(OCRLine(text: text, box: box, charBoxes: CharacterLayout.proportional(text, in: box, vertical: vertical),
                                 measuredCharBoxes: false, vertical: vertical, confidence: Double(d.score)))
        }
        return OCRPage(engine: id, lines: NeuralLayout.readingOrder(lines), durationMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    struct Detection { var rect: CGRect; var score: Float; var charCount: Int64 }

    /// Page posée dans un carré (noir), réduite à 800 × 800, normalisation ImageNet.
    func detect(_ image: RGBImage) throws -> [Detection] {
        let model = try SessionCache.shared.model(store.url(.ndlocr, "deim.onnx"))
        let side = 800
        let square = max(image.width, image.height)
        let tensor = image.padded(width: square, height: square, fill: 0).resized(width: side, height: side)
            .chw(mean: [0.485, 0.456, 0.406], std: [0.229, 0.224, 0.225])
        let names = try model.inputNames()
        guard names.count >= 2 else { return [] }
        let out = try model.run(floats: [names[0]: (tensor, [1, 3, side, side])],
                                ints: [names[1]: ([Int64(side), Int64(side)], [1, 2])])
        guard let labels = out["labels"]?.int64s, let boxes = out["boxes"]?.floats, let scores = out["scores"]?.floats else { return [] }
        let counts = out["char_count"]?.int64s ?? []
        let scale = Double(square) / Double(side)
        var result: [Detection] = []
        for i in 0..<min(labels.count, scores.count) where scores[i] > 0.25 {
            guard Self.lineClasses.contains(Int(labels[i]) - 1), boxes.count >= (i + 1) * 4 else { continue }
            let x0 = Double(boxes[i * 4]) * scale, y0 = Double(boxes[i * 4 + 1]) * scale
            let x1 = Double(boxes[i * 4 + 2]) * scale, y1 = Double(boxes[i * 4 + 3]) * scale
            let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard !rect.isNull, rect.width >= 2, rect.height >= 2 else { continue }
            result.append(Detection(rect: rect, score: scores[i], charCount: i < counts.count ? counts[i] : 100))
        }
        return result
    }

    /// Cascade : petit modèle pour les lignes courtes, plus grand si le texte déborde.
    func read(_ crop: RGBImage, charCount: Int64, charset: [String]) throws -> String {
        let tiers: [(file: String, width: Int, limit: Int)] = [("parseq30.onnx", 256, 25), ("parseq50.onnx", 384, 45),
                                                              ("parseq100.onnx", 768, Int.max)]
        var tier = charCount == 3 ? 0 : charCount == 2 ? 1 : 2
        var line = crop
        if Double(line.height) > Double(line.width) * 0.8 { line = line.rotatedCounterClockwise() }
        while true {
            let t = tiers[tier]
            let model = try SessionCache.shared.model(store.url(.ndlocr, t.file))
            // BGR, (pixel / 127,5) − 1, étiré à 24 × largeur du modèle.
            let tensor = line.resized(width: t.width, height: 24).chw(mean: [1, 1, 1], std: [1, 1, 1], scale: 1 / 127.5, bgr: true)
            let name = try model.inputNames().first ?? "images"
            guard let out = try model.run(floats: [name: (tensor, [1, 3, 24, t.width])]).values.first, out.shape.count == 3 else { return "" }
            let text = SequenceDecoder.parseq(out.floats, steps: out.shape[1], classes: out.shape[2], charset: charset)
            if text.count >= t.limit, tier < tiers.count - 1 { tier += 1; continue }
            return text
        }
    }
}
