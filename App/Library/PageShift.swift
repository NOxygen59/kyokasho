// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import PDFKit
import ReaderCore

/// Remplacement du PDF d'un document par une version avec des pages en plus (« Ajouter des pages… »), sans jamais
/// désaligner le PDF et les données rangées par numéro de page. Étapes notées dans `page-shift.json` (Application
/// Support) : si l'app s'arrête au milieu, `reconcile` au lancement annule (PDF pas encore remplacé) ou termine.
/// Ordre : base (transaction) → PDF (remplacement atomique) → rapport d'analyse → fichiers IA par page → cartes.
@MainActor
enum PageShift {
    struct Pending: Codable {
        var documentId: String
        var offset: Int
        var oldCount: Int
        var oldSize: Int64
        var newCount: Int
        var newSize: Int64
        /// db, pdf, report, files, cards : l'étape commencée.
        var stage: String
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true)
    }
    private static var marker: URL { support.appendingPathComponent("page-shift.json") }
    private static func staged(_ id: String) -> URL { support.appendingPathComponent("page-shift-\(id).pdf") }

    private static func save(_ p: Pending) throws {
        try JSONEncoder().encode(p).write(to: marker, options: .atomic)
    }

    private static func clear(_ id: String) {
        try? FileManager.default.removeItem(at: marker)
        try? FileManager.default.removeItem(at: staged(id))
    }

    /// `merged` : nouveau PDF complet (fichier temporaire, déplacé). Rend des avertissements (rien de bloquant).
    static func apply(_ model: AppModel, document: LibraryDocument, merged: URL, offset: Int, newCount: Int) throws -> [String] {
        let fm = FileManager.default, id = document.id
        let current = model.storage.url(for: id), staged = staged(id)
        try? fm.removeItem(at: staged)
        try fm.moveItem(at: merged, to: staged)
        let newSize = (try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var p = Pending(documentId: id, offset: offset, oldCount: document.pageCount, oldSize: document.fileSize,
                        newCount: newCount, newSize: newSize, stage: "db")
        try save(p)
        do {
            try model.database.shiftPages(documentId: id, by: offset, pageCount: newCount, fileSize: newSize)
        } catch {
            clear(id)
            throw error
        }
        p.stage = "pdf"
        try? save(p)
        do {
            _ = try fm.replaceItemAt(current, withItemAt: staged)
        } catch {
            // PDF inchangé : la base revient en arrière (sinon le suivi le fera au prochain lancement).
            if (try? model.database.shiftPages(documentId: id, by: -offset, pageCount: p.oldCount, fileSize: p.oldSize)) != nil {
                clear(id)
            }
            throw error
        }
        return finish(&p, model)
    }

    /// Étapes après le remplacement du PDF (reprises au lancement si besoin).
    private static func finish(_ p: inout Pending, _ model: AppModel) -> [String] {
        var warnings: [String] = []
        if p.stage == "pdf" {
            p.stage = "report"
            try? save(p)
            DocumentAnalysisService.shared.shiftReport(p.documentId, by: p.offset)
        }
        if p.stage == "report" {
            p.stage = "files"
            try? save(p)
        }
        if p.stage == "files" {
            let lost = shiftAnalysisFiles(p.documentId, by: p.offset)
            if lost > 0 { warnings.append("\(lost) lecture(s) IA n'ont pas pu suivre leur page : elles seront refaites.") }
            p.stage = "cards"
            try? save(p)
            do { try model.review.store.shiftSourcePages(documentId: p.documentId, by: p.offset) } catch {
                warnings.append("Cartes : page d'origine pas décalée (\(error.localizedDescription)).")
            }
        }
        clear(p.documentId)
        return warnings
    }

    /// Au lancement : opération interrompue → annulée (PDF d'avant) ou terminée (nouveau PDF en place).
    static func reconcile(_ model: AppModel) {
        guard let data = try? Data(contentsOf: marker), var p = try? JSONDecoder().decode(Pending.self, from: data) else { return }
        let id = p.documentId
        let pages = PDFDocument(url: model.storage.url(for: id))?.pageCount
        switch p.stage {
        case "db", "pdf":
            if pages == p.newCount, p.stage == "pdf" {
                _ = finish(&p, model)
            } else {
                // Nouveau PDF pas en place : base remise comme avant si elle avait été décalée.
                if (try? model.database.document(id: id))??.pageCount == p.newCount {
                    try? model.database.shiftPages(documentId: id, by: -p.offset, pageCount: p.oldCount, fileSize: p.oldSize)
                }
                clear(id)
            }
        case "report", "files":
            _ = finish(&p, model)
        default:
            // Cartes : peut-être déjà décalées, ne pas risquer de le faire deux fois.
            clear(id)
        }
    }

    /// Fichiers `Analysis/<id>/<lecteur>-<page>.md` renumérotés via un dossier de passage (`<id>.shift`) : chaque
    /// déplacement est atomique, et un arrêt au milieu se reprend (les fichiers restés dans l'ancien dossier
    /// n'ont pas encore bougé). Un fichier qui ne peut pas suivre sa page est supprimé (jamais sur la mauvaise
    /// page) ; rend leur nombre.
    nonisolated static func shiftAnalysisFiles(_ id: String, by offset: Int) -> Int {
        let fm = FileManager.default
        let root = DocumentAnalysisService.folder
        let old = root.appendingPathComponent(id, isDirectory: true)
        let pass = root.appendingPathComponent(id + ".shift", isDirectory: true)
        guard fm.fileExists(atPath: old.path) || fm.fileExists(atPath: pass.path) else { return 0 }
        try? fm.createDirectory(at: pass, withIntermediateDirectories: true)
        var lost = 0
        for url in (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "md", let dash = name.lastIndex(of: "-"),
                  let page = Int(name[name.index(after: dash)...]) else {
                try? fm.moveItem(at: url, to: pass.appendingPathComponent(url.lastPathComponent))
                continue
            }
            let target = pass.appendingPathComponent("\(name[..<dash])-\(page + offset).md")
            if (try? fm.moveItem(at: url, to: target)) == nil {
                try? fm.removeItem(at: url)
                lost += 1
            }
        }
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: pass, to: old)
        return lost
    }
}
