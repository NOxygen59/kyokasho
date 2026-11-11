// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit

/// Décisions OCR isolées pour tester les vrais chemins utilisateur avec une base synthétique.
/// Le service reste MainActor ; le rapport ne se clôture qu’après sauvegarde du cache.
extension DocumentAnalysisService {
    /// De quoi annuler un choix appliqué (#41) : la ligne d'avant et le texte posé.
    struct AppliedChoice: Equatable {
        let source: Int
        let line: Int
        let previous: OCRLine
        let applied: String
    }

    /// Applique des choix dans le résultat OCR du document : seulement sur une ligne pas encore réglée et dont
    /// le texte n'a pas changé depuis l'analyse ; marquée réglée **après** l'enregistrement réussi.
    /// Renvoie les choix réellement enregistrés, pour « Annuler le dernier choix ».
    @discardableResult
    func apply(_ choices: [(source: Int, line: Int, text: String)], documentId: String, service: OCRService) async -> [AppliedChoice] {
        setCorrectionError(nil)
        guard let report = report(for: documentId) else {
            setCorrectionError(String(localized: "Analyse indisponible. Relance l’analyse avant de choisir."))
            return []
        }
        var applied: [AppliedChoice] = []
        for source in Set(choices.map(\.source)).sorted() {
            guard let info = report.pages[source] else {
                setCorrectionError(String(localized: "Page \(source + 1) absente de l’analyse. Relance l’analyse avant de choisir."))
                continue
            }
            guard var page = await service.cached(documentId: documentId, pageIndex: source, engine: info.baseEngine) else {
                setCorrectionError(String(localized: "Texte OCR de la page \(source + 1) indisponible. Relis la page puis relance l’analyse. Aucun choix n’a été enregistré pour cette page."))
                continue
            }
            var done: [Int] = []
            var undo: [AppliedChoice] = []
            for c in choices where c.source == source {
                guard let vote = info.disagreements.first(where: { $0.line == c.line }), !vote.settled else { continue }
                guard page.lines.indices.contains(c.line), page.lines[c.line].text == vote.base else {
                    setCorrectionError(String(localized: "Page \(source + 1), ligne \(c.line + 1) : le texte a changé depuis l’analyse. Ta version est conservée ; relance l’analyse avant de choisir."))
                    continue
                }
                let previous = page.lines[c.line]
                page.lines[c.line] = previous.acceptingCorrection(c.text)
                done.append(c.line)
                undo.append(AppliedChoice(source: source, line: c.line, previous: previous, applied: page.lines[c.line].text))
            }
            guard !done.isEmpty else { continue }
            do {
                try await service.store(page, documentId: documentId, pageIndex: source)
            } catch {
                setCorrectionError(String(localized: "Page \(source + 1) non enregistrée : \(error.localizedDescription)"))
                continue
            }
            update(documentId) { r in
                for line in done {
                    guard let i = r.pages[source]?.disagreements.firstIndex(where: { $0.line == line && !$0.settled }) else { continue }
                    r.pages[source]?.disagreements[i].settled = true
                    r.pages[source]?.confirmed += 1
                }
            }
            applied += undo
        }
        return applied
    }

    /// « Annuler le dernier choix » (#41, tant que la fenêtre d'analyse est ouverte) : remet chaque ligne comme avant,
    /// seulement si elle porte encore le texte posé (sinon, rien n'est touché et un message le dit), puis rouvre le
    /// désaccord. Même ordre que `apply` : cache d'abord, rapport ensuite.
    func undo(_ choices: [AppliedChoice], documentId: String, service: OCRService) async {
        setCorrectionError(nil)
        guard let report = report(for: documentId) else { return }
        for source in Set(choices.map(\.source)).sorted() {
            guard let info = report.pages[source],
                  var page = await service.cached(documentId: documentId, pageIndex: source, engine: info.baseEngine) else {
                setCorrectionError(String(localized: "Page \(source + 1) : texte indisponible, annulation impossible."))
                continue
            }
            var done: [Int] = []
            for c in choices where c.source == source {
                guard page.lines.indices.contains(c.line), page.lines[c.line].text == c.applied else {
                    setCorrectionError(String(localized: "Page \(source + 1), ligne \(c.line + 1) : le texte a changé depuis le choix, il est gardé."))
                    continue
                }
                page.lines[c.line] = c.previous
                done.append(c.line)
            }
            guard !done.isEmpty else { continue }
            do {
                try await service.store(page, documentId: documentId, pageIndex: source)
            } catch {
                setCorrectionError(String(localized: "Page \(source + 1) non enregistrée : \(error.localizedDescription)"))
                continue
            }
            update(documentId) { r in
                for line in done {
                    guard let i = r.pages[source]?.disagreements.firstIndex(where: { $0.line == line && $0.settled }) else { continue }
                    r.pages[source]?.disagreements[i].settled = false
                    r.pages[source]?.confirmed -= 1
                }
            }
        }
    }

    /// « Garder tel quel » est une acceptation explicite du texte de base, pas seulement du rapport.
    /// La clôture reste conditionnée à l'enregistrement réussi et au texte inchangé depuis l'analyse.
    @discardableResult
    func dismiss(source: Int, line: Int, documentId: String, service: OCRService) async -> [AppliedChoice] {
        guard let vote = report(for: documentId)?.pages[source]?.disagreements.first(where: { $0.line == line && !$0.settled }) else { return [] }
        return await apply([(source: source, line: line, text: vote.base)], documentId: documentId, service: service)
    }
}
