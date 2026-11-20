// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Cache des pages « égalisées » (même hauteur) : une boîte source par page, écrite en `[[x, y, largeur, hauteur]]`.
/// C1.4 (audit du 09/11/2026) : une ligne sans ses quatre valeurs faisait planter la lecture du cache (`$0[3]`).
public enum EqualizedBoxes {
    /// Boîtes du cache, ou `nil` si une ligne n'a pas exactement quatre valeurs (cache à refaire).
    public static func rects(_ saved: [[CGFloat]]) -> [CGRect]? {
        guard saved.allSatisfy({ $0.count == 4 }) else { return nil }
        return saved.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
    }
}

/// Égalisation des hauteurs de page (PLAN-DATA03-001, E1 ; DEC-03/04 = A, NOxygen59 13/11/2026). Fonctions pures,
/// testées, utilisées par la préparation des pages (`ReaderController.equalizedDocument`). L'export ne convertit rien
/// point par point (DEC-01 = A) : il part des mêmes pages préparées que l'écran. `toEqualized`/`toSource` décrivent la
/// conversion (tests) ; elles serviront si un export aux tailles d'origine (DEC-01 B) est un jour demandé.
public enum PageEqualization {
    /// Écart au-delà duquel une page est redessinée à la hauteur commune.
    public static let tolerance: CGFloat = 0.03

    /// Hauteur de la page telle qu'affichée (rotation comprise), arrondie au point.
    public static func displayedHeight(box: CGRect, rotation: Int) -> CGFloat {
        (rotation % 180 == 0 ? box.height : box.width).rounded()
    }

    /// Hauteur la plus fréquente ; à égalité, la plus grande (DEC-03 = A : les petites pages sont agrandies, jamais
    /// réduites). Avant, l'égalité n'était pas départagée (ordre d'un dictionnaire, enquête D-03 constat 3).
    public static func commonHeight(_ heights: [CGFloat]) -> CGFloat? {
        var counts: [CGFloat: Int] = [:]
        for height in heights where height > 0 { counts[height.rounded(), default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key
    }

    /// Facteur à appliquer à une page de hauteur `height`, ou `nil` si elle reste telle quelle (écart ≤ 3 %).
    public static func factor(height: CGFloat, common: CGFloat) -> CGFloat? {
        guard height > 0, common > 0, abs(common / height - 1) > tolerance else { return nil }
        return common / height
    }

    /// Point de la page d'origine (cadre `sourceBox`) → point de la page égalisée : `(p − origine) × f`, comme le
    /// dessin de `ReaderController.scaledPage`.
    public static func toEqualized(_ point: CGPoint, sourceBox: CGRect, factor: CGFloat) -> CGPoint {
        CGPoint(x: (point.x - sourceBox.minX) * factor, y: (point.y - sourceBox.minY) * factor)
    }

    /// Hauteur commune qui a servi à préparer un PDF déjà égalisé (E3) : celle d'une page redessinée, reconnue à ce que
    /// sa taille diffère de son cadre d'origine. `nil` si aucune page n'a été redessinée.
    public static func referenceHeight(displayed: [(box: CGRect, rotation: Int)], sourceBoxes: [CGRect]) -> CGFloat? {
        for (i, page) in displayed.enumerated() where i < sourceBoxes.count {
            let source = sourceBoxes[i]
            if abs(page.box.width - source.width) > 0.5 || abs(page.box.height - source.height) > 0.5 {
                return displayedHeight(box: page.box, rotation: page.rotation)
            }
        }
        return nil
    }

    /// Inverse de `toEqualized` : point de la page égalisée → point de la page d'origine.
    public static func toSource(_ point: CGPoint, sourceBox: CGRect, factor: CGFloat) -> CGPoint {
        CGPoint(x: point.x / factor + sourceBox.minX, y: point.y / factor + sourceBox.minY)
    }
}
