// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreText
import OCRKit
import XCTest
@testable import GLMOCRKit

/// Essai réel : seulement si `KYOKASHO_MODELS` contient `glmocr/` (et `ppocr5/` pour les lignes).
final class GLMOCREngineTests: XCTestCase {
    func testReadsJapanese() async throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_MODELS"] else { throw XCTSkip("modèles absents") }
        let engine = GLMOCREngine(store: ModelStore(root: URL(fileURLWithPath: path)))
        try XCTSkipUnless(engine.isAvailable)
        let w = 1400, h = 600
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 56, nil)
        for (i, text) in ["日本語の教科書を読む。", "漢字とひらがな"].enumerated() {
            let attr = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
            ctx.textPosition = CGPoint(x: 100, y: CGFloat(h - 150 - i * 110))
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        let page = try await engine.recognize(.image(try XCTUnwrap(ctx.makeImage())))
        print("GLM-OCR:", page.lines.map(\.text), page.durationMs, "ms")
        XCTAssertTrue(page.text.contains("教科書"))

        // Vertical : colonnes de droite à gauche (CoreText a changé la couleur de remplissage).
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (i, text) in ["縦書きの文章", "二行目"].enumerated() {
            for (j, c) in text.enumerated() {
                let attr = NSAttributedString(string: String(c), attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
                ctx.textPosition = CGPoint(x: CGFloat(w - 200 - i * 120), y: CGFloat(h - 100 - j * 64))
                CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
            }
        }
        let vertical = try await engine.recognize(.image(try XCTUnwrap(ctx.makeImage())))
        print("GLM-OCR vertical:", vertical.lines.map(\.text), vertical.durationMs, "ms")
        // Le modèle 4 bits lit 「緃」 au lieu de 「縦」 sur ce rendu synthétique (PP-OCRv5 et NDLOCR le lisent bien).
        XCTAssertEqual(vertical.lines.first?.text.hasSuffix("書きの文章"), true)
        XCTAssertEqual(vertical.lines.count, 2)
    }
}
