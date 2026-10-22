// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreText
import Foundation
@testable import GLMOCRKit
import OCRKit
import XCTest

/// Avec le vrai modèle seulement : `KYOKASHO_MODELS=<dossier contenant ovisocr2/> swift test --filter OvisOCR2Tests`.
final class OvisOCR2Tests: XCTestCase {
    /// Page blanche avec quelques lignes de japonais horizontal (Hiragino), comme un manuel.
    private func page(_ lines: [String]) -> CGImage {
        let w = 1200, h = 900
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, 40, nil)
        for (i, text) in lines.enumerated() {
            let attr = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font,
                                                                     .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            ctx.textPosition = CGPoint(x: 60, y: h - 120 - i * 80)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        return ctx.makeImage()!
    }

    func testReadsJapanesePage() async throws {
        guard let root = ProcessInfo.processInfo.environment["KYOKASHO_MODELS"] else { throw XCTSkip("KYOKASHO_MODELS absent") }
        let reader = OvisOCR2Reader(store: ModelStore(root: URL(fileURLWithPath: root)))
        XCTAssertTrue(reader.isAvailable)
        let lines = ["天井を張る場合、一般的に小屋裏、", "天井裏にスペースをとる。", "上階からの防音にも役立つ。"]
        let start = Date()
        let markdown = try await reader.read(.image(page(lines)), maxTokens: 512)
        print("OVIS (\(String(format: "%.1f", Date().timeIntervalSince(start))) s):\n\(markdown)")
        let plain = String(OCRReferenceDiff.plain(markdown))
        for line in lines { XCTAssertTrue(plain.contains(line.filter { !$0.isWhitespace }), "manque : \(line)") }
    }

    func testQwen3VLReadsInteriorDesignPage() async throws {
        guard let root = ProcessInfo.processInfo.environment["KYOKASHO_MODELS"] else { throw XCTSkip("KYOKASHO_MODELS absent") }
        let reader = Qwen3VLReader(store: ModelStore(root: URL(fileURLWithPath: root)))
        guard reader.isAvailable else { throw XCTSkip("Qwen3-VL-4B absent") }
        let lines = ["天井は小屋組、上階の構造体から吊られる。", "基本的には吊り木または吊りボルトで、", "野縁受けを吊り、野縁を付ける。", "照明器具の取り付け位置を決める。"]
        let start = Date()
        let markdown = try await reader.read(.image(page(lines)), maxTokens: 512)
        print("QWEN (\(String(format: "%.1f", Date().timeIntervalSince(start))) s):\n\(markdown)")
        let plain = String(OCRReferenceDiff.plain(markdown))
        for line in lines { XCTAssertTrue(plain.contains(line.filter { !$0.isWhitespace }), "manque : \(line)") }
    }
}
