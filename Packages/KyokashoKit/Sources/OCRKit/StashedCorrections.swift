// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore

/// Remise des corrections manuelles mises de côté pendant un remplacement de document
/// (décision DEC-C3, voir `CorrectionAsideStore`) : quand un nouveau résultat OCR est
/// enregistré pour le document remplacé, chaque ligne relue dont le texte est **identique** au
/// texte lu d'origine d'une correction mise de côté pour cette page et ce moteur reçoit la
/// correction, exactement comme une correction faite à la main (`OCRLine.acceptingCorrection`) ;
/// la correction appliquée est retirée du dossier, les autres restent pour une relecture suivante.
///
/// Invariant : le rapprochement se fait sur le texte relu **tel qu'enregistré** (résultat déjà
/// normalisé par `OCRService`), par égalité stricte — un texte différent n'est jamais retouché :
/// une ligne ou un paragraphe nouvellement lus décriraient un contenu que l'utilisateur n'a pas
/// corrigé si on lui servait le texte d'une version antérieure. Une entrée restée dans le dossier
/// après un arrêt au pire moment ne s'applique jamais deux fois : la ligne déjà corrigée (son
/// `originalText` est posé) ne concorde plus avec le texte lu d'origine.
enum StashedCorrections {
    /// Applique les corrections mises de côté à un nouveau résultat. Retourne la page corrigée
    /// et le nombre de corrections appliquées, ou `nil` si rien ne concorde (le dossier peut
    /// très bien ne pas exister : le document n'a pas été remplacé).
    /// `commit` retire les corrections appliquées du dossier de côté : à appeler **après** l'écriture réussie du
    /// résultat (revue R2, S3 : sinon un échec d'écriture perdait la correction des deux côtés).
    static func applied(to page: OCRPage, documentId: String, pageIndex: Int) -> (page: OCRPage, applied: Int, commit: () -> Void)? {
        let aside = CorrectionAsideStore.shared
        let pending = aside.pendingCorrections(documentId: documentId, pageIndex: pageIndex, engine: page.engine)
        guard !pending.isEmpty else { return nil }
        var result = page
        var applied = 0
        var appliedPerFile: [URL: Set<KeptCorrection>] = [:]
        for candidate in pending {
            // Une ligne pas encore corrigée du nouveau PDF porte le texte lu : c'est à elle que
            // la correction s'applique (une ligne déjà corrigée concordait, mais son texte est
            // celui de la correction ; le rapprochement ne peut pas la viser deux fois).
            // Analyse avant candidate 1.5.5 (DeepSeek #2) : le texte relu est normalisé (table T6), le texte mis
            // de côté peut ne pas l'être (correction faite avant 1.5.5) : les deux formes sont acceptées.
            let original = candidate.entry.original, normalizedOriginal = JapaneseOCRText.normalize(original)
            guard let index = result.lines.firstIndex(where: { $0.originalText == nil && ($0.text == original || $0.text == normalizedOriginal) })
            else { continue }
            result.lines[index] = result.lines[index].acceptingCorrection(candidate.entry.corrected)
            applied += 1
            appliedPerFile[candidate.file, default: []].insert(candidate.entry)
        }
        // « Une correction appliquée est retirée du dossier, les autres restent » : fichier par
        // fichier, un seul passage, une fois le résultat enregistré.
        let commit = { for (file, entries) in appliedPerFile { aside.removeApplied(documentId: documentId, file: file, entries: entries) } }
        return applied > 0 ? (result, applied, commit) : nil
    }
}
