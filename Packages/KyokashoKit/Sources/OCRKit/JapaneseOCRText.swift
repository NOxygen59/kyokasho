// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Corrige les confusions d'écriture vérifiées dans les lectures de manuels japonais.
/// Une substitution remplace un seul graphème : les positions des boîtes OCR restent valides.
public enum JapaneseOCRText {
    public static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "图", with: "図")
    }

    public static func normalize(_ page: OCRPage) -> OCRPage {
        var result = page
        for index in result.lines.indices where result.lines[index].edited != true {
            result.lines[index].text = normalize(result.lines[index].text)
        }
        return result
    }
}
