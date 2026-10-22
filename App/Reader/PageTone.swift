// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PDFKit
import UIKit

/// Fond des pages PDF : blanc d'origine, adouci (crème, tamisé) ou inversé (sombre confortable).
/// Appliqué par `ToneOverlay`, un filtre de mélange posé sur toute la vue du lecteur au moment de l'affichage :
/// instantané, sur tout le PDF (pages pas encore dessinées comprises), sans redessiner ni reconstruire. (Avant :
/// peint page par page après PDFKit → page blanche puis teinte qui arrivait, à chaque page et à chaque changement.)
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

    /// Calques de mélange, de bas en haut (mêmes réglages que l'ancien dessin par page).
    var blends: [(filter: String, color: UIColor)] {
        switch self {
        case .normal: return []
        // Multiplier : le noir reste noir, le blanc devient crème.
        case .cream: return [("multiplyBlendMode", UIColor(red: 1.0, green: 0.94, blue: 0.82, alpha: 1))]
        case .dim: return [("multiplyBlendMode", UIColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1))]
        // Inverser, fond gris très foncé (pas noir pur), texte blanc cassé (moins éblouissant). Ancien calcul en
        // trois mélanges : m × (1 − (1 − (1 − c))(1 − g)) = m − m(1 − g)·c, avec m = (0,86 ; 0,84 ; 0,80) et
        // g = (0,11 ; 0,11 ; 0,12). Même résultat en deux : multiplier par k = m(1 − g), puis |k·c − m|.
        case .dark: return [("multiplyBlendMode", UIColor(red: 0.7654, green: 0.7476, blue: 0.704, alpha: 1)),
                            ("differenceBlendMode", UIColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1))]
        }
    }

    /// Couleur à donner au fond du lecteur pour qu'il garde sa teinte une fois filtré (l'inversion le retourne).
    func compensated(_ background: UIColor) -> UIColor {
        guard self == .dark else { return background }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        background.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: 1 - r, green: 1 - g, blue: 1 - b, alpha: a)
    }
}

/// Filtre de teinte posé sur toute la vue du lecteur (au-dessus des pages, sous rien d'interactif) : une vue par
/// calque de mélange (`compositingFilter`), composée par l'écran à l'affichage. Ne reçoit aucun toucher.
final class ToneOverlay: UIView {
    var tone: PageTone = .normal {
        didSet { guard tone != oldValue else { return }; rebuild() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("non utilisé") }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        for blend in tone.blends {
            let layerView = UIView(frame: bounds)
            layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            layerView.isUserInteractionEnabled = false
            layerView.backgroundColor = blend.color
            layerView.layer.compositingFilter = blend.filter
            addSubview(layerView)
        }
        isHidden = tone == .normal
    }
}

/// Page qui affiche sa version nettoyée par DE-GAN si elle est prête (`ScanSharpening`) et ses furigana. La teinte
/// (`PageTone`) n'est plus peinte ici : `ToneOverlay` sur la vue.
final class TonedPage: PDFPage {
    /// Clé de la page d'origine (document + page) : version nettoyée, furigana.
    var pageKey: String?
    /// Cadre d'origine de la page (avant rognage / coupe), là où l'image nettoyée se pose.
    var originalBox: CGRect = .zero

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
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
        if let key = pageKey, let marks = FuriganaLayer.marks(for: key), !marks.isEmpty {
            context.saveGState()
            context.concatenate(transform(for: box))
            context.clip(to: bounds(for: box))
            FuriganaLayer.draw(marks, in: context)
            context.restoreGState()
        }
    }
}

/// Délégué à poser sur le document **avant** de lire ses pages : elles deviennent des `TonedPage`
/// (les copies faites pour couper les doubles pages aussi).
final class TonedPageProvider: NSObject, PDFDocumentDelegate, @unchecked Sendable {
    static let shared = TonedPageProvider()
    func classForPage() -> AnyClass { TonedPage.self }
}
