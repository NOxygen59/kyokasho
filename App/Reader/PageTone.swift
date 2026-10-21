// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import UIKit

/// Fond des pages PDF : blanc d'origine, adouci (crème, tamisé) ou inversé (sombre confortable).
/// Appliqué au dessin de chaque page (aucun calcul à part, aucun fichier modifié).
enum PageTone: String, CaseIterable, Identifiable {
    case normal, cream, dim, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Blanc (d'origine)"
        case .cream: return "Crème"
        case .dim: return "Tamisé"
        case .dark: return "Sombre (inversé)"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "sun.max"
        case .cream: return "cup.and.saucer"
        case .dim: return "sun.min"
        case .dark: return "moon"
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
        case .dark:
            // Inverser, puis fond gris très foncé (pas noir pur) et texte blanc cassé (moins éblouissant).
            blend(.difference, 1, 1, 1)
            blend(.screen, 0.11, 0.11, 0.12)
            blend(.multiply, 0.86, 0.84, 0.80)
        }
        context.restoreGState()
    }
}

/// Page qui affiche sa version nettoyée par DE-GAN si elle est prête (`ScanSharpening`), puis applique
/// `PageTone.current` par-dessus.
final class TonedPage: PDFPage {
    /// Clé de la version nettoyée (document + page d'origine) ; `nil` : jamais remplacée.
    var sharpenKey: String?
    /// Cadre d'origine de la page (avant rognage / coupe), là où l'image nettoyée se pose.
    var originalBox: CGRect = .zero

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        if let key = sharpenKey, let image = ScanSharpening.image(for: key) {
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
        let tone = PageTone.current
        guard tone != .normal else { return }
        tone.apply(in: context, rect: context.boundingBoxOfClipPath)
    }
}

/// Délégué à poser sur le document **avant** de lire ses pages : elles deviennent des `TonedPage`
/// (les copies faites pour couper les doubles pages aussi).
final class TonedPageProvider: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    static let shared = TonedPageProvider()
    func classForPage() -> AnyClass { TonedPage.self }
}
