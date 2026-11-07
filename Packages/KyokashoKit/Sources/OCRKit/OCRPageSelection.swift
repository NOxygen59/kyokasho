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
    /// Un choix du menu l'écrit **avant** que la lecture arrive : c'est une intention, pas ce qui est affiché.
    public private(set) var selected: [Int: String] = [:]
    /// Moteur de la dernière lecture réellement dessinée pour la page (zones, furigana). Distinct de `selected` : le
    /// passage NDLOCR → texte du PDF par le menu doit encore savoir que des furigana NDLOCR sont à retirer
    /// (contre-revue Codex de 51f8a2d, F1).
    public private(set) var published: [Int: String] = [:]
    private var revisions: [Int: Int] = [:]
    /// Incrémentée par `reset` : périme d'un coup toutes les pages, même celles sans révision propre.
    private var epoch = 0

    public init() {}

    /// Ticket à prendre avant de lire le cache ou de lancer une lecture pour `source`.
    public func ticket(for source: Int) -> Ticket {
        Ticket(source: source, epoch: epoch, revision: revisions[source, default: 0])
    }

    /// Intention annulable (choix du menu, « Relancer ») : état d'avant et ticket de la demande lancée.
    public struct Intent: Sendable {
        public let ticket: Ticket
        let previousPinned: String?
        let previousSelected: String?
    }

    /// Vrai si aucune intention ni changement de moteur adopté n'a eu lieu pour la page depuis la prise du ticket.
    /// Une adoption du **même** moteur ne périme pas : la fraîcheur du contenu d'un même moteur relève de l'étape 2.
    public func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.epoch == epoch && ticket.revision == revisions[ticket.source, default: 0]
    }

    /// Choix du menu du panneau : retenu pour la page ; les demandes en cours pour elle deviennent périmées.
    @discardableResult
    public mutating func pin(_ engine: String, source: Int) -> Intent {
        let previous = (pinned[source], selected[source])
        invalidate(source)
        pinned[source] = engine
        selected[source] = engine
        return Intent(ticket: ticket(for: source), previousPinned: previous.0, previousSelected: previous.1)
    }

    /// « Relancer » avec un moteur connu : même moteur retenu, sans en faire un choix durable pour la page.
    @discardableResult
    public mutating func retain(_ engine: String, source: Int) -> Intent {
        let previous = (pinned[source], selected[source])
        invalidate(source)
        selected[source] = engine
        return Intent(ticket: ticket(for: source), previousPinned: previous.0, previousSelected: previous.1)
    }

    /// Lecture de l'intention échouée : l'ancienne lecture redevient explicitement l'OCR retenu, plutôt qu'un état hybride
    /// (moteur demandé sans lecture, panneau de l'ancien). Sans effet si une intention plus récente existe.
    /// Les demandes encore en route pour l'intention échouée restent refusées.
    /// - Returns: `true` si l'état d'avant a été rétabli.
    @discardableResult
    public mutating func revert(_ intent: Intent) -> Bool {
        guard isCurrent(intent.ticket) else { return false }
        let source = intent.ticket.source
        invalidate(source)
        pinned[source] = intent.previousPinned
        selected[source] = intent.previousSelected
        return true
    }

    /// Note le moteur de la lecture que l'on dessine pour la page.
    /// - Returns: le moteur précédemment dessiné s'il était **différent** (ses furigana sont à retirer), sinon `nil`.
    @discardableResult
    public mutating func publish(_ engine: String, source: Int) -> String? {
        let previous = published[source]
        published[source] = engine
        return previous == engine ? nil : previous
    }

    /// Nouvelle intention sans moteur encore connu (« Relancer » en Auto) : les demandes en cours deviennent périmées.
    public mutating func invalidate(_ source: Int) {
        revisions[source, default: 0] &+= 1
    }

    /// Page tournée : ses lectures ne valent plus pour l'orientation affichée ; le choix du menu est gardé.
    public mutating func forget(_ source: Int) {
        invalidate(source)
        selected[source] = nil
        published[source] = nil
    }

    /// Nouveau réglage du moteur : intention durable qui remplace tous les choix faits page par page.
    public mutating func reset() {
        epoch &+= 1
        pinned.removeAll()
        selected.removeAll()
        published.removeAll()
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
