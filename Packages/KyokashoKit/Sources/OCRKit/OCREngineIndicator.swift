// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore

/// Ce que montre le libellé du menu des moteurs du panneau Texte.
///
/// Recette iPad 1.5.3, retour 2.10 de NOxygen59 : le logo du menu ne correspondait pas au moteur choisi. Le logo suit le
/// texte **affiché** (`OCRPage.engine`), et ce texte peut venir d'un autre moteur que le choix : une correction à la
/// main passe toujours d'abord (décision F4 du 07/11/2026), et un moteur absent ou en échec laisse la lecture
/// précédente. Le libellé garde donc le moteur affiché — c'est lui que lisent le toucher, les furigana et la copie —
/// et le panneau signale l'écart avec le choix au lieu de le cacher.
public struct OCREngineIndicator: Equatable, Sendable {
    /// Moteur du texte affiché ; `nil` si la page n'a pas encore été lue.
    public let shown: String?
    /// Le texte affiché porte au moins une ligne corrigée à la main.
    public let corrected: Bool
    /// Moteur choisi : celui du menu pour cette page, sinon le réglage du document ; `nil` en Auto (pas de choix).
    public let chosen: String?

    /// - Parameters:
    ///   - page: OCR retenu de la page de travail.
    ///   - pinned: moteur choisi dans le menu pour cette page (`ReaderController.pinnedEngines`).
    ///   - setting: réglage OCR du document (ou de l'app).
    public init(page: OCRPage?, pinned: String?, setting: OCREngineChoice) {
        shown = page?.engine
        corrected = page.map(OCRSelectionPolicy.isCorrected) ?? false
        chosen = pinned ?? (setting == .auto ? nil : OCRSelectionPolicy.engineID(setting))
    }

    /// Le texte affiché ne vient pas du moteur choisi.
    public var differs: Bool {
        guard let shown, let chosen else { return false }
        return shown != chosen
    }
}
