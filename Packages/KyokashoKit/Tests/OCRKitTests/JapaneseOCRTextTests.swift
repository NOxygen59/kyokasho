// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

/// Table de conversion des formes chinoises relevées dans les lectures OvisOCR2 (retour terrain T6, 10/11/2026).
final class JapaneseOCRTextTests: XCTestCase {
    /// Chaque paire de la table convertit bien sa forme source, et change la longueur en graphèmes de zéro.
    func testChaquePaireReleveeEstAppliquee() {
        for (source, target) in JapaneseOCRText.substitutions {
            XCTAssertEqual(JapaneseOCRText.normalize(String(source)), String(target), "paire \(source) → \(target)")
            XCTAssertEqual(String(target).count, 1, "la cible \(target) doit tenir en un graphème")
        }
    }

    /// Aucune cible n'est aussi une source : une seule passe suffit, donc pas de conversion en chaîne
    /// (`對` lue `对` puis convertie deux fois). La table doit rester idempotente.
    func testAucuneCibleNEstAussiUneSource() {
        for target in JapaneseOCRText.substitutions.values {
            XCTAssertNil(JapaneseOCRText.substitutions[target], "\(target) est à la fois cible et source")
        }
    }

    /// Texte japonais déjà correct : la table ne doit toucher à rien. Mots du domaine du manuel.
    func testTexteJaponaisCorrectNonModifie() {
        let corrects = [
            "対流", "単板", "汚れ", "溶剤", "図面", "換気", "化粧合板",
            "階段", "踊場", "販売", "断熱材", "給湯", "収縮", "縫製",
            "相対湿度、絶対値", "郷土色", "内装", "戸棚", "鉄筋",
        ]
        for texte in corrects {
            XCTAssertEqual(JapaneseOCRText.normalize(texte), texte)
        }
    }

    /// Les cas de contexte écartés de la table restent intacts : quand on les reverra dans une lecture,
    /// il faudra relire l'image, pas ajouter une paire.
    func testCaracteresEcartesRestentIntacts() {
        for caractere in ["桩", "兰", "凇", "杀", "踰", "雾"] as [Character] {
            XCTAssertEqual(JapaneseOCRText.normalize(String(caractere)), String(caractere))
            XCTAssertNil(JapaneseOCRText.substitutions[caractere])
        }
    }

    /// Invariant de la table : un graphème pour un graphème. Un texte mêlant kanji, kana et latin
    /// garde exactement le même nombre de graphèmes, donc les boîtes OCR restent alignées.
    func testLongueurDeGraphemesConservee() {
        let texte = "单板の汚れ 对流12.5% 換気「図面」"
        let converti = JapaneseOCRText.normalize(texte)
        XCTAssertEqual(converti.count, texte.count)
        XCTAssertEqual(converti, "単板の汚れ 対流12.5% 換気「図面」")
    }

    /// Une page : les lignes non corrigées à la main sont converties, les lignes corrigées ne bougent pas,
    /// et les boîtes par caractère restent valides (mêmes positions, une boîte par graphème).
    func testPageNormaliseeConserveLesBoitesEtLesCorrections() {
        let box = NormBox(x: 0.1, y: 0.1, w: 0.8, h: 0.1)
        let texteLu = "单板と对流"
        let ligneLue = OCRLine(
            text: texteLu,
            box: box,
            charBoxes: CharacterLayout.proportional(texteLu, in: box, vertical: false),
            measuredCharBoxes: true,
            vertical: false,
            confidence: 0.9
        )
        let boites = ligneLue.charBoxes

        var ligneCorrigee = OCRLine(
            text: texteLu,
            box: box,
            charBoxes: CharacterLayout.proportional(texteLu, in: box, vertical: false),
            measuredCharBoxes: true,
            vertical: false,
            confidence: 0.9
        )
        ligneCorrigee.edited = true

        let page = OCRPage(engine: "ovisocr2", lines: [ligneLue, ligneCorrigee], durationMs: 1)
        let normalisee = JapaneseOCRText.normalize(page)

        XCTAssertEqual(normalisee.lines[0].text, "単板と対流")
        XCTAssertEqual(normalisee.lines[0].charBoxes, boites)
        XCTAssertEqual(normalisee.lines[0].charBoxes.count, normalisee.lines[0].text.count)
        // Ligne corrigée à la main : le texte de l'utilisateur prime sur la table.
        XCTAssertEqual(normalisee.lines[1].text, texteLu)

        XCTAssertEqual(page.lines[0].text, texteLu)
    }

    /// Convertir deux fois donne le même texte : la conversion est stable pour le cache et les relectures.
    func testNormalisationIdempotente() {
        let texte = "业余の窓、图面、给排水"
        let uneFois = JapaneseOCRText.normalize(texte)
        XCTAssertEqual(JapaneseOCRText.normalize(uneFois), uneFois)
    }
}
