// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

/// Texte que copie le bouton « Copier » du panneau Texte (recette iPad 1.5.3, 7.1 à 7.4 : NOxygen59 a préféré ce bouton à
/// une correction de la copie depuis la page). Règle : copier ce qui est **affiché**. Relecture de 6cc15fc (P2) : en
/// « Mise en page IA », le panneau montre le Markdown d'OvisOCR2 (ou sa traduction), pas le texte du moteur OCR.
public enum OCRPanelCopy {
    /// Affichage du panneau : « Mis en forme », « Brut » ou « Mise en page IA ».
    public enum Mode: Sendable { case formatted, raw, aiLayout }

    /// - Parameters:
    ///   - page: OCR retenu de la page de travail.
    ///   - ovis: Markdown d'OvisOCR2 de la page, s'il existe.
    ///   - translation: traduction de ce Markdown dans la langue choisie, si elle existe.
    ///   - showTranslation: la traduction est demandée à l'écran.
    /// - Returns: le texte à copier, ou `nil` s'il n'y a rien d'affiché à copier.
    public static func text(mode: Mode, page: OCRPage?, ovis: String?, translation: String?, showTranslation: Bool) -> String? {
        switch mode {
        case .aiLayout:
            if showTranslation, let translation { return translation }
            return ovis
        case .formatted:
            return page.map { OCRLayout.markdown($0) }
        case .raw:
            return page?.text
        }
    }
}
