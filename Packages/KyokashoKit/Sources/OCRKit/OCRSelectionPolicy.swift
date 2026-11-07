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

    /// Vrai si la priorité des corrections (D7) s'applique : Auto, sans moteur choisi pour la page. Un choix explicite
    /// (réglage ou menu du panneau) reste l'intention de l'utilisateur.
    public static func prioritizesCorrections(choice: OCREngineChoice, pinned: String?) -> Bool {
        choice == .auto && pinned == nil
    }

    /// OCR retenu parmi les lectures déjà faites, données dans l'ordre de `cacheOrder`.
    ///
    /// D7 (décision de NOxygen59 du 07/11/2026 ; revue Codex de d87e048, R3) : les corrections restent attachées à leur
    /// moteur, mais l'OCR retenu les prend en premier. Avec `prioritizingCorrections`, la première lecture corrigée à la
    /// main gagne ; plusieurs lectures corrigées se départagent par l'ordre de la politique. Aucune version n'est
    /// supprimée, fusionnée ni déplacée vers un autre moteur.
    public static func retained(among pages: [OCRPage], prioritizingCorrections: Bool) -> OCRPage? {
        if prioritizingCorrections, let corrected = pages.first(where: \.hasManualEdits) { return corrected }
        return pages.first
    }

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
