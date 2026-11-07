// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

/// État de l'**OCR retenu** des pages d'un lecteur ouvert : moteur choisi pour la page (`pinned`), moteur retenu
/// (`selected`) et une révision par page qui date chaque intention.
///
/// Pourquoi une révision (revue Codex de d87e048, R1) : une lecture de cache ou d'OCR suspendue pouvait, à son retour,
/// réécrire elle-même le moteur retenu, puis passer la garde qu'elle venait de modifier ; un choix explicite fait entre-temps
/// dans le menu était perdu, dans un sens comme dans l'autre. Désormais :
/// - un appelant prend un `Ticket` **avant** toute attente ;
/// - toute nouvelle intention (choix du menu, « Relancer », rotation, nouveau réglage) incrémente la révision ;
/// - `adopt` n'accepte qu'un ticket encore courant ; s'il change de moteur, il périme les demandes plus anciennes.
/// Lire l'état (`selected`, `pinned`, `ticket`) ne le modifie jamais.
///
/// Type valeur sans verrou : il vit dans le contrôleur du lecteur, sur le `MainActor`. Contrôle et écriture se font dans
/// le même bloc synchrone, sans attente entre les deux.
public struct OCRPageSelection: Sendable {
    /// Demande datée pour une page : seule une demande encore courante peut faire adopter son résultat.
    public struct Ticket: Equatable, Sendable {
        public let source: Int
        let epoch: Int
        let revision: Int
    }

    /// Moteur choisi dans le panneau Texte pour la page (décision D2), tant que le lecteur est ouvert.
    public private(set) var pinned: [Int: String] = [:]
    /// Moteur de l'OCR retenu de chaque page : seul un résultat de ce moteur alimente zones, furigana et panneau.
    public private(set) var selected: [Int: String] = [:]
    private var revisions: [Int: Int] = [:]
    /// Incrémentée par `reset` : périme d'un coup toutes les pages, même celles sans révision propre.
    private var epoch = 0

    public init() {}

    /// Ticket à prendre avant de lire le cache ou de lancer une lecture pour `source`.
    public func ticket(for source: Int) -> Ticket {
        Ticket(source: source, epoch: epoch, revision: revisions[source, default: 0])
    }

    /// Vrai si aucune intention ni adoption n'a eu lieu pour la page depuis la prise du ticket.
    public func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.epoch == epoch && ticket.revision == revisions[ticket.source, default: 0]
    }

    /// Choix du menu du panneau : retenu pour la page ; les demandes en cours pour elle deviennent périmées.
    public mutating func pin(_ engine: String, source: Int) {
        invalidate(source)
        pinned[source] = engine
        selected[source] = engine
    }

    /// « Relancer » avec un moteur connu : même moteur retenu, sans en faire un choix durable pour la page.
    public mutating func retain(_ engine: String, source: Int) {
        invalidate(source)
        selected[source] = engine
    }

    /// Nouvelle intention sans moteur encore connu (« Relancer » en Auto) : les demandes en cours deviennent périmées.
    public mutating func invalidate(_ source: Int) {
        revisions[source, default: 0] &+= 1
    }

    /// Page tournée : ses lectures ne valent plus pour l'orientation affichée ; le choix du menu est gardé.
    public mutating func forget(_ source: Int) {
        invalidate(source)
        selected[source] = nil
    }

    /// Nouveau réglage du moteur : intention durable qui remplace tous les choix faits page par page.
    public mutating func reset() {
        epoch &+= 1
        pinned.removeAll()
        selected.removeAll()
        revisions.removeAll()
    }

    /// Adopte `engine` comme OCR retenu de la page du ticket, si la demande est encore courante et compatible avec le
    /// moteur choisi pour la page. Refusé : rien ne change, et l'appelant ne doit rien afficher.
    /// - Returns: `true` si le résultat peut être affiché.
    @discardableResult
    public mutating func adopt(_ engine: String, ticket: Ticket) -> Bool {
        guard isCurrent(ticket), pinned[ticket.source].map({ $0 == engine }) ?? true else { return false }
        // Changement de moteur : la dernière adoption gagne, une demande plus ancienne de la page ne pourra plus revenir.
        // Même moteur : l'autorité ne change pas ; une lecture forcée de ce moteur (« Relancer ») reste attendue.
        if selected[ticket.source] != engine { invalidate(ticket.source) }
        selected[ticket.source] = engine
        return true
    }
}
