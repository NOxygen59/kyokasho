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
        IntroStep(icon: "books.vertical", title: "Ta bibliothèque",
                  how: "« Importer » ajoute des PDF depuis Fichiers ou Google Drive. Les outils convertissent aussi des photos en PDF et fusionnent plusieurs PDF.",
                  why: "Tous tes manuels au même endroit, rangés en Manuels et Livres."),
        IntroStep(icon: "book", title: "Lire",
                  how: "Touche un livre pour l'ouvrir. Glisse, ou utilise ‹ › et les flèches du clavier, pour tourner les pages. Les onglets en haut passent d'un livre à l'autre.",
                  why: "Chaque livre rouvre à la page où tu l'avais laissé."),
        IntroStep(icon: "character.ja", title: "Le texte de la page",
                  how: "Le bouton あ ouvre le panneau Texte : l'app lit la page scannée (OCR) et la met en forme, avec furigana et traduction.",
                  why: "Un scan n'est qu'une image : l'OCR en fait du texte que tu peux chercher, copier et comprendre."),
        IntroStep(icon: "character.book.closed.ja", title: "Le dictionnaire",
                  how: "Touche un mot de la page ou du panneau Texte. Avec un clavier, tiens Maj et passe la souris sur un mot.",
                  why: "Lecture et sens d'un mot sans quitter la page ; tu peux le garder pour le réviser."),
        IntroStep(icon: "highlighter", title: "Annoter",
                  how: "Notes, signets, dessin au Pencil, et le surligneur : glisse sur le texte de la page pour le surligner.",
                  why: "Tes repères restent attachés à la page, et s'exportent."),
        IntroStep(icon: "rectangle.stack.badge.play", title: "Réviser",
                  how: "« Révisions » propose chaque jour les mots gardés, au bon moment.",
                  why: "Revoir juste avant d'oublier : c'est ce qui fait retenir."),
        IntroStep(icon: "sparkles", title: "L'IA locale",
                  how: "OvisOCR2 lit les pages mieux que l'OCR simple ; Qwen traduit et répond à tes questions sur le livre. Tout tourne sur l'iPad, hors ligne.",
                  why: "Rien ne part sur Internet, mais la batterie baisse vite : branche l'iPad pour les longues lectures."),
        IntroStep(icon: "gearshape", title: "Réglages et sauvegarde",
                  how: "Les réglages ajustent la lecture, l'OCR et l'IA ; ils permettent aussi de sauvegarder la bibliothèque et de revoir cette visite.",
                  why: "Une sauvegarde régulière protège tes notes et tes lectures."),
    ]
}

/// Notes d'une version : ce qui est ajouté, corrigé, retiré.
public struct ReleaseNotes: Equatable, Sendable {
    public let version: String
    public let added: [String]
    public let fixed: [String]
    public let removed: [String]

    public static let all: [ReleaseNotes] = [
        ReleaseNotes(version: "1.3.2", added: [
            "Onglets en haut du lecteur pour passer d'un livre à l'autre ; une notification prévient quand beaucoup sont ouverts.",
            "Accueil en sections Manuels et Livres, question « Livre ou manuel ? » à l'import, suppression de plusieurs documents.",
            "Corbeille : un document supprimé reste 30 jours, restaurable.",
            "Temps de lecture sur l'accueil, à la place de la progression en pages.",
            "Surligneur sur le texte lu par l'OCR, avec gomme et annulation (⌘ Z).",
            "Images (photo, PNG, HEIC) vers PDF.",
            "Notes : heure de chaque note, groupées par jour, modifiables sur place ; export Markdown.",
            "Analyse du document : conseil fondé d'abord sur OvisOCR2, annulation d'un choix, relance au choix, texte des images.",
            "Chat IA : consignes et paramètres par modèle, préréglages, tâches rapides, partage, liste des conversations.",
            "Moniteur de ressources intégré à la barre du lecteur ; journal des IA en clair.",
            "Fond « Sépia nuit », visite guidée et cette fenêtre de nouveautés.",
        ], fixed: [
            "Les flèches du clavier tournent les pages sans rester bloquées sur le champ du numéro de page.",
            "Le survol du dictionnaire avec Maj suit le curseur, même rapide.",
            "La pastille du moteur OCR ne clignote plus en tournant les pages.",
            "« Voir le journal » s'ouvre vite, même long.",
            "Avertissement quand un brouillon de note n'a pas été ajouté.",
        ], removed: [
            "Fond « Sombre intelligent » (remplacé par « Sépia nuit »).",
            "Fenêtre OCR « réduite en pastille » (le panneau se masque avec ×).",
            "Grosses flèches sur les bords de la page (rangées à côté du numéro de page).",
        ]),
    ]

    /// Notes de `version` (« 1.3.2 », sans le numéro de build).
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
