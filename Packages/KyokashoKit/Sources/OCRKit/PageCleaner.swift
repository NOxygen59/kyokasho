// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59


import CoreGraphics
import Foundation

/// Nettoyage d'une photo de page, comme un « scanner de poche » : on estime la couleur du papier sous
/// l'éclairage (ombres, jaunissement), on divise l'image par ce fond (papier → blanc), puis une courbe
/// renforce l'encre. Les couleurs et les dessins sont gardés (division canal par canal). Sans modèle,
/// quelques dizaines de millisecondes par page.
public enum PageCleaner {
    public enum Mode: String, CaseIterable, Sendable {
        /// Papier blanc, couleurs gardées.
        case color
        /// Noir et blanc contrasté (texte seul).
        case mono
    }

    /// `rgb` : `width × height × 3` octets. Renvoie le même format.
    public static func clean(_ rgb: [UInt8], width: Int, height: Int, mode: Mode) -> [UInt8] {
        precondition(rgb.count == width * height * 3)
        guard width > 8, height > 8 else { return rgb }
        // 1. Fond du papier, calculé en petit (1/8) : maximum local (l'encre disparaît), puis flou.
        let f = 8
        let sw = max(1, width / f), sh = max(1, height / f)
        var small = [Float](repeating: 0, count: sw * sh * 3)
        for y in 0..<sh {
            for x in 0..<sw {
                // Le plus clair du bloc 8 × 8 (le papier entre les traits).
                var m: (Float, Float, Float) = (0, 0, 0)
                for yy in (y * f)..<min(height, y * f + f) {
                    var i = (yy * width + x * f) * 3
                    for _ in (x * f)..<min(width, x * f + f) {
                        m.0 = max(m.0, Float(rgb[i])); m.1 = max(m.1, Float(rgb[i + 1])); m.2 = max(m.2, Float(rgb[i + 2]))
                        i += 3
                    }
                }
                let o = (y * sw + x) * 3
                small[o] = m.0; small[o + 1] = m.1; small[o + 2] = m.2
            }
        }
        // Gros caractères / dessins : maximum sur 5 × 5 blocs, puis deux flous 5 × 5 (fond lisse).
        let local = boxFilter(small, sw, sh, radius: 2, max: true)
        // Grands dessins / photos (plus grands que la fenêtre) : sans garde-fou, leur intérieur serait pris
        // pour du papier et « creusé ». Fond vu de plus loin (≈ 1/10 de la page de chaque côté), un peu atténué
        // pour suivre les ombres.
        let wide = boxFilter(local, sw, sh, radius: max(2, min(sw, sh) / 10), max: true)
        for i in small.indices { small[i] = max(local[i], wide[i] * 0.9) }
        small = boxFilter(boxFilter(small, sw, sh, radius: 2, max: false), sw, sh, radius: 2, max: false)

        // 2. Division par le fond (interpolé), courbe : papier → blanc, encre → plus foncée.
        var out = [UInt8](repeating: 255, count: rgb.count)
        let low: Float = mode == .mono ? 0.55 : 0.30, high: Float = 0.88
        for y in 0..<height {
            let fy = min(Float(sh - 1), max(0, (Float(y) + 0.5) / Float(f) - 0.5))
            let y0 = Int(fy), y1 = min(sh - 1, y0 + 1), ty = fy - Float(y0)
            for x in 0..<width {
                let fx = min(Float(sw - 1), max(0, (Float(x) + 0.5) / Float(f) - 0.5))
                let x0 = Int(fx), x1 = min(sw - 1, x0 + 1), tx = fx - Float(x0)
                let i = (y * width + x) * 3
                var values: [Float] = [0, 0, 0]
                for c in 0..<3 {
                    let a = small[(y0 * sw + x0) * 3 + c], b = small[(y0 * sw + x1) * 3 + c]
                    let d = small[(y1 * sw + x0) * 3 + c], e = small[(y1 * sw + x1) * 3 + c]
                    let bg = max(24, (a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty)
                    values[c] = min(1, Float(rgb[i + c]) / bg)
                }
                if mode == .mono {
                    let l = 0.299 * values[0] + 0.587 * values[1] + 0.114 * values[2]
                    values = [l, l, l]
                }
                for c in 0..<3 {
                    let v = max(0, min(1, (values[c] - low) / (high - low)))
                    // Courbe douce (bords des traits lisses), encre poussée vers le noir.
                    out[i + c] = UInt8((v * v * (3 - 2 * v)) * 255)
                }
            }
        }
        return out
    }

    /// Filtre carré (maximum ou moyenne), image Float à 3 canaux : une passe en lignes puis une en
    /// colonnes (même résultat qu'un carré, coût proportionnel au rayon et non à son carré).
    static func boxFilter(_ src: [Float], _ w: Int, _ h: Int, radius r: Int, max useMax: Bool) -> [Float] {
        func pass(_ input: [Float], horizontal: Bool) -> [Float] {
            var out = input
            let (outer, inner) = horizontal ? (h, w) : (w, h)
            for o in 0..<outer {
                for i in 0..<inner {
                    let lo = Swift.max(0, i - r), hi = Swift.min(inner - 1, i + r)
                    for c in 0..<3 {
                        var acc: Float = 0
                        for k in lo...hi {
                            let v = input[(horizontal ? o * w + k : k * w + o) * 3 + c]
                            acc = useMax ? Swift.max(acc, v) : acc + v
                        }
                        out[(horizontal ? o * w + i : i * w + o) * 3 + c] = useMax ? acc : acc / Float(hi - lo + 1)
                    }
                }
            }
            return out
        }
        return pass(pass(src, horizontal: true), horizontal: false)
    }
}
