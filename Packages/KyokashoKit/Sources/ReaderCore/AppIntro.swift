// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Visite guidée et fenêtre « Nouveautés » (idées de NOxygen59, 29/10/2026) : expliquer très simplement comment faire
/// quoi et pourquoi, au premier lancement ; montrer après chaque mise à jour ce qui est ajouté, corrigé ou retiré.
/// Les deux se relancent depuis les réglages.
public struct IntroStep: Equatable, Sendable, Identifiable {
    public var id: String { title }
    /// Symbole SF Symbols.
    public let icon: String
    public let title: String
    /// Comment faire.
    public let how: String
    /// Pourquoi c'est utile.
    public let why: String
}

public enum AppTour {
    public static let steps: [IntroStep] = [
        IntroStep(icon: "books.vertical", title: String(localized: "Ta bibliothèque", bundle: .main),
                  how: String(localized: "« Importer » ajoute des PDF depuis Fichiers ou Google Drive. Les outils convertissent aussi des photos en PDF et fusionnent plusieurs PDF.", bundle: .main),
                  why: String(localized: "Tous tes manuels au même endroit, rangés en Manuels et Livres.", bundle: .main)),
        IntroStep(icon: "book", title: String(localized: "Lire", bundle: .main),
                  how: String(localized: "Touche un livre pour l'ouvrir. Glisse, ou utilise ‹ › et les flèches du clavier, pour tourner les pages. Les onglets en haut passent d'un livre à l'autre.", bundle: .main),
                  why: String(localized: "Chaque livre rouvre à la page où tu l'avais laissé.", bundle: .main)),
        IntroStep(icon: "character.ja", title: String(localized: "Le texte de la page", bundle: .main),
                  how: String(localized: "Le bouton あ ouvre le panneau Texte : l'app lit la page scannée (OCR) et la met en forme, avec furigana et traduction.", bundle: .main),
                  why: String(localized: "Un scan n'est qu'une image : l'OCR en fait du texte que tu peux chercher, copier et comprendre.", bundle: .main)),
        IntroStep(icon: "character.book.closed.ja", title: String(localized: "Le dictionnaire", bundle: .main),
                  how: String(localized: "Touche un mot de la page ou du panneau Texte. Avec un clavier, tiens Maj et passe la souris sur un mot.", bundle: .main),
                  why: String(localized: "Lecture et sens d'un mot sans quitter la page ; tu peux le garder pour le réviser.", bundle: .main)),
        IntroStep(icon: "highlighter", title: String(localized: "Annoter", bundle: .main),
                  how: String(localized: "Notes, signets, dessin au Pencil, et le surligneur : glisse sur le texte de la page pour le surligner.", bundle: .main),
                  why: String(localized: "Tes repères restent attachés à la page, et s'exportent.", bundle: .main)),
        IntroStep(icon: "rectangle.stack.badge.play", title: String(localized: "Réviser", bundle: .main),
                  how: String(localized: "« Révisions » propose chaque jour les mots gardés, au bon moment.", bundle: .main),
                  why: String(localized: "Revoir juste avant d'oublier : c'est ce qui fait retenir.", bundle: .main)),
        IntroStep(icon: "sparkles", title: String(localized: "L'IA locale", bundle: .main),
                  how: String(localized: "OvisOCR2 lit les pages mieux que l'OCR simple ; Qwen traduit et répond à tes questions sur le livre. Tout tourne sur l'iPad, hors ligne.", bundle: .main),
                  why: String(localized: "Rien ne part sur Internet, mais la batterie baisse vite : branche l'iPad pour les longues lectures.", bundle: .main)),
        IntroStep(icon: "gearshape", title: String(localized: "Réglages et sauvegarde", bundle: .main),
                  how: String(localized: "Les réglages ajustent la lecture, l'OCR et l'IA ; ils permettent aussi de sauvegarder la bibliothèque et de revoir cette visite.", bundle: .main),
                  why: String(localized: "Une sauvegarde régulière protège tes notes et tes lectures.", bundle: .main)),
    ]
}

/// Notes d'une version : ce qui est ajouté, corrigé, retiré. L'historique complet (``all``) va de la 0.1.0 à la
/// version en cours, en intercalant les builds de test non publiées (recettes iPad), demandé par NOxygen59 le 29/10.
public struct ReleaseNotes: Equatable, Sendable, Identifiable {
    public var id: String { version }
    /// « 1.3.2 » pour une version ; « 1.3.2 (50–52) » pour des builds de test non publiées.
    public let version: String
    /// Date de publication (ou de la recette pour une build non publiée), « 2026-10-20 ».
    public let date: String
    /// Release GitHub publiée ; sinon build de test installée seulement par NOxygen59.
    public let published: Bool
    /// Résumé en quelques mots.
    public let title: String
    public let added: [String]
    public let fixed: [String]
    public let removed: [String]

    public init(_ version: String, _ date: String, published: Bool = true, _ title: String,
                added: [String] = [], fixed: [String] = [], removed: [String] = []) {
        self.version = version
        self.date = date
        self.published = published
        self.title = title
        self.added = added
        self.fixed = fixed
        self.removed = removed
    }

    /// Du plus récent au plus ancien.
    public static let all: [ReleaseNotes] = [current] + ReleaseHistory.past

    /// La version en cours de préparation : seulement ce qu'elle change (décision de NOxygen59 du 04/11/2026). C'est
    /// elle que montre la fenêtre « Nouveautés » ; les versions précédentes vont dans `ReleaseHistory`.
    public static let current = ReleaseNotes("1.4.2", "2026-11-04", published: false, String(localized: "Nouveautés et export plus clairs", bundle: .main), added: [
            String(localized: "Export : le fichier se prépare d'abord, puis un message indique clairement quand il est prêt à être enregistré ou envoyé.", bundle: .main),
            String(localized: "Extraction des lectures OvisOCR2 : le nombre de pages lues est affiché pour chaque document.", bundle: .main),
        ], fixed: [
            String(localized: "Cette fenêtre ne montre plus que les changements de la version installée.", bundle: .main),
            String(localized: "Fenêtre d'étude, notes et dictionnaire : le texte n'est plus dédoublé sur les styles à ombre franche.", bundle: .main),
        ])

    /// Notes de `version` (« 1.3.2 », sans le numéro de build) : la version elle-même, jamais une build de test.
    public static func notes(for version: String) -> ReleaseNotes? { all.first { $0.version == version } }
}

/// Que montrer au lancement.
public enum IntroGate: Equatable, Sendable {
    case none, tour, whatsNew

    /// - `tourSeen` : visite déjà vue ; `lastSeen` : dernière version (« 1.3.2 (65) ») dont les nouveautés ont été vues ;
    /// - `current` : version installée ; `hasNotes` : des notes existent pour elle ;
    /// - `hasLibrary` : la bibliothèque contient déjà des documents (l'app était utilisée avant cette fonction).
    /// Nouvel utilisateur : la visite (les nouveautés ne lui disent rien). Utilisateur d'avant : les nouveautés, la
    /// visite restant accessible dans les réglages.
    public static func decide(tourSeen: Bool, lastSeen: String?, current: String, hasNotes: Bool, hasLibrary: Bool) -> IntroGate {
        if !tourSeen && lastSeen == nil && !hasLibrary { return .tour }
        if lastSeen != current && hasNotes { return .whatsNew }
        return .none
    }
}
