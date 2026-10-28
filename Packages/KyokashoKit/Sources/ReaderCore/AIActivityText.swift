// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Textes lisibles du journal des IA locales (#47) : NOxygen59 veut voir ce que fait chaque IA, en clair, et pas
/// seulement « en cours ».
public enum AIActivityText {
    /// Explication d'une activité de pastille (« chargement », « chat »…), pour la fenêtre « Activité des IA ».
    public static func explain(_ activity: String) -> String {
        switch activity {
        case "chargement": return "charge le modèle en mémoire (quelques secondes, plusieurs Go de RAM)"
        case "chargée": return "reste en mémoire pour la prochaine demande, sans calculer"
        case "en attente": return "attend son tour : une autre IA utilise la puce"
        case "chat": return "rédige une réponse au chat"
        case "lecture": return "lit les pages du document et en tire le texte"
        case "mise en page": return "met la page en forme (titres, paragraphes, tableaux)"
        case "vérification": return "relit la page pour repérer les erreurs de l'OCR"
        case "relecture": return "relit la page en entier avec un autre modèle"
        case "traduction": return "traduit le texte en français"
        case "analyse": return "analyse tout le document (comparaison des lectures)"
        case "utilisée": return "calcule (génère du texte)"
        default:
            if activity.hasSuffix("tâches") { return "enchaîne plusieurs tâches, une à la fois" }
            return activity
        }
    }

    /// « 45 s », « 2 min 05 s », « 1 h 03 min ».
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) s" }
        if s < 3600 { return String(format: "%d min %02d s", s / 60, s % 60) }
        return String(format: "%d h %02d min", s / 3600, s % 3600 / 60)
    }

    /// Fin d'une tâche : terminée, arrêtée ou en erreur, avec sa durée.
    public static func outcome(seconds: TimeInterval, cancelled: Bool, error: String?) -> String {
        if cancelled { return "Arrêtée après \(duration(seconds))" }
        if let error { return "Erreur après \(duration(seconds)) : \(error)" }
        return "Terminée en \(duration(seconds))"
    }
}
