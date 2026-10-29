// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit

/// Version Mac Catalyst (#55, Mac Intel) : MLX n'est pas compilé. Lectures IA, chat, traduction et relevé de termes
/// renvoient cette erreur ; les lectures déjà faites arrivent par un paquet `.kyokasho` exporté de l'iPad.
let localAIUnavailableOnMac = OCRError.engineFailed(
    "L'IA locale n'est pas disponible sur Mac : importe le document en paquet .kyokasho avec ses lectures et traductions.")

/// Vrai si cette version de l'app fait tourner les modèles d'IA locaux (iPad), faux sur Mac.
public let localAIAvailable: Bool = {
    #if canImport(MLXVLM)
    return true
    #else
    return false
    #endif
}()
