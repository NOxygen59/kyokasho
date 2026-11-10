// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Corrige les confusions d'écriture vérifiées dans les lectures de manuels japonais.
/// Une substitution remplace un seul graphème : les positions des boîtes OCR restent valides.
public enum JapaneseOCRText {
    /// Formes non japonaises rencontrées telles quelles dans les lectures OvisOCR2, ramenées au shinjitai japonais.
    ///
    /// Origine : retour terrain T6 du 10/11/2026, relevé DeepSeek sur le manuel complet
    /// (68 caractères mesurés après conversion ; 62 paires retenues ici, 6 écartées, voir plus bas).
    /// Les entrées sont des paires simplifié chinois → japonais ou 旧字体 → shinjitai : la cible est le
    /// caractère japonais standard, jamais une hypothèse de lecture. Un caractère dont la forme japonaise
    /// dépend du contexte n'entre pas dans cette table : il faut relire l'image.
    ///
    /// Invariant : **un graphème pour un graphème**. `OCRLine.charBoxes` contient une boîte par graphème de
    /// `OCRLine.text` (`OCRModels.swift`) ; toute conversion de longueur différente décalerait les boîtes et
    /// fausserait la sélection, le furigana et le survol. Aucune cible n'est aussi une source : la conversion
    /// est idempotente en une seule passe, sans chaîne de remplacements.
    ///
    /// Écartés volontairement (ne pas les ajouter sans relire le contexte sur l'image) :
    /// - `桩` (U+6869) : 粧 dans « 化粧合板 » (p. 216), 柾 dans « 柾目 » (p. 233) — ambigu.
    /// - `兰` (U+5170) : la phrase est « フランス窓 », cible `ラ`, pas `蘭`.
    /// - `凇` (U+51C7) et `雾` (U+96FE) : « 雰囲気 », cible `雰` ; `雾`→`霧` donnerait « 霧囲気 », toujours faux.
    /// - `杀` (U+6740) : « 糸面 », cible `糸` ; la forme japonaise du caractère est `殺`.
    /// - `踰` (U+8E30) : « 階段幅踰場幅 », cible `踊` (踊場) ; ce n'est pas une variante graphique.
    static let substitutions: [Character: Character] = [
        "业": "業",
        "为": "為",
        "值": "値",
        "內": "内",
        "净": "浄",
        "则": "則",
        "剂": "剤",
        "动": "動",
        "单": "単",
        "压": "圧",
        "发": "発",
        "变": "変",
        "团": "団",
        "图": "図", // entrée historique de la table, antérieure au relevé T6
        "处": "処",
        "娛": "娯",
        "娱": "娯",
        "对": "対",
        "專": "専",
        "德": "徳",
        "户": "戸",
        "换": "換",
        "揭": "掲",
        "擊": "撃",
        "收": "収",
        "效": "効",
        "时": "時",
        "查": "査",
        "栈": "桟",
        "樂": "楽",
        "樞": "枢",
        "污": "汚",
        "润": "潤",
        "淚": "涙",
        "渴": "渇",
        "獎": "奨",
        "现": "現",
        "發": "発",
        "綠": "緑",
        "约": "約",
        "细": "細",
        "给": "給",
        "维": "維",
        "缩": "縮",
        "聽": "聴",
        "藏": "蔵",
        "视": "視",
        "设": "設",
        "轻": "軽",
        "边": "辺",
        "达": "達",
        "进": "進",
        "铁": "鉄",
        "铸": "鋳",
        "长": "長",
        "闭": "閉",
        "阈": "閾",
        "韧": "靭",
        "顏": "顔",
        "项": "項",
        "颜": "顔",
        "风": "風",
        "鲜": "鮮",
    ]

    public static func normalize(_ text: String) -> String {
        guard text.contains(where: isSubstituted) else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var changed = false
        for character in text {
            if let replacement = substitutions[character] {
                result.append(replacement)
                changed = true
            } else {
                result.append(character)
            }
        }
        // Rien remplacé : on rend la chaîne d'origine, sans copie inutile (le texte d'une page peut être long).
        return changed ? result : text
    }

    public static func normalize(_ page: OCRPage) -> OCRPage {
        var result = page
        for index in result.lines.indices where result.lines[index].edited != true {
            result.lines[index].text = normalize(result.lines[index].text)
        }
        return result
    }

    private static func isSubstituted(_ character: Character) -> Bool {
        substitutions[character] != nil
    }
}
