// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import ReaderCore
import UIKit

/// Fond des pages PDF : blanc d'origine, adouci (crème, tamisé) ou inversé (sombre confortable, sépia nuit).
/// Appliqué au dessin de chaque page (aucun calcul à part, aucun fichier modifié).
///
/// « Sombre intelligent (expérimental) » a été retiré (RET-027, #42) : `migrateStoredSetting()` remplace l'ancienne
/// valeur enregistrée au lancement.
enum PageTone: String, CaseIterable, Identifiable {
    case normal, cream, dim, dark, sepiaNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return String(localized: "Blanc (d'origine)")
        case .cream: return String(localized: "Crème")
        case .dim: return String(localized: "Tamisé")
        case .dark: return String(localized: "Sombre (inversé)")
        case .sepiaNight: return String(localized: "Sépia nuit")
        }
    }

    var icon: String {
        switch self {
        case .normal: return "sun.max"
        case .cream: return "cup.and.saucer"
        case .dim: return "sun.min"
        case .dark: return "moon"
        case .sepiaNight: return "moon.haze"
        }
    }

    static let storageKey = "reader.pageTone"

    /// Au lancement, avant toute lecture du réglage : une valeur retirée devient la teinte qui la remplace
    /// (`PageToneMigration`), au lieu de retomber sur « Blanc ».
    static func migrateStoredSetting() {
        let defaults = UserDefaults.standard
        guard let replacement = PageToneMigration.migrated(defaults.string(forKey: storageKey)) else { return }
        defaults.set(replacement, forKey: storageKey)
        Diagnostics.log("Fond des pages : réglage retiré remplacé par « \(replacement) »", "lecteur")
    }

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
        case .dark:
            // Inverser, puis fond gris très foncé (pas noir pur) et texte blanc cassé (moins éblouissant).
            blend(.difference, 1, 1, 1)
            blend(.screen, 0.11, 0.11, 0.12)
            blend(.multiply, 0.86, 0.84, 0.80)
        case .sepiaNight:
            // Inverser, puis fond brun sépia foncé et texte beige chaud : ni blanc pur ni noir pur, contraste
            // plus faible que « Sombre » et moins de bleu le soir (RET-027, #42).
            blend(.difference, 1, 1, 1)
            blend(.screen, 0.17, 0.12, 0.07)
            blend(.multiply, 0.90, 0.78, 0.60)
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
        tone.apply(in: ctx, rect: rect)
        guard let toned = ctx.makeImage() else { return false }
        lock.withLock { images[full(key, tone)] = toned }
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
    /// Cadre de la page dans le PDF d'origine. Différent de `originalBox` si la page a été remise à la hauteur
    /// commune du livre : les furigana (calculés sur l'origine) sont alors agrandis d'autant.
    var sourceBox: CGRect = .zero

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
        guard let key = pageKey, let page = FuriganaLayer.prepared(for: key), !page.marks.isEmpty else { return }
        context.saveGState()
        context.concatenate(transform(for: box))
        context.clip(to: bounds(for: box))
        if sourceBox.height > 0, originalBox.height > 0, abs(originalBox.height / sourceBox.height - 1) > 0.001 {
            let f = originalBox.height / sourceBox.height
            context.translateBy(x: originalBox.minX, y: originalBox.minY)
            context.scaleBy(x: f, y: f)
            context.translateBy(x: -sourceBox.minX, y: -sourceBox.minY)
        }
        FuriganaLayer.draw(page, in: context)
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
