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
    /// Étapes de la visite pour cet appareil : le Mac n'a ni Pencil ni espace Manga (réservé à l'iPad).
    public static var steps: [IntroStep] {
        #if targetEnvironment(macCatalyst)
        return steps(mac: true)
        #else
        return steps(mac: false)
        #endif
    }

    public static func steps(mac: Bool) -> [IntroStep] {
        var list: [IntroStep] = [
        IntroStep(icon: "books.vertical", title: String(localized: "Ta bibliothèque", bundle: .main),
                  how: mac ? String(localized: "« Importer » ajoute des PDF choisis dans le Finder. Les outils convertissent des photos en PDF, fusionnent plusieurs PDF et importent un paquet .kyokasho venu de l'iPad, avec ses lectures.", bundle: .main) : String(localized: "« Importer » ajoute des PDF depuis Fichiers ou Google Drive. Les outils convertissent des photos en PDF, fusionnent plusieurs PDF et importent un paquet .kyokasho venu d'un autre appareil, avec ses lectures.", bundle: .main),
                  why: String(localized: "Tes livres et manuels au même endroit, rangés par catégorie, chacun avec sa progression et son temps de lecture.", bundle: .main)),
        ]
        if !mac {
            list.append(
        IntroStep(icon: "rectangle.split.2x1", title: String(localized: "Deux espaces", bundle: .main),
                  how: String(localized: "En haut de l'accueil, passe de Livres & Manuels à Manga. Les .cbz vont dans Manga ; un PDF s'y range d'un appui long sur sa carte. La rangée du haut montre tes documents ouverts.", bundle: .main),
                  why: String(localized: "Chaque espace garde ses documents et, si tu veux, son propre thème (Réglages → Thèmes).", bundle: .main)))
        }
        list += [
        IntroStep(icon: "book", title: String(localized: "Lire", bundle: .main),
                  how: mac ? String(localized: "Clique un livre pour l'ouvrir. ‹ ›, les flèches du clavier ou le trackpad tournent les pages ; pince le trackpad ou double-clique pour zoomer. Les onglets en haut passent d'un livre à l'autre.", bundle: .main) : String(localized: "Touche un livre pour l'ouvrir. Glisse, ou utilise ‹ › et les flèches du clavier, pour tourner les pages ; pince ou touche deux fois pour zoomer. Les onglets en haut passent d'un livre à l'autre.", bundle: .main),
                  why: String(localized: "Chaque livre rouvre à la page où tu l'avais laissé.", bundle: .main)),
        IntroStep(icon: "character.ja", title: String(localized: "Le texte de la page", bundle: .main),
                  how: String(localized: "Dans la barre d'outils, « Texte de la page » (あ) ouvre le panneau Texte : l'app lit la page scannée (OCR), y compris le japonais vertical, et la met en forme avec furigana et traduction. Le bouton あ de la barre du haut pose les furigana sur la page.", bundle: .main),
                  why: String(localized: "Un scan n'est qu'une image : l'OCR en fait du texte que tu peux chercher, copier et comprendre.", bundle: .main)),
        IntroStep(icon: "character.book.closed.ja", title: String(localized: "Le dictionnaire", bundle: .main),
                  how: mac ? String(localized: "Clique un mot de la page ou du panneau Texte, ou tiens Maj et passe la souris dessus. Réglages → Dictionnaires installe tout le catalogue en un bouton.", bundle: .main) : String(localized: "Touche un mot de la page ou du panneau Texte. Avec un clavier, tiens Maj et passe la souris sur un mot. Réglages → Dictionnaires installe tout le catalogue en un bouton.", bundle: .main),
                  why: String(localized: "Lecture et sens d'un mot sans quitter la page ; tu peux le garder pour le réviser.", bundle: .main)),
        IntroStep(icon: "highlighter", title: String(localized: "Annoter", bundle: .main),
                  how: mac ? String(localized: "Notes, signets et surligneur : glisse sur le texte de la page pour le surligner.", bundle: .main) : String(localized: "Notes, signets, dessin au Pencil, et le surligneur : glisse sur le texte de la page pour le surligner.", bundle: .main),
                  why: String(localized: "Tes repères restent attachés à la page, et s'exportent.", bundle: .main)),
        IntroStep(icon: "rectangle.stack.badge.play", title: String(localized: "Réviser", bundle: .main),
                  how: String(localized: "« Révisions » propose chaque jour les mots gardés, au bon moment.", bundle: .main),
                  why: String(localized: "Revoir juste avant d'oublier : c'est ce qui fait retenir.", bundle: .main)),
        IntroStep(icon: "sparkles", title: String(localized: "L'IA locale", bundle: .main),
                  how: mac ? String(localized: "Réglages → Modèles d'IA : OvisOCR2 lit les pages, NDLOCR-Lite fait l'OCR rapide et Qwen3.5-9B répond à tes questions sur le livre, dans la langue de l'app. Tout tourne sur ce Mac, hors ligne.", bundle: .main) : String(localized: "OvisOCR2 lit les pages mieux que l'OCR simple ; Qwen traduit et répond à tes questions sur le livre. Tout tourne sur l'iPad, hors ligne.", bundle: .main),
                  why: mac ? String(localized: "Rien ne part sur Internet. Un seul modèle est chargé à la fois ; sur batterie, préfère les lectures courtes.", bundle: .main) : String(localized: "Rien ne part sur Internet, mais la batterie baisse vite : branche l'iPad pour les longues lectures.", bundle: .main)),
        IntroStep(icon: "chart.bar.xaxis", title: String(localized: "Suivre ton travail", bundle: .main),
                  how: String(localized: "L'accueil montre ton temps de lecture et l'avancée des analyses ; le panneau des performances montre ce que fait l'app et ce qu'elle consomme.", bundle: .main),
                  why: String(localized: "Voir où passe ton temps, et savoir quand l'IA travaille.", bundle: .main)),
        IntroStep(icon: "gearshape", title: String(localized: "Réglages et sauvegarde", bundle: .main),
                  how: String(localized: "Les réglages ajustent la lecture, l'OCR, l'IA, la langue de l'app et le thème ; ils sauvegardent aussi la bibliothèque et relancent cette visite.", bundle: .main),
                  why: String(localized: "Une sauvegarde régulière protège tes notes et tes lectures.", bundle: .main)),
        ]
        return list
    }
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
    public static let current = ReleaseNotes("1.5.1", "2026-11-06", published: false, String(localized: "Tableau de bord en tuiles et dictionnaires à jour", bundle: .main), added: [
            String(localized: "Tableau de bord refait en tuiles : un chiffre clé par case, des courbes et des anneaux.", bundle: .main),
            String(localized: "Dictionnaires : l'app cherche les mises à jour à chaque lancement s'il y a une connexion ; le catalogue a un bouton pour tout mettre à jour.", bundle: .main),
            String(localized: "Accueil : les documents ouverts sont rangés en deux groupes, Livres & Manuels puis Manga.", bundle: .main),
        ], fixed: [
            String(localized: "Thèmes clairs : la barre latérale, la recherche et le moniteur ne restent plus sombres.", bundle: .main),
            String(localized: "Réglages → Thèmes : « Comme la palette générale » s'applique, et la carte choisie passe en tête.", bundle: .main),
            String(localized: "Copier une sélection copie bien son texte.", bundle: .main),
            String(localized: "Moniteur de l'accueil : CPU, RAM et FPS lisibles quand il est déplié.", bundle: .main),
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
