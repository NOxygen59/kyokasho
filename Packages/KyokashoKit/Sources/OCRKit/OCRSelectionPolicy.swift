// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore

/// Règle **unique** de choix de l'OCR d'une page (« OCR retenu »), partagée par tous les chemins du lecteur : page
/// posée, panneau Texte, toucher d'un mot, surlignage, rafraîchissement après une lecture IA.
///
/// Avant (recette iPad 1.5.2, enquête `ENQUETE-CLAUDE-FURIGANA-IPAD-VS-MAC-5ec3952`), la page posée relisait le cache dans
/// l'ordre des moteurs, tandis que « Lire la page », la file de lecture et le toucher choisissaient d'après les modèles
/// **installés** : en Auto sans NDLOCR ni PP-OCRv5, ils rendaient le cache Vision d'un livre déjà lu par NDLOCR, et les
/// deux résultats se remplaçaient à chaque geste (223 furigana, puis 74).
///
/// Décisions de NOxygen59 du 07/11/2026 (plan `PLAN-RECONSTRUCTION-OCR-PDF-5ec3952`, D1 et D2) :
/// - en Auto, une lecture **déjà faite** et valide passe avant une nouvelle lecture, même si son modèle n'est plus
///   installé : texte du PDF s'il est vrai, puis NDLOCR, PP-OCRv5, GLM-OCR, Apple Vision ;
/// - un moteur choisi dans le panneau Texte est **retenu pour la page** (`pinned`) ; un moteur réglé (document ou
///   défaut de l'app) vaut pour toutes les pages. L'ordre exprime une politique, pas une qualité garantie.
public enum OCRSelectionPolicy {
    /// Ordre de recherche des lectures déjà faites. `pinned` : moteur choisi pour cette page.
    /// `hasTextLayer` : vraie couche de texte (pas un scan avec image pleine page).
    public static func cacheOrder(choice: OCREngineChoice, pinned: String?, hasTextLayer: Bool) -> [String] {
        if let pinned { return [pinned] }
        guard choice == .auto else { return [engineID(choice)] }
        let scans = [OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.glmocr, OCREngineID.vision]
        return hasTextLayer ? [OCREngineID.pdfText] + scans : scans
    }

    /// Moteur d'une **nouvelle** lecture, quand aucune lecture faite n'est réutilisable. En Auto : texte du PDF s'il est
    /// vrai, sinon le premier modèle japonais installé (NDLOCR, PP-OCRv5), sinon Apple Vision, toujours présent.
    public static func engineToRead(choice: OCREngineChoice, pinned: String?, hasTextLayer: Bool,
                                    isInstalled: (String) -> Bool) -> String {
        if let pinned { return pinned }
        guard choice == .auto else { return engineID(choice) }
        if hasTextLayer { return OCREngineID.pdfText }
        return [OCREngineID.ndlocr, OCREngineID.ppocr5].first(where: isInstalled) ?? OCREngineID.vision
    }

    /// Ordre dans lequel lire les lectures déjà faites d'une page : celles du choix (`cacheOrder`) d'abord, puis tous les
    /// autres moteurs, **texte du PDF compris**, sans doublon. Les suivants ne servent qu'à trouver une version
    /// **corrigée** (D7) : le texte du PDF corrigé à la main compte même quand un moteur de scan est réglé ou choisi
    /// (contre-revue Codex de 4522367) ; non corrigé, il n'est jamais pris à la place du choix.
    public static func lookupOrder(choice: OCREngineChoice, pinned: String?, hasTextLayer: Bool) -> [String] {
        let all = [OCREngineID.pdfText, OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.glmocr, OCREngineID.vision]
        var order = cacheOrder(choice: choice, pinned: pinned, hasTextLayer: hasTextLayer)
        if choice != .auto || pinned != nil { order.append(engineID(choice)) }
        order += all
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }
    }

    /// OCR retenu parmi les lectures déjà faites, données dans l'ordre de `lookupOrder`.
    ///
    /// D7 et décision F4 de NOxygen59 (07/11/2026) : les corrections restent attachées à leur moteur, mais l'OCR retenu
    /// les prend **toujours** en premier, même face au moteur réglé ou choisi dans le menu du panneau. Plusieurs versions
    /// corrigées : la première dans l'ordre de recherche (moteur choisi d'abord). Sans correction : la première lecture
    /// d'un moteur de `choiceOrder` (le choix explicite reste seul). Aucune version n'est supprimée, fusionnée ni déplacée.
    public static func retained(among pages: [OCRPage], choiceOrder: [String]) -> OCRPage? {
        if let corrected = pages.first(where: isCorrected) { return corrected }
        return pages.first { choiceOrder.contains($0.engine) }
    }

    /// Lecture dont au moins une ligne a été corrigée à la main.
    public static func isCorrected(_ page: OCRPage) -> Bool { page.hasManualEdits }

    /// Identifiant du moteur d'un choix explicite.
    public static func engineID(_ choice: OCREngineChoice) -> String {
        switch choice {
        case .auto, .pdfText: return OCREngineID.pdfText
        case .vision: return OCREngineID.vision
        case .ndlocr: return OCREngineID.ndlocr
        case .ppocr5: return OCREngineID.ppocr5
        case .glmocr: return OCREngineID.glmocr
        }
    }
}
