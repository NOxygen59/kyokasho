// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Images (PNG, JPEG, HEIC) vers PDF : taille de chaque page et de l'image dessinée.
///
/// Une page par image, à la forme de l'image (pas de bandes blanches) : son plus grand côté mesure celui d'une page A4
/// (842 pt), pour que le lecteur l'affiche comme les manuels. L'image est réduite à ``maxPixels`` sur son plus grand
/// côté : assez pour l'OCR (≈ 300 ppp sur A4), sans PDF énorme ni pic de mémoire avec des photos de 48 Mpx.
public enum ImagePDFLayout {
    public static let longSide: CGFloat = 842
    public static let maxPixels: CGFloat = 3508

    /// Taille de la page en points, même forme que l'image (`size` en pixels, orientation déjà appliquée).
    public static func pageSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 595, height: longSide) }
        let scale = longSide / max(size.width, size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Taille en pixels à garder : jamais agrandie, réduite au-delà de ``maxPixels``.
    public static func pixelSize(for size: CGSize) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxPixels, longest > 0 else { return size }
        let scale = maxPixels / longest
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
