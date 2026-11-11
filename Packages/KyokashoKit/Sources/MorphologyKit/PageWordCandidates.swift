// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Mots d'une page à proposer pour « Créer des cartes de cette page » (PLAN-CARTES-001, étape E2 ; plan approuvé par
/// NOxygen59 le 11/11/2026, DEC-CA-02 et DEC-CA-06 = A).
///
/// Fonction pure, testée : jetons MeCab/UniDic → forme de dictionnaire → filtre des mots grammaticaux → liste sans
/// doublon, **dans l'ordre d'apparition** sur la page. La recherche dans les dictionnaires (seuls les mots trouvés sont
/// proposés) et le repérage des cartes déjà créées se font après, hors de cette fonction.
///
/// Retirés (DEC-CA-02) : particules (助詞), auxiliaires (助動詞), symboles et ponctuation (補助記号, 記号, 空白),
/// préfixes et suffixes (接頭辞, 接尾辞), pronoms (代名詞), interjections (感動詞), conjonctions (接続詞 : しかし,
/// だから), déterminants (連体詞 : この, その), hésitations (フィラー), nombres (数詞), verbes « non autonomes »
/// (非自立可能 : する, ある, いる, なる… outils de grammaire plus que vocabulaire), mots dont la forme de dictionnaire
/// est un seul kana, et mots sans caractère japonais (chiffres, lettres latines). Revue DeepSeek D-07 (F5-F7) :
/// conjonctions et déterminants ajoutés ; un mot écrit d'un seul kana mais de forme pleine (え → 絵) reste proposé ;
/// こと et もの, noms ordinaires pour UniDic, ne sont pas retirés.
public enum PageWordCandidates {
    public struct Word: Equatable, Sendable {
        /// Forme à chercher dans les dictionnaires (lemme UniDic, sans son suffixe anglais).
        public let expression: String
        /// Forme telle qu'écrite sur la page, cherchée si la forme de dictionnaire ne donne rien.
        public let surface: String
        /// Lecture en hiragana quand elle vaut pour `expression` (mot écrit sous sa forme de base), sinon vide.
        public let readingHint: String

        public init(expression: String, surface: String, readingHint: String) {
            self.expression = expression
            self.surface = surface
            self.readingHint = readingHint
        }
    }

    static let excludedCategories: Set<String> = ["助詞", "助動詞", "補助記号", "記号", "空白", "接頭辞", "接尾辞", "代名詞",
                                                  "感動詞", "接続詞", "連体詞", "フィラー"]
    static let excludedSubcategories: Set<String> = ["数詞", "非自立可能"]

    /// Mots retenus, dans l'ordre d'apparition, sans doublon (même forme de dictionnaire) et hors de `excluding`
    /// (termes du lexique du cours, déjà proposés à part).
    public static func words(_ tokens: [MeCab.Token], excluding: Set<String> = []) -> [Word] {
        var seen = excluding
        var out: [Word] = []
        for token in tokens {
            guard let category = token.pos.first, !excludedCategories.contains(category),
                  token.pos.dropFirst().allSatisfy({ !excludedSubcategories.contains($0) }) else { continue }
            let expression = dictionaryForm(token)
            guard isWorthACard(expression), !seen.contains(expression),
                  !seen.contains(token.surface) else { continue }
            seen.insert(expression)
            out.append(Word(expression: expression, surface: token.surface,
                            readingHint: token.surface == expression ? token.reading : ""))
        }
        return out
    }

    /// Lemme UniDic sans son suffixe d'origine (« コンピューター-computer » → « コンピューター ») ; la forme écrite
    /// si le lemme est absent.
    static func dictionaryForm(_ token: MeCab.Token) -> String {
        var lemma = token.lemma
        if let dash = lemma.firstIndex(of: "-"), dash != lemma.startIndex,
           lemma[lemma.index(after: dash)...].allSatisfy({ $0.isASCII }) {
            lemma = String(lemma[..<dash])
        }
        return lemma.isEmpty ? token.surface : lemma
    }

    /// Au moins un caractère japonais, et pas un seul kana isolé.
    static func isWorthACard(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.contains(where: isJapanese) else { return false }
        return !(scalars.count == 1 && isKana(scalars[0]))
    }

    private static func isKana(_ s: Unicode.Scalar) -> Bool { (0x3041...0x30FF).contains(s.value) }

    private static func isJapanese(_ s: Unicode.Scalar) -> Bool {
        isKana(s) || (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) || s.value == 0x3005
    }
}
