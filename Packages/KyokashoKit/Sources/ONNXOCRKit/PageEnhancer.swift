// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit

/// Netteté des scans avec DE-GAN (modèle importé, voir `ModelSpec.degan`) : image en niveaux de gris
/// → fond blanc nettoyé, caractères noirs nets. Traitement par tuiles de 256 px qui se recouvrent
/// (fondu entre tuiles : pas de coutures), comme le script d'origine mais sans bords durs.
public enum PageEnhancer {
    static let tile = 256
    static let overlap = 32

    public static func isInstalled(store: ModelStore = .shared) -> Bool { store.isInstalled(.degan) }

    /// `gray` : `width × height` octets (0 = noir). Renvoie le même format.
    public static func enhance(gray: [UInt8], width: Int, height: Int, store: ModelStore = .shared) throws -> [UInt8] {
        precondition(gray.count == width * height)
        let model = try SessionCache.shared.model(store.url(.degan, "degan-binarize.onnx"), coreML: true)
        let t = tile
        func starts(_ n: Int) -> [Int] {
            guard n > t else { return [0] }
            var s = Array(stride(from: 0, to: n - t, by: t - 2 * overlap))
            s.append(n - t)
            return s
        }
        // Poids en rampe sur les bords de chaque tuile : les recouvrements se fondent.
        let ramp: [Float] = (0..<t).map { Float(min($0 + 1, t - $0, overlap)) / Float(overlap) }
        let ys = starts(height), xs = starts(width)
        // Grille régulière de tuiles : le poids total d'un pixel = poids en y × poids en x
        // (deux petits tableaux au lieu d'un tableau de la taille de la page).
        func axisWeight(_ origins: [Int], _ n: Int) -> [Float] {
            var w = [Float](repeating: 0, count: n)
            for o in origins { for i in 0..<min(t, n - o) { w[o + i] += ramp[i] } }
            return w
        }
        let weightY = axisWeight(ys, height), weightX = axisWeight(xs, width)
        var sum = [Float](repeating: 0, count: width * height)
        var input = [Float](repeating: 1, count: t * t)
        for y0 in ys {
            for x0 in xs {
                try Task.checkCancellation()
                let h = min(t, height - y0), w = min(t, width - x0)
                for i in input.indices { input[i] = 1 }
                for y in 0..<h {
                    let row = (y0 + y) * width + x0
                    for x in 0..<w { input[y * t + x] = Float(gray[row + x]) / 255 }
                }
                guard let out = try model.run(floats: ["image": (input, [1, 1, t, t])]).values.first?.floats,
                      out.count == t * t else { throw OCRError.renderFailed }
                for y in 0..<h {
                    let row = (y0 + y) * width + x0
                    for x in 0..<w {
                        let k = ramp[y] * ramp[x]
                        sum[row + x] += out[y * t + x] * k
                    }
                }
            }
        }
        // Le modèle sort ≈ 1 pour le fond : on étire [0,5 ; 0,95] vers [noir ; blanc] (seuil 0,95 du script
        // d'origine, mais en douceur pour garder des bords lisses).
        var result = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let w = weightY[y] * weightX[x]
                guard w > 0 else { continue }
                let v = (sum[row + x] / w - 0.5) / 0.45
                result[row + x] = UInt8(max(0, min(1, v)) * 255)
            }
        }
        return result
    }
}
