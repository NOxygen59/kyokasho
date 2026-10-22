// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreImage
import PDFKit
import UIKit

/// Fond des pages PDF : blanc d'origine, adouci (crème, tamisé) ou inversé (sombre confortable).
/// Appliqué au dessin de chaque page (aucun calcul à part, aucun fichier modifié).
enum PageTone: String, CaseIterable, Identifiable {
    case normal, cream, dim, dark, smartDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Blanc (d'origine)"
        case .cream: return "Crème"
        case .dim: return "Tamisé"
        case .dark: return "Sombre (inversé)"
        case .smartDark: return "Sombre intelligent (expérimental)"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "sun.max"
        case .cream: return "cup.and.saucer"
        case .dim: return "sun.min"
        case .dark: return "moon"
        case .smartDark: return "moon.stars"
        }
    }

    static let storageKey = "reader.pageTone"

    /// Lu par PDFKit depuis ses fils de dessin : protégé par un verrou.
    private static let lock = NSLock()
    private static var stored = PageTone(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .normal
    static var current: PageTone {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Recouvre la page déjà dessinée (`rect` = zone visible du contexte).
    func apply(in context: CGContext, rect: CGRect) {
        guard self != .normal else { return }
        context.saveGState()
        func blend(_ mode: CGBlendMode, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            context.setBlendMode(mode)
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(rect)
        }
        switch self {
        case .normal: break
        case .cream:
            // Multiplier : le noir reste noir, le blanc devient crème.
            blend(.multiply, 1.0, 0.94, 0.82)
        case .dim:
            blend(.multiply, 0.80, 0.78, 0.74)
        case .dark, .smartDark:
            // Inverser, puis fond gris très foncé (pas noir pur) et texte blanc cassé (moins éblouissant).
            // (Sombre intelligent : seulement en attendant son image préparée, voir `ToneCache`.)
            blend(.difference, 1, 1, 1)
            blend(.screen, 0.11, 0.11, 0.12)
            blend(.multiply, 0.86, 0.84, 0.80)
        }
        context.restoreGState()
    }
}

/// Pages teintées préparées à l'avance (planche affichée, précédente et suivante, voir
/// `ReaderController.scheduleTone`) : le dessin pose l'image prête au lieu de teinter après coup (plus de page
/// blanche puis teinte). Lu par PDFKit depuis ses fils de dessin : protégé par un verrou.
enum ToneCache {
    static let longSide: CGFloat = 2000
    private static let lock = NSLock()
    private static var images: [String: CGImage] = [:]

    private static func full(_ key: String, _ tone: PageTone) -> String { key + "|" + tone.rawValue }

    static func image(for key: String, tone: PageTone) -> CGImage? { lock.withLock { images[full(key, tone)] } }

    /// Garde seulement ces pages (dans la teinte en cours) : le reste est libéré.
    static func keep(_ keys: Set<String>, tone: PageTone) {
        let wanted = Set(keys.map { full($0, tone) })
        lock.withLock { images = images.filter { wanted.contains($0.key) } }
    }

    static func clear() { lock.withLock { images = [:] } }

    /// Rend la page source (cadre `cropBox`, comme les pages nettoyées) puis la teinte. Hors du fil principal.
    static func prepare(key: String, fileURL: URL, page index: Int, tone: PageTone) -> Bool {
        guard tone != .normal, image(for: key, tone: tone) == nil,
              let document = CGPDFDocument(fileURL as CFURL), let page = document.page(at: index + 1) else { return false }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return false }
        let scale = longSide / max(box.width, box.height)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(rect)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        ctx.restoreGState()
        guard var result = ctx.makeImage() else { return false }
        if tone == .smartDark {
            // Clair ↔ sombre inversés, teintes gardées (inversion puis rotation de teinte d'un demi-tour), puis le
            // même adoucissement que « Sombre » (fond gris très foncé, blanc cassé).
            let inverted = CIImage(cgImage: result).applyingFilter("CIColorInvert")
                .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: Double.pi])
            guard let smart = CIContext(options: [.cacheIntermediates: false]).createCGImage(inverted, from: inverted.extent)
            else { return false }
            ctx.draw(smart, in: rect)
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.setFillColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            ctx.fill(rect)
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1)
            ctx.fill(rect)
            ctx.restoreGState()
        } else {
            tone.apply(in: ctx, rect: rect)
        }
        guard let toned = ctx.makeImage() else { return false }
        result = toned
        lock.withLock { images[full(key, tone)] = result }
        return true
    }
}

/// Page qui affiche sa version nettoyée par DE-GAN si elle est prête (`ScanSharpening`), puis applique
/// `PageTone.current` par-dessus.
final class TonedPage: PDFPage {
    /// Clé de la page d'origine (document + page) : version nettoyée, furigana.
    var pageKey: String?
    /// Cadre d'origine de la page (avant rognage / coupe), là où l'image nettoyée se pose.
    var originalBox: CGRect = .zero

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let tone = PageTone.current
        // Page teintée déjà prête (et assez nette pour le zoom actuel) : posée telle quelle, pas de teinte après coup.
        if tone != .normal, let key = pageKey, ScanSharpening.image(for: key) == nil,
           let toned = ToneCache.image(for: key, tone: tone), sharpEnough(toned, in: context) {
            context.saveGState()
            context.concatenate(transform(for: box))
            context.clip(to: bounds(for: box))
            context.interpolationQuality = .high
            context.draw(toned, in: originalBox)
            context.restoreGState()
            drawFurigana(box, in: context)
            return
        }
        if let key = pageKey, let image = ScanSharpening.image(for: key) {
            // Même repère que `super.draw` (origine du cadre + rotation, vérifié sur Mac) ;
            // la découpe garde seulement la partie visible (moitié de page coupée, rognage).
            let visible = bounds(for: box)
            context.saveGState()
            context.concatenate(transform(for: box))
            context.clip(to: visible)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(visible)
            context.interpolationQuality = .high
            context.draw(image, in: originalBox)
            context.restoreGState()
        } else {
            super.draw(with: box, to: context)
        }
        drawFurigana(box, in: context)
        guard tone != .normal else { return }
        tone.apply(in: context, rect: context.boundingBoxOfClipPath)
    }

    private func drawFurigana(_ box: PDFDisplayBox, in context: CGContext) {
        guard let key = pageKey, let marks = FuriganaLayer.marks(for: key), !marks.isEmpty else { return }
        context.saveGState()
        context.concatenate(transform(for: box))
        context.clip(to: bounds(for: box))
        FuriganaLayer.draw(marks, in: context)
        context.restoreGState()
    }

    /// Image assez fine pour l'échelle du dessin (zoom) ; sinon teinte peinte comme avant (nette à tout zoom).
    private func sharpEnough(_ image: CGImage, in context: CGContext) -> Bool {
        guard originalBox.width > 0 else { return false }
        let m = context.ctm
        let pixelsPerPoint = (m.a * m.a + m.b * m.b).squareRoot()
        return CGFloat(image.width) >= originalBox.width * pixelsPerPoint * 0.9
    }
}

/// Délégué à poser sur le document **avant** de lire ses pages : elles deviennent des `TonedPage`
/// (les copies faites pour couper les doubles pages aussi).
final class TonedPageProvider: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    static let shared = TonedPageProvider()
    func classForPage() -> AnyClass { TonedPage.self }
}
