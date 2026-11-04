// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Textes lisibles du journal des IA locales (#47) : NOxygen59 veut voir ce que fait chaque IA, en clair, et pas
/// seulement « en cours ».
public enum AIActivityText {
    /// Nom affiché d'une activité : la valeur brute reste en français, c'est elle qu'`explain` reconnaît.
    public static func label(_ activity: String) -> String {
        switch activity {
        case "chargement": return String(localized: "chargement", bundle: .main)
        case "chargée": return String(localized: "chargée", bundle: .main)
        case "en attente": return String(localized: "en attente", bundle: .main)
        case "chat": return String(localized: "chat", bundle: .main)
        case "lecture": return String(localized: "lecture", bundle: .main)
        case "mise en page": return String(localized: "mise en page", bundle: .main)
        case "vérification": return String(localized: "vérification", bundle: .main)
        case "relecture": return String(localized: "relecture", bundle: .main)
        case "traduction": return String(localized: "traduction", bundle: .main)
        case "analyse": return String(localized: "analyse", bundle: .main)
        case "utilisée": return String(localized: "utilisée", bundle: .main)
        default:
            if activity.hasSuffix(" tâches"), let count = Int(activity.dropLast(" tâches".count)) {
                return String(localized: "\(count) tâches", bundle: .main)
            }
            return activity
        }
    }

    /// Explication d'une activité de pastille (« chargement », « chat »…), pour la fenêtre « Activité des IA ».
    public static func explain(_ activity: String) -> String {
        switch activity {
        case "chargement": return String(localized: "charge le modèle en mémoire (quelques secondes, plusieurs Go de RAM)", bundle: .main)
        case "chargée": return String(localized: "reste en mémoire pour la prochaine demande, sans calculer", bundle: .main)
        case "en attente": return String(localized: "attend son tour : une autre IA utilise la puce", bundle: .main)
        case "chat": return String(localized: "rédige une réponse au chat", bundle: .main)
        case "lecture": return String(localized: "lit les pages du document et en tire le texte", bundle: .main)
        case "mise en page": return String(localized: "met la page en forme (titres, paragraphes, tableaux)", bundle: .main)
        case "vérification": return String(localized: "relit la page pour repérer les erreurs de l'OCR", bundle: .main)
        case "relecture": return String(localized: "relit la page en entier avec un autre modèle", bundle: .main)
        case "traduction": return String(localized: "traduit le texte en français", bundle: .main)
        case "analyse": return String(localized: "analyse tout le document (comparaison des lectures)", bundle: .main)
        case "utilisée": return String(localized: "calcule (génère du texte)", bundle: .main)
        default:
            if activity.hasSuffix("tâches") { return String(localized: "enchaîne plusieurs tâches, une à la fois", bundle: .main) }
            return activity
        }
    }

    /// « 45 s », « 2 min 05 s », « 1 h 03 min ».
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return String(localized: "\(s) s", bundle: .main) }
        if s < 3600 { return String(format: String(localized: "%d min %02d s", bundle: .main), s / 60, s % 60) }
        return String(format: String(localized: "%d h %02d min", bundle: .main), s / 3600, s % 3600 / 60)
    }

    /// Fin d'une tâche : terminée, arrêtée ou en erreur, avec sa durée.
    public static func outcome(seconds: TimeInterval, cancelled: Bool, error: String?) -> String {
        if cancelled { return String(localized: "Arrêtée après \(duration(seconds))", bundle: .main) }
        if let error { return String(localized: "Erreur après \(duration(seconds)) : \(error)", bundle: .main) }
        return String(localized: "Terminée en \(duration(seconds))", bundle: .main)
    }
}
