// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

/// Ouverture du lecteur (#93, KYO-001, PLAN-1510-001 E1). iOS 16 peut refuser la fenêtre plein écran du lecteur si un
/// menu ou une autre fenêtre se referme encore ; l'app gardait alors le document « ouvert » sans lecteur, et un
/// nouveau toucher ne relançait rien. Ce type pur décide quand redemander la présentation : document redemandé alors
/// que le lecteur n'est jamais apparu, ou lecteur toujours absent après un délai (au plus `maxRetries` fois).
public struct ReaderOpenGuard: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// Rien à faire (lecteur déjà à l'écran, demande périmée, essais épuisés).
        case none
        /// Première présentation de cette demande.
        case present
        /// Présentation refusée ou jamais faite : la retirer puis la redemander.
        case presentAgain
    }

    public static let maxRetries = 2

    public private(set) var requested: String?
    /// Change à chaque demande : un contrôle prévu pour une demande plus ancienne ne relance jamais rien.
    public private(set) var serial = 0
    public private(set) var retries = 0
    public private(set) var shown = false

    public init() {}

    /// Demande d'ouverture de `id` (toucher, menu, note, onglet).
    public mutating func request(_ id: String) -> Action {
        serial += 1
        retries = 0
        let again = requested == id && !shown
        requested = id
        // Lecteur déjà à l'écran : il change seulement de document, la fenêtre reste.
        if shown { return .none }
        return again ? .presentAgain : .present
    }

    /// Le lecteur est réellement apparu.
    public mutating func didShow() { shown = true }

    /// Lecteur fermé (ou plus aucun document ouvert).
    public mutating func didClose() {
        shown = false
        requested = nil
        retries = 0
    }

    /// Contrôle après le délai, pour la demande `serial` : toujours rien à l'écran → nouvel essai.
    public mutating func check(serial: Int) -> Action {
        guard serial == self.serial, requested != nil, !shown, retries < Self.maxRetries else { return .none }
        retries += 1
        return .presentAgain
    }

    /// Plus d'essai possible et toujours rien à l'écran pour la demande `serial`.
    public func gaveUp(serial: Int) -> Bool {
        serial == self.serial && requested != nil && !shown && retries >= Self.maxRetries
    }
}
