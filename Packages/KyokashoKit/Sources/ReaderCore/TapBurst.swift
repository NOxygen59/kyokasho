// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Rafale de touchers sur la carte « Temps de lecture » de l'accueil (PLAN-MODLOC-001, E1 ; DEC-01 = A, décidé par
/// NOxygen59 le 13/11/2026) : on attend `window` secondes après le dernier toucher ; trois touchers ou plus basculent le
/// mode propriétaire (chat et import de modèle visibles ou cachés), un ou deux ouvrent le tableau de bord comme avant.
/// Fonction pure, testée : la vue ne fait que dater les touchers et relire `outcome` après la pause.
public struct TapBurst: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case single, toggleOwnerMode }

    /// Pause qui clôt une rafale ; le tableau de bord s'ouvre donc ~0,4 s plus tard qu'avant (DEC-01, accepté).
    public static let window: TimeInterval = 0.4

    public private(set) var taps: [Date] = []

    public init() {}

    public mutating func tap(at date: Date) {
        // Un toucher venu après une pause commence une nouvelle rafale.
        if let last = taps.last, date.timeIntervalSince(last) > Self.window { taps = [] }
        taps.append(date)
    }

    /// Résultat de la rafale une fois la pause écoulée ; `nil` tant qu'elle peut encore continuer.
    public func outcome(at now: Date) -> Outcome? {
        // 1 ms de tolérance : l'arrondi des dates (0,4 s calculé = 0,39999… s) ne doit pas retarder la décision.
        guard let last = taps.last, now.timeIntervalSince(last) >= Self.window - 0.001 else { return nil }
        return taps.count >= 3 ? .toggleOwnerMode : .single
    }
}
