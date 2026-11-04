// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import PDFKit
import PencilKit
import ReaderCore
import ReviewKit
import SwiftUI
import UIKit

/// Exporter un document depuis la bibliothèque (appui long → « Exporter… »), dans le format choisi et pour les pages
/// choisies. Tout est fait hors du fil principal ; le fichier part dans `tmp/Export` puis dans la feuille de partage.
enum DocumentExport {
    enum Format: String, CaseIterable, Identifiable {
        case original, annotated, markdown, images, cards, package
        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: return String(localized: "PDF d'origine")
            case .annotated: return String(localized: "PDF annoté")
            case .markdown: return String(localized: "Texte (Markdown)")
            case .images: return String(localized: "Images PNG (zip)")
            case .cards: return String(localized: "Cartes Anki (.apkg)")
            case .package: return String(localized: "Paquet Kyōkasho (tout le document)")
            }
        }
        var detail: String {
            switch self {
            case .original: return String(localized: "Le fichier importé, tel quel.")
            case .annotated: return String(localized: "Surlignages, dessins au stylet et notes posés sur les pages ; notes en fin de fichier.")
            case .markdown: return String(localized: "Mise en page IA (sinon texte de l'OCR), traductions française et anglaise si elles existent, notes.")
            case .images: return String(localized: "Une image par page (avec annotations), dans un fichier zip.")
            case .cards: return String(localized: "Les cartes de révision créées depuis ce document.")
            case .package: return String(localized: "PDF, notes, surlignages, dessins, OCR et retouches, lectures IA, traductions, analyse et brouillons : à réimporter tel quel dans Kyōkasho sur un autre appareil. Sans cartes, conversations ni réglages de l'app.")
            }
        }
        var icon: String {
            switch self {
            case .original: return "doc"
            case .annotated: return "pencil.tip.crop.circle"
            case .markdown: return "text.alignleft"
            case .images: return "photo.on.rectangle"
            case .cards: return "rectangle.stack"
            case .package: return "shippingbox"
            }
        }
        /// Pas de choix de pages pour le fichier d'origine ni les cartes.
        var usesPages: Bool { self != .original && self != .cards && self != .package }
    }

    /// Ce qu'il faut lire dans la base, pris sur le fil principal (la base est partagée).
    struct Annotations: Sendable {
        var highlights: [Highlight] = []
        var comments: [PageComment] = []
        var ink: [Int: Data] = [:]
        var ocr: [Int: OCRPage] = [:]
    }

    /// Dossier propre à chaque export (`tmp/Export/<uuid>`, vidé par le système) : deux exports ne se gênent pas.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Nom de fichier sûr à partir du titre.
    static func baseName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Kyokasho" : String(cleaned.prefix(80))
    }

    static func annotations(_ database: AppDatabase, documentId: String, pages: ClosedRange<Int>) -> Annotations {
        var a = Annotations()
        a.highlights = ((try? database.highlights(documentId: documentId)) ?? []).filter { pages.contains($0.pageIndex) }
        a.comments = ((try? database.comments(documentId: documentId)) ?? []).filter { pages.contains($0.pageIndex) }
        for page in pages {
            if let ink = try? database.inkDrawing(documentId: documentId, pageIndex: page) { a.ink[page] = ink.data }
        }
        // OCR le plus récent de chaque page (corrections à la main comprises).
        let records = ((try? database.ocrResults(documentId: documentId)) ?? []).filter { pages.contains($0.pageIndex) }
        for record in records.sorted(by: { $0.createdAt < $1.createdAt }) {
            if let page = try? JSONDecoder().decode(OCRPage.self, from: record.json), !page.lines.isEmpty {
                a.ocr[record.pageIndex] = page
            }
        }
        return a
    }

    // MARK: PDF annoté / images

    /// Dessine les annotations d'une page dans le repère PDF de la page (y vers le haut), après
    /// `context.concatenate(page.transform(for: .cropBox))`.
    static func drawAnnotations(page index: Int, _ a: Annotations, in ctx: CGContext) {
        for h in a.highlights where h.pageIndex == index {
            ctx.setFillColor(h.color.uiColor.withAlphaComponent(0.35).cgColor)
            for r in h.rects { ctx.fill(CGRect(x: r.x, y: r.y, width: r.width, height: r.height)) }
        }
        if let data = a.ink[index], let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty {
            // Encre en repère de page ; l'image de PencilKit a l'axe y vers le bas : retournée pour le repère PDF.
            let rect = drawing.bounds.insetBy(dx: -2, dy: -2)
            let image = drawing.image(from: rect, scale: 3)
            if let cg = image.cgImage {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cg, in: rect)
                ctx.restoreGState()
            }
        }
        // Notes ancrées : pastille numérotée sur le mot (le texte des notes est en fin de fichier).
        let notes = a.comments.filter { $0.pageIndex == index }
        for (n, note) in notes.enumerated() {
            guard let r = note.anchorRect else { continue }
            let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            ctx.setStrokeColor(UIColor.systemOrange.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(rect.insetBy(dx: -1, dy: -1))
            let badge = CGRect(x: rect.maxX - 2, y: rect.maxY - 2, width: 12, height: 12)
            ctx.setFillColor(UIColor.systemOrange.cgColor)
            ctx.fillEllipse(in: badge)
            drawText("\(n + 1)", at: CGPoint(x: badge.midX, y: badge.midY), size: 8, color: .white, in: ctx)
        }
    }

    /// Texte centré sur un point, dans un repère PDF (y vers le haut).
    static func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor, in ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: color]))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func annotatedPDF(source: URL, pages: ClosedRange<Int>, _ a: Annotations, title: String,
                             labels: [Int: String], to url: URL, progress: (Int) -> Void) throws {
        guard let doc = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: title] as CFDictionary)
        else { throw CocoaError(.fileWriteUnknown) }
        for (k, index) in pages.enumerated() {
            try Task.checkCancellation()
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .cropBox)
            var media = CGRect(origin: .zero, size: page.rotation % 180 == 0 ? bounds.size
                                                   : CGSize(width: bounds.height, height: bounds.width))
            ctx.beginPage(mediaBox: &media)
            page.draw(with: .cropBox, to: ctx)
            ctx.saveGState()
            ctx.concatenate(page.transform(for: .cropBox))
            drawAnnotations(page: index, a, in: ctx)
            ctx.restoreGState()
            ctx.endPage()
            progress(k + 1)
        }
        // Notes en fin de fichier, page par page.
        let notes = a.comments.sorted { ($0.pageIndex, $0.createdAt) < ($1.pageIndex, $1.createdAt) }
        if !notes.isEmpty { notesPages(notes, labels: labels, in: ctx) }
        ctx.closePDF()
    }

    /// Pages A4 de texte : « p. X — n° : note ».
    private static func notesPages(_ notes: [PageComment], labels: [Int: String], in ctx: CGContext) {
        let text = NSMutableAttributedString(string: "Notes\n\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 18)])
        var counter: [Int: Int] = [:]
        for note in notes {
            counter[note.pageIndex, default: 0] += 1
            let label = labels[note.pageIndex] ?? String(note.pageIndex + 1)
            let anchor = note.anchorText.map { " « \($0) »" } ?? ""
            text.append(NSAttributedString(string: "p. \(label) — n° \(counter[note.pageIndex]!)\(anchor)\n",
                                           attributes: [.font: UIFont.boldSystemFont(ofSize: 12)]))
            text.append(NSAttributedString(string: note.body.isEmpty ? String(localized: "(dessin seulement)\n\n") : note.body + "\n\n",
                                           attributes: [.font: UIFont.systemFont(ofSize: 12)]))
        }
        let setter = CTFramesetterCreateWithAttributedString(text)
        var start = 0
        while start < text.length {
            var media = CGRect(x: 0, y: 0, width: 595, height: 842)
            ctx.beginPage(mediaBox: &media)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0),
                                                 CGPath(rect: media.insetBy(dx: 48, dy: 56), transform: nil), nil)
            CTFrameDraw(frame, ctx)
            ctx.endPage()
            let shown = CTFrameGetVisibleStringRange(frame).length
            guard shown > 0 else { break }
            start += shown
        }
    }

    static func images(source: URL, pages: ClosedRange<Int>, _ a: Annotations, labels: [Int: String],
                       folder: URL, progress: (Int) -> Void) throws {
        guard let doc = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        for (k, index) in pages.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = doc.page(at: index) else { return }
                let bounds = page.bounds(for: .cropBox)
                let size = page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
                // ≈ 200 ppp, plafonné (mémoire de l'iPad).
                let scale = min(200 / 72, 3000 / max(size.width, size.height))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale),
                                                    format: format).image { r in
                    let ctx = r.cgContext
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: r.format.bounds.size))
                    // Repère PDF (y vers le haut) à l'échelle voulue.
                    ctx.translateBy(x: 0, y: size.height * scale)
                    ctx.scaleBy(x: scale, y: -scale)
                    page.draw(with: .cropBox, to: ctx)
                    ctx.concatenate(page.transform(for: .cropBox))
                    drawAnnotations(page: index, a, in: ctx)
                }
                let name = String(format: "p%04d", index + 1) + (labels[index].map { "-\($0)" } ?? "") + ".png"
                try image.pngData()?.write(to: folder.appendingPathComponent(baseName(name)))
            }
            progress(k + 1)
        }
    }

    /// Dossier → zip (fonction du système, sans bibliothèque).
    static func zip(_ folder: URL, to url: URL) throws {
        var result: Result<Void, Error> = .failure(CocoaError(.fileWriteUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            result = Result { try FileManager.default.copyItem(at: zipped, to: url) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    // MARK: Markdown

    static func markdown(documentId: String, title: String, pages: ClosedRange<Int>, _ a: Annotations,
                         labels: [Int: String], aiFile: (Int) -> URL, frenchFile: (Int) -> URL,
                         englishFile: ((Int) -> URL)? = nil) -> String {
        var out = "# \(title)\n"
        for index in pages {
            let label = labels[index] ?? String(index + 1)
            out += String(localized: "\n---\n\n## Page \(label)\n\n")
            if let ai = try? String(contentsOf: aiFile(index), encoding: .utf8), !ai.isEmpty {
                // Images de la mise en page IA : leurs coordonnées n'ont pas de sens hors de l'app.
                out += ai.replacingOccurrences(of: "<img[^>]*>", with: "", options: .regularExpression) + "\n"
            } else if let ocr = a.ocr[index] {
                out += ocr.lines.map(\.text).joined(separator: "\n") + "\n"
            } else {
                out += String(localized: "_(page pas encore lue)_\n")
            }
            if let fr = try? String(contentsOf: frenchFile(index), encoding: .utf8), !fr.isEmpty {
                out += String(localized: "\n### Traduction\n\n") + fr.replacingOccurrences(of: "<img[^>]*>", with: "", options: .regularExpression) + "\n"
            }
            // Traduction anglaise, si la page en a une (en plus ou à la place de la française).
            if let englishFile, let en = try? String(contentsOf: englishFile(index), encoding: .utf8), !en.isEmpty {
                out += String(localized: "\n### Translation (English)\n\n") + en.replacingOccurrences(of: "<img[^>]*>", with: "", options: .regularExpression) + "\n"
            }
            let highlights = a.highlights.filter { $0.pageIndex == index && !$0.text.isEmpty }
            if !highlights.isEmpty {
                out += String(localized: "\n### Surlignages\n\n") + highlights.map { "- \($0.text)" }.joined(separator: "\n") + "\n"
            }
            let notes = a.comments.filter { $0.pageIndex == index && !$0.body.isEmpty }
            if !notes.isEmpty {
                out += String(localized: "\n### Notes\n\n") + notes.map { n in
                    (n.anchorText.map { "- **\($0)** : " } ?? "- ") + n.body.replacingOccurrences(of: "\n", with: " ")
                }.joined(separator: "\n") + "\n"
            }
        }
        return out
    }
}

/// Feuille « Exporter… » : format, pages, puis partage du fichier.
struct DocumentExportSheet: View {
    let document: LibraryDocument
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var format = DocumentExport.Format.annotated
    @State private var first = 1
    @State private var last = 1
    @State private var working: (done: Int, total: Int)?
    @State private var result: URL?
    @State private var error: String?
    /// Export en cours (annulé si la feuille se ferme) et son numéro : un résultat d'un export remplacé est ignoré.
    @State private var task: Task<Void, Never>?
    @State private var run = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    ForEach(DocumentExport.Format.allCases) { f in
                        Button { format = f; result = nil } label: {
                            HStack(spacing: 12) {
                                Image(systemName: f.icon).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).foregroundStyle(.primary)
                                    Text(f.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if format == f { Image(systemName: "checkmark").foregroundStyle(Atelier.Tint.read) }
                            }
                        }
                    }
                }
                .disabled(working != nil)
                if format.usesPages {
                    Section("Pages (\(document.pageCount) dans le PDF)") {
                        Stepper("De la page \(first)", value: $first, in: 1...max(1, last))
                        Stepper("À la page \(last)", value: $last, in: first...max(first, document.pageCount))
                        Button("Tout le document") { first = 1; last = document.pageCount }
                    }
                    .disabled(working != nil)
                }
                Section {
                    if let working {
                        ProgressView(value: Double(working.done), total: Double(max(1, working.total))) {
                            Text("Préparation… \(working.done) / \(working.total)")
                        }
                    } else if let result {
                        Label("Fichier prêt : \(result.lastPathComponent)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        ShareLink(item: result) {
                            Label("Enregistrer ou envoyer le fichier", systemImage: "square.and.arrow.up")
                                .font(.headline)
                        }
                    } else {
                        Button { start() } label: { Label("Préparer le fichier", systemImage: "doc.badge.gearshape") }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    Text(verbatim: result == nil ? String(localized: "Étape 1 sur 2 : préparer") : String(localized: "Étape 2 sur 2 : enregistrer ou envoyer"))
                } footer: {
                    if working != nil {
                        Text("Garde cette fenêtre ouverte : la fermer annule la préparation.")
                    } else if result != nil {
                        Text("Le fichier n'est pas encore enregistré : touche le bouton ci-dessus pour choisir où le mettre.")
                    } else {
                        Text("Rien n'est enregistré à cette étape. Un bouton apparaîtra ici quand le fichier sera prêt.")
                    }
                }
            }
            .navigationTitle("Exporter « \(document.title) »")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onAppear { last = max(1, document.pageCount) }
            .onDisappear { task?.cancel() }
            .onChange(of: first) { _ in result = nil }
            .onChange(of: last) { _ in result = nil }
        }
    }

    private func start() {
        error = nil
        result = nil
        task?.cancel()
        run = UUID()
        let runId = run, doc = document, source = model.storage.url(for: document.id)
        let pages = (first - 1)...(max(first, last) - 1)
        let name = DocumentExport.baseName(doc.title)
        let labels = Dictionary(uniqueKeysWithValues: pages.map { ($0, doc.pageLabel($0)) })
        let format = format
        // Lu ici (base et cartes partagées avec l'app), écrit hors du fil principal.
        let annotations = format == .annotated || format == .images || format == .markdown
            ? DocumentExport.annotations(model.database, documentId: doc.id, pages: pages) : DocumentExport.Annotations()
        var cards: (cards: [StudyCard], template: NoteTemplate, mediaRoot: URL)?
        if format == .cards {
            guard let template = review.defaultTemplate, let templateId = template.id else {
                error = String(localized: "Aucun modèle de carte."); return
            }
            let list = ((try? review.store.cards(limit: 1_000_000)) ?? [])
                .filter { $0.templateId == templateId && $0.sourceDocumentId == doc.id }
            guard !list.isEmpty else { error = String(localized: "Aucune carte créée depuis ce document."); return }
            cards = (list, template, review.store.mediaRoot)
        }
        // Paquet complet : valeurs de l'app lues ici, fichier écrit hors du fil principal.
        let database = model.database
        let drafts = NoteDraftStore.shared.drafts(documentId: doc.id)
        let preferences = DocumentPackageService.preferences(documentId: doc.id)
        let dictionaries = model.dictionary.dictionaries.map(\.title)
        let total = format.usesPages ? pages.count : 1
        let lower = pages.lowerBound
        let ai = pages.map { DocumentScan.file(doc.id, $0) }, fr = pages.map { DocumentAnalysisService.rawURL(doc.id, "fr", $0) }
        let en = pages.map { DocumentAnalysisService.rawURL(doc.id, TranslationLanguage.english.rawValue, $0) }
        working = (0, total)
        task = Task.detached(priority: .userInitiated) {
            // Progression ignorée une fois l'export fini ou remplacé (aucun retour à « Préparation… »).
            let report: @Sendable (Int) -> Void = { n in
                Task { @MainActor in if run == runId, working != nil { working = (n, total) } }
            }
            let outcome = Result<URL, Error> {
                let folder = try DocumentExport.folder()
                switch format {
                case .original:
                    let url = folder.appendingPathComponent(name + ".pdf")
                    try FileManager.default.copyItem(at: source, to: url)
                    return url
                case .cards:
                    let url = folder.appendingPathComponent(name + ".apkg")
                    try AnkiExport.apkg(cards: cards!.cards, template: cards!.template, deckName: doc.title,
                                        mediaRoot: cards!.mediaRoot, to: url)
                    return url
                case .annotated:
                    let url = folder.appendingPathComponent(name + String(localized: " (annoté).pdf"))
                    try DocumentExport.annotatedPDF(source: source, pages: pages, annotations, title: doc.title,
                                                    labels: labels, to: url, progress: report)
                    return url
                case .images:
                    let dir = folder.appendingPathComponent(name, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try DocumentExport.images(source: source, pages: pages, annotations, labels: labels,
                                              folder: dir, progress: report)
                    let url = folder.appendingPathComponent(name + " (images).zip")
                    try DocumentExport.zip(dir, to: url)
                    return url
                case .package:
                    return try DocumentPackageService.export(doc, database: database, pdf: source, drafts: drafts,
                                                             preferences: preferences, dictionaries: dictionaries, to: folder)
                case .markdown:
                    let text = DocumentExport.markdown(documentId: doc.id, title: doc.title, pages: pages, annotations,
                                                       labels: labels, aiFile: { ai[$0 - lower] },
                                                       frenchFile: { fr[$0 - lower] }, englishFile: { en[$0 - lower] })
                    let url = folder.appendingPathComponent(name + ".md")
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    return url
                }
            }
            await MainActor.run {
                guard run == runId else { return }
                working = nil
                switch outcome {
                case .success(let url): result = url
                case .failure(is CancellationError): break
                case .failure(let e): error = String(localized: "Export impossible : \(e.localizedDescription)")
                }
            }
        }
    }
}
