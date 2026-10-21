// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreText
import XCTest
import OCRKit
@testable import ONNXOCRKit

/// Essai réel des moteurs : seulement si `KYOKASHO_MODELS` pointe vers un dossier avec les modèles
/// (`ppocr5/…`, `ndlocr/…`). Sinon le test est sauté (les modèles ne sont jamais dans le dépôt).
final class ONNXEnginesTests: XCTestCase {
    var store: ModelStore!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_MODELS"] else {
            throw XCTSkip("KYOKASHO_MODELS non défini : modèles absents")
        }
        store = ModelStore(root: URL(fileURLWithPath: path))
    }

    /// Page blanche avec du texte japonais (horizontal ou vertical).
    func page(_ lines: [String], vertical: Bool) throws -> CGImage {
        let w = 1400, h = 1000
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("HiraMinProN-W3" as CFString, 56, nil)
        for (i, text) in lines.enumerated() {
            if vertical {
                for (j, c) in text.enumerated() {
                    let attr = NSAttributedString(string: String(c), attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
                    ctx.textPosition = CGPoint(x: CGFloat(w - 200 - i * 120), y: CGFloat(h - 120 - j * 64))
                    CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
                }
            } else {
                let attr = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
                ctx.textPosition = CGPoint(x: 100, y: CGFloat(h - 150 - i * 110))
                CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
            }
        }
        return try XCTUnwrap(ctx.makeImage())
    }

    func testDEGAN() throws {
        try XCTSkipUnless(PageEnhancer.isInstalled(store: store))
        // Page abîmée : fond gris taché, texte gris clair.
        let image = try page(["日本語の教科書を読む。", "漢字とひらがな"], vertical: false)
        let w = image.width, h = image.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let ctx = try XCTUnwrap(CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var seed: UInt32 = 7
        for i in gray.indices {
            seed = seed &* 1_103_515_245 &+ 12_345
            let noise = Int(seed >> 27)  // 0…31
            gray[i] = UInt8(min(255, 90 + Int(gray[i]) * 110 / 255 + noise))
        }
        let start = Date()
        let out = try PageEnhancer.enhance(gray: gray, width: w, height: h, store: store)
        print("DE-GAN:", w, "×", h, Int(Date().timeIntervalSince(start) * 1000), "ms")
        // Bas de page vide : redevenu blanc. Texte : resté sombre.
        let background = out[(h - 60) * w ..< (h - 50) * w].map(Int.init).reduce(0, +) / (10 * w)
        let dark = out.filter { $0 < 100 }.count
        print("DE-GAN: fond", background, "pixels sombres", dark)
        XCTAssertGreaterThan(background, 230)
        XCTAssertGreaterThan(dark, 2_000)
    }

    func testPPOCR() async throws {
        let engine = PPOCREngine(store: store)
        try XCTSkipUnless(engine.isAvailable)
        let result = try await engine.recognize(.image(page(["日本語の教科書を読む。", "漢字とひらがな"], vertical: false)))
        print("PP-OCRv5:", result.lines.map(\.text), result.durationMs, "ms")
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertTrue(result.text.contains("教科書"))
    }

    func testPPOCRVertical() async throws {
        let engine = PPOCREngine(store: store)
        try XCTSkipUnless(engine.isAvailable)
        let result = try await engine.recognize(.image(page(["縦書きの文章", "二行目です"], vertical: true)))
        print("PP-OCRv5 vertical:", result.lines.map(\.text), result.lines.map(\.vertical))
        XCTAssertEqual(result.lines.first?.text.contains("縦書き"), true)
    }

    func testNDLOCR() async throws {
        let engine = NDLOCREngine(store: store)
        try XCTSkipUnless(engine.isAvailable)
        let h = try await engine.recognize(.image(page(["日本語の教科書を読む。", "漢字とひらがな"], vertical: false)))
        print("NDLOCR:", h.lines.map(\.text), h.durationMs, "ms")
        XCTAssertTrue(h.text.contains("教科書"))
        let v = try await engine.recognize(.image(page(["縦書きの文章", "二行目です"], vertical: true)))
        print("NDLOCR vertical:", v.lines.map(\.text), v.lines.map(\.vertical))
        XCTAssertEqual(v.lines.first?.text.contains("縦書き"), true)
        XCTAssertEqual(v.lines.first?.vertical, true)
    }
}
