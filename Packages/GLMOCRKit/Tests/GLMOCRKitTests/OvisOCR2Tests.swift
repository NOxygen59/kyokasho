// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics
import CoreText
import Foundation
@testable import GLMOCRKit
import MLX
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

    /// Page pleine (1600 px de haut, ~30 lignes) comme une vraie page de manuel : `KYOKASHO_FULLPAGE=1`.
    func testFullPageOvis() async throws {
        guard ProcessInfo.processInfo.environment["KYOKASHO_FULLPAGE"] != nil,
              let root = ProcessInfo.processInfo.environment["KYOKASHO_MODELS"] else { throw XCTSkip("désactivé") }
        let text = "天井を張る場合、一般的に小屋裏、天井裏にスペースをとる。上階からの防音にも役立ち、配管、配線、空調機器、照明器具等を取り付ける空間になる。"
        let w = 1131, h = 1600
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, 30, nil)
        let chars = Array(text)
        for i in 0..<30 {
            let start = (i * 31) % chars.count
            let line = String((chars + chars)[start..<(start + 33)])
            let attr = NSAttributedString(string: line, attributes: [.init(kCTFontAttributeName as String): font,
                                                                     .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            ctx.textPosition = CGPoint(x: 50, y: h - 80 - i * 50)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        let reader = OvisOCR2Reader(store: ModelStore(root: URL(fileURLWithPath: root)))
        let start = Date()
        let md = try await reader.read(.image(ctx.makeImage()!))
        print("FULL OVIS \(String(format: "%.1f", Date().timeIntervalSince(start))) s, \(md.count) caractères")
    }

    /// Vraies pages du manuel de l'utilisateur (jamais dans le dépôt) :
    /// `KYOKASHO_SAMPLE_PDF=<pdf> KYOKASHO_SAMPLE_PAGES=1,2 KYOKASHO_MODELS=<dossier> swift test --filter testRealSample`.
    func testRealSample() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let pdf = env["KYOKASHO_SAMPLE_PDF"], let root = env["KYOKASHO_MODELS"] else { throw XCTSkip("désactivé") }
        let store = ModelStore(root: URL(fileURLWithPath: root))
        let pages = (env["KYOKASHO_SAMPLE_PAGES"] ?? "1").split(separator: ",").compactMap { Int($0) }
        let url = URL(fileURLWithPath: pdf)
        for p in pages {
            let base = try await VisionOCREngine().recognize(.pdfPage(url: url, index: p))
            let chars = base.lines.reduce(0) { $0 + $1.text.count }
            let budget = min(4096, max(384, chars * 2 + 256))
            print("PAGE \(p) : Vision \(base.lines.count) lignes, \(chars) caractères, budget \(budget)")
            let only = env["KYOKASHO_ONLY"]
            for (name, read) in [("OVIS", { try await OvisOCR2Reader(store: store).read(.pdfPage(url: url, index: p), maxTokens: budget) }),
                                 ("QWEN", { try await Qwen3VLReader(store: store).read(.pdfPage(url: url, index: p), maxTokens: budget) })]
                as [(String, () async throws -> String)] where only == nil || only == name {
                MLX.GPU.resetPeakMemory()
                let start = Date()
                let text = try await read()
                print("\(name) p.\(p) : \(String(format: "%.1f", Date().timeIntervalSince(start))) s, pic mémoire GPU \(MLX.GPU.peakMemory / 1_048_576) Mo, \(text.count) caractères")
                print(String(text.prefix(600)))
                if let dump = env["KYOKASHO_DUMP"] { try? text.write(toFile: "\(dump)/\(name.lowercased())-\(p).md", atomically: true, encoding: .utf8) }
                print("— diff avec Vision : \(OCRReferenceDiff.suggestions(base, reference: text).count) ligne(s) différente(s) sur \(base.lines.count)")
            }
        }
    }

    /// Mesure d'une vraie page (chargement et compilation à part) : `KYOKASHO_BENCH_PDF=<pdf> KYOKASHO_BENCH_PAGE=<index>`
    /// (+ `MLX_METAL_LANGUAGE_VERSION=30` = conditions iOS 16).
    func testProfileRealPage() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["KYOKASHO_MODELS"], let pdf = env["KYOKASHO_BENCH_PDF"] else { throw XCTSkip("désactivé") }
        let index = Int(env["KYOKASHO_BENCH_PAGE"] ?? "") ?? 2
        let reader = OvisOCR2Reader(store: ModelStore(root: URL(fileURLWithPath: root)))
        let input = OCRInput.pdfPage(url: URL(fileURLWithPath: pdf), index: index)
        _ = try await reader.read(input, maxTokens: 3072)
        let start = Date()
        let text = try await reader.read(input, maxTokens: 3072)
        print("BENCH \(String(format: "%.1f", Date().timeIntervalSince(start))) s, \(text.count) caractères")
    }

    /// Conversation : `KYOKASHO_CHAT=1` (+ `KYOKASHO_MODELS`). Deux tours : l'historique est bien gardé.
    func testQwenChatAnswers() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KYOKASHO_CHAT"] != nil, let root = env["KYOKASHO_MODELS"] else { throw XCTSkip("désactivé") }
        let chat = QwenChat(store: ModelStore(root: URL(fileURLWithPath: root)))
        try await chat.start(history: [])
        var first = ""
        for try await chunk in chat.stream("Comment se lit 天井 et que veut dire ce mot ?") { first += chunk }
        print("CHAT 1 : \(first)")
        var second = ""
        for try await chunk in chat.stream("Et le mot suivant dans un plafond : 野縁 ?") { second += chunk }
        print("CHAT 2 : \(second)")
        await chat.stop()
        XCTAssertTrue(first.contains("てんじょう"), "lecture de 天井")
        XCTAssertFalse(second.isEmpty)
    }

    /// Traduction d'une vraie page (Markdown d'OvisOCR2) : `KYOKASHO_TRANSLATE=<fichier .md>`.
    func testQwenTranslatesPage() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let file = env["KYOKASHO_TRANSLATE"], let root = env["KYOKASHO_MODELS"] else { throw XCTSkip("désactivé") }
        let md = try String(contentsOfFile: file, encoding: .utf8)
        let reader = Qwen3VLReader(store: ModelStore(root: URL(fileURLWithPath: root)))
        MLX.GPU.resetPeakMemory()
        let start = Date()
        let fr = try await reader.translate(markdown: md)
        print("TRAD \(String(format: "%.1f", Date().timeIntervalSince(start))) s, pic GPU \(MLX.GPU.peakMemory / 1_048_576) Mo, \(md.count) → \(fr.count) caractères")
        print(fr)
        if let dump = env["KYOKASHO_DUMP"] { try? fr.write(toFile: "\(dump)/fr.md", atomically: true, encoding: .utf8) }
        XCTAssertEqual(AILayout.blocks(fr).filter { if case .figure = $0 { return true }; return false }.count,
                       AILayout.blocks(md).filter { if case .figure = $0 { return true }; return false }.count, "figures gardées")
    }
}
