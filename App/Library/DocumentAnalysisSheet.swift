// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

/// Bibliothèque → document → « Analyser le document entier » : lancement, progression, fiabilité, désaccords.
struct DocumentAnalysisSheet: View {
    let document: LibraryDocument
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var service = DocumentAnalysisService.shared
    @Environment(\.dismiss) private var dismiss

    private var running: DocumentAnalysisService.Progress? {
        service.progress?.documentId == document.id ? service.progress : nil
    }
    private var report: DocumentAnalysis? {
        _ = service.revision  // relu à chaque enregistrement
        return service.report(for: document.id)
    }

    var body: some View {
        NavigationStack {
            List {
                if let p = running {
                    progressSection(p)
                } else if let report, !report.pages.isEmpty {
                    resultSection(report)
                } else {
                    startSection
                }
                if let error = service.lastError { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("Analyse · \(document.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    // MARK: Avant

    private var startSection: some View {
        let readers = DocumentAnalysisService.readers
        let minutes = max(1, document.pageCount * readers.count * 45 / 60)
        return Group {
            Section {
                Text("Chaque page est lue par ton OCR habituel **et** par \(readers.isEmpty ? "aucun autre modèle" : readers.map(Self.name).joined(separator: " et ")). Une ligne est confirmée quand deux lectures indépendantes donnent le même texte ; à la fin, une note de fiabilité et la liste des désaccords, avec un choix conseillé.")
                    .font(.footnote)
                if readers.isEmpty {
                    Text("Télécharge OvisOCR2 (et si tu veux GLM-OCR) dans Réglages → Modèles d'IA et outils.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section {
                LabeledContent("Pages", value: "\(document.pageCount)")
                LabeledContent("Durée estimée", value: minutes >= 60 ? "≈ \(minutes / 60) h \(minutes % 60) min" : "≈ \(minutes) min")
                Button {
                    service.start(document, model: model)
                } label: {
                    Label("Analyser le document entier", systemImage: "checkmark.seal")
                }
                .disabled(readers.isEmpty || service.progress != nil)
            } footer: {
                Text("Très gourmand (mémoire, batterie, chaleur) : branche l'iPad et laisse l'app ouverte, l'écran reste allumé. Tu peux arrêter à tout moment : l'analyse reprendra là où elle s'est arrêtée. Rien ne part en ligne.")
            }
        }
    }

    // MARK: Pendant

    private func progressSection(_ p: DocumentAnalysisService.Progress) -> some View {
        let fraction = p.total > 0 ? Double(p.done) / Double(p.total) : 0
        let elapsed = Date().timeIntervalSince(p.phaseStarted)
        let left = p.done > 0 ? elapsed / Double(p.done) * Double(p.total - p.done) : 0
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.phase).font(.headline)
                ProgressView(value: fraction)
                Text("Page \(p.done) sur \(p.total)\(p.done > 0 ? " · encore ≈ \(Int(left / 60) + 1) min pour cette étape" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if p.cancelling {
                HStack { ProgressView(); Text("Arrêt après la page en cours…").font(.footnote) }
            } else {
                Button("Arrêter (reprendra plus tard)", role: .destructive) { service.cancel() }
            }
        } footer: {
            Text("Laisse l'app ouverte. Étapes : OCR habituel, puis chaque modèle sur toutes les pages, puis le vote.")
        }
    }

    // MARK: Après

    @ViewBuilder
    private func resultSection(_ report: DocumentAnalysis) -> some View {
        let open = report.pages.values.sorted { $0.source < $1.source }.flatMap { page in
            page.disagreements.filter { !$0.settled }.map { (page.source, $0) }
        }
        let advised = open.filter { $0.1.advised != nil && $0.1.advised != $0.1.baseKey }
        Section {
            HStack {
                Text("\(Int((report.reliability * 1000).rounded()) / 10, specifier: "%.1f") %")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(report.reliability > 0.97 ? .green : report.reliability > 0.9 ? .orange : .red)
                VStack(alignment: .leading) {
                    Text("lignes confirmées par au moins deux lectures").font(.footnote)
                    Text("\(open.count) désaccord(s) à voir · \(report.engines.map(Self.name).joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                    if report.errorPages > 0 || report.uncheckedPages > 0 {
                        Text("\(report.errorPages) page(s) en erreur · \(report.uncheckedPages) page(s) sans comparaison possible")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            if !advised.isEmpty {
                Button {
                    Task {
                        await service.apply(advised.map { ($0.0, $0.1.line, $0.1.advised!) }, documentId: document.id, service: model.ocr)
                    }
                } label: { Label("Appliquer les \(advised.count) choix conseillés", systemImage: "wand.and.stars") }
            }
            Button { service.start(document, model: model) } label: { Label("Relancer l'analyse (pages manquantes)", systemImage: "arrow.clockwise") }
            Button("Oublier cette analyse", role: .destructive) { service.forget(document.id) }
        } header: {
            Text("Fiabilité du texte")
        } footer: {
            Text("Choix conseillé : la majorité des lectures, ou, à égalité, celle que ton dictionnaire comprend le mieux. Ton OCR habituel reste le texte de base ; tu peux aussi choisir un autre moteur pour ce document (lecteur → « … » → réglages de ce document).")
        }
        let worst = report.pages.values.filter { $0.lines - $0.unchecked > 0 }.sorted { $0.reliability < $1.reliability }.prefix(8)
        if !worst.isEmpty {
            Section("Pages les moins sûres") {
                ForEach(Array(worst)) { page in
                    LabeledContent("Page \(document.pageLabel(page.source))", value: "\(Int(page.reliability * 100)) %")
                }
            }
        }
        let failed = report.pages.values.filter { $0.error != nil }.sorted { $0.source < $1.source }
        if !failed.isEmpty {
            Section("Pages en erreur") {
                ForEach(failed.prefix(30)) { page in
                    VStack(alignment: .leading) {
                        Text("Page \(document.pageLabel(page.source))").font(.caption.bold())
                        Text(page.error ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !open.isEmpty {
            Section("Désaccords") {
                ForEach(open.prefix(200), id: \.1.id) { source, vote in
                    disagreementRow(source: source, vote: vote)
                }
            }
        }
    }

    private func disagreementRow(source: Int, vote: DocumentAnalysis.LineVote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("p. \(document.pageLabel(source)) · ligne \(vote.line + 1)").font(.caption).foregroundStyle(.secondary)
            choice(Self.name("ocr"), vote.base, source: source, line: vote.line, advised: vote.advised == vote.baseKey)
            ForEach(vote.readings.sorted(by: { $0.key < $1.key }), id: \.key) { engine, text in
                choice(Self.name(engine), text, source: source, line: vote.line, advised: vote.advised == text)
            }
            Button("Garder tel quel") { service.dismiss(source: source, line: vote.line, documentId: document.id) }
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func choice(_ label: String, _ text: String, source: Int, line: Int, advised: Bool) -> some View {
        Button {
            Task { await service.apply([(source, line, text)], documentId: document.id, service: model.ocr) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption2.bold()).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text(text).font(Atelier.jp).foregroundStyle(.primary)
                if advised { Text("conseillé").font(.caption2.bold()).foregroundStyle(.green) }
            }
        }
        .buttonStyle(.plain)
    }

    static func name(_ engine: String) -> String { DocumentAnalysisService.name(engine) }
}
