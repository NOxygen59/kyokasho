// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Boîtes par caractère.
///
/// **Stratégie (V2)** — mesurée sur le Mac avec Vision (voir docs/OCR.md) :
/// 1. Vision `.accurate` fournit le texte japonais et, via `boundingBox(for:)`, une boîte par
///    caractère. On les garde si elles sont **cohérentes** (`validate`) : une par caractère, de
///    taille non nulle, rangées dans le sens de lecture, sans être toutes égales (ce qui
///    trahirait des boîtes par mot).
/// 2. Sinon, **découpage proportionnel** de la boîte de ligne : chaque caractère reçoit une part
///    selon sa largeur typographique (pleine chasse = 1, demi-chasse = 0,5).
/// Le niveau `.fast` de Vision ne reconnaît pas le japonais : pas de seconde passe possible.
public enum CharacterLayout {
    /// Largeur relative d'un caractère : 1 pour la pleine chasse (kanji, kana, ponctuation
    /// japonaise, formes pleine largeur), 0,5 pour la demi-chasse (latin, chiffres, demi-largeur).
    public static func widthWeight(_ c: Character) -> Double {
        guard let scalar = c.unicodeScalars.first else { return 0.5 }
        switch scalar.value {
        case 0x0000...0x024F, 0x2000...0x206F: return 0.5          // latin, ponctuation générale
        case 0xFF61...0xFF9F: return 0.5                            // katakana demi-largeur
        case 0x1100...0x11FF, 0x2E80...0x9FFF, 0xAC00...0xD7AF,
             0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x3FFFF: return 1          // CJK, kana, pleine largeur
        default: return c.isWhitespace ? 0.5 : 1
        }
    }

    /// Une ligne est verticale si sa boîte est nettement plus haute que large (en pixels).
    public static func isVertical(_ box: NormBox, imageAspect: Double, characters: Int) -> Bool {
        let pixelW = box.w * imageAspect
        let pixelH = box.h
        return characters > 1 && pixelH > pixelW * 1.5
    }

    /// Découpe proportionnelle de la boîte de ligne.
    public static func proportional(_ text: String, in box: NormBox, vertical: Bool) -> [NormBox] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }
        let weights = chars.map(widthWeight)
        let total = weights.reduce(0, +)
        guard total > 0 else { return chars.map { _ in box } }
        var result: [NormBox] = []
        result.reserveCapacity(chars.count)
        var offset = 0.0
        for w in weights {
            let part = w / total
            if vertical {
                result.append(NormBox(x: box.x, y: box.y + offset * box.h, w: box.w, h: part * box.h))
            } else {
                result.append(NormBox(x: box.x + offset * box.w, y: box.y, w: part * box.w, h: box.h))
            }
            offset += part
        }
        return result
    }

    /// Boîtes mesurées par le moteur jugées fiables ?
    public static func validate(_ boxes: [NormBox?], count: Int, vertical: Bool) -> Bool {
        guard boxes.count == count, count > 0 else { return false }
        let real = boxes.compactMap { $0 }
        guard real.count == count, real.allSatisfy({ $0.w > 0 && $0.h > 0 }) else { return false }
        if count == 1 { return true }
        // Toutes identiques = boîte de mot répétée : pas des boîtes par caractère.
        if Set(real.map { "\(($0.x * 1e4).rounded()),\(($0.y * 1e4).rounded())" }).count == 1 { return false }
        // Ordre de lecture croissant (tolérance pour les chevauchements légers).
        let positions = real.map { vertical ? $0.midY : $0.midX }
        return zip(positions, positions.dropFirst()).allSatisfy { $1 >= $0 - 0.002 }
    }
}

/// Taux d'erreur de caractères (CER) : distance d'édition / longueur de la référence.
public enum CharacterErrorRate {
    /// Normalisation commune (espaces et retours à la ligne ignorés : la mise en page ne compte pas).
    public static func normalize(_ s: String) -> [Character] {
        Array(s.filter { !$0.isWhitespace && !$0.isNewline })
    }

    public static func cer(reference: String, hypothesis: String) -> Double {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(levenshtein(ref, hyp)) / Double(ref.count)
    }

    /// Distance de Levenshtein, en O(n·m) temps et O(m) mémoire.
    public static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
