// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

/// Texte de la page lue (OCR ou texte intégré), affiché façon « lecteur de texte » d'Aidoku.
struct TextPageSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    var close: () -> Void
    @State private var showCompare = false
    @State private var addedToBench = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Texte — page \(reader.currentSourcePage + 1)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button { reader.runOCR(engine: OCREngineID.pdfText) } label: { Label("Texte du PDF", systemImage: "doc.plaintext") }
                            Button { reader.runOCR(engine: OCREngineID.vision) } label: { Label("Apple Vision", systemImage: "eye") }
                            Divider()
                            Button { reader.runOCR(engine: reader.ocrPage?.engine, force: true) } label: {
                                Label("Relancer l'OCR", systemImage: "arrow.clockwise")
                            }
                            Button { showCompare = true } label: { Label("Comparer les moteurs", systemImage: "rectangle.split.2x1") }
                        } label: {
                            Label(reader.ocrPage.map { OCREngineID.displayName($0.engine) } ?? "Moteur", systemImage: "cpu")
                        }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        Button { UIPasteboard.general.string = reader.ocrPage?.text } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("Copier le texte")
                            .disabled(reader.ocrPage == nil)
                        Button { addToBench() } label: {
                            Image(systemName: addedToBench ? "checkmark.circle" : "gauge.with.dots.needle.33percent")
                        }
                        .accessibilityLabel("Ajouter au banc d'essai")
                        .disabled(reader.ocrPage == nil || addedToBench)
                        Button("OK", action: close)
                    }
                }
                .sheet(isPresented: $showCompare) {
                    CompareEnginesView(reader: reader).environmentObject(model).environmentObject(model.dictionary)
                }
                .onAppear { if reader.ocrPage == nil && reader.ocrState != .running { reader.runOCR() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (reader.ocrPage, reader.ocrState) {
        case (_, .running):
            VStack(spacing: 12) {
                ProgressView()
                Text("Lecture de la page…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (_, .failed(let message)):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Essayer avec Apple Vision") { reader.runOCR(engine: OCREngineID.vision) }.buttonStyle(.bordered)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (let page?, _):
            VStack(spacing: 0) {
                OCRTextView(text: page.text, settings: model.appSettings.textReader)
                Divider()
                HStack {
                    Text("\(OCREngineID.displayName(page.engine)) · \(page.lines.count) lignes · \(page.durationMs) ms")
                    Spacer()
                    if page.lines.contains(where: { !$0.measuredCharBoxes }) {
                        Text("boîtes de caractères estimées").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        default:
            Text("Aucun texte pour l'instant.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Ajoute la page au banc d'essai : image de la page + texte actuel comme référence à corriger.
    private func addToBench() {
        guard let image = reader.renderCurrentPage(maxWidth: 2048), let png = image.pngData() else { return }
        let file = UUID().uuidString + ".png"
        do {
            try png.write(to: model.benchDirectory.appendingPathComponent(file))
            let sample = BenchSample(title: "\(reader.document.title) — p. \(reader.currentSourcePage + 1)",
                                     imageFile: file, referenceText: reader.ocrPage?.text ?? "")
            model.persist { try $0.save(sample) }
            addedToBench = true
        } catch {
            model.lastError = error.localizedDescription
        }
    }
}

/// Texte affiché selon les réglages du lecteur de texte : défilement ou pages.
struct OCRTextView: View {
    let text: String
    let settings: TextReaderSettings

    private var font: Font {
        switch settings.font {
        case .gothic: return .custom("HiraginoSans-W3", size: settings.fontSize)
        case .mincho: return .custom("HiraMinProN-W3", size: settings.fontSize)
        case .system: return .system(size: settings.fontSize)
        }
    }

    var body: some View {
        GeometryReader { geo in
            switch settings.style {
            case .scroll:
                ScrollView {
                    Text(text)
                        .font(font)
                        .lineSpacing(settings.fontSize * settings.lineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, settings.horizontalMargin)
                        .padding(.vertical, 24)
                }
            case .pages:
                let pages = TextPaginator.pages(text, size: geo.size, settings: settings)
                TabView {
                    ForEach(pages.indices, id: \.self) { i in
                        Text(pages[i])
                            .font(font)
                            .lineSpacing(settings.fontSize * settings.lineSpacing)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, settings.horizontalMargin)
                            .padding(.vertical, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            }
        }
    }
}

/// Découpe approximative en pages : capacité estimée selon la taille du texte et de la vue
/// (un caractère japonais ≈ un carré de la taille de police, demi-chasse = moitié).
enum TextPaginator {
    static func pages(_ text: String, size: CGSize, settings: TextReaderSettings) -> [String] {
        let usableWidth = max(100, size.width - settings.horizontalMargin * 2)
        let usableHeight = max(100, size.height - 60)
        let lineHeight = settings.fontSize * (1.2 + settings.lineSpacing)
        let linesPerPage = max(1, Int(usableHeight / lineHeight))
        let perLine = max(4, usableWidth / settings.fontSize)
        var pages: [String] = []
        var current: [String] = []
        var used = 0
        for line in text.components(separatedBy: "\n") {
            let weight = line.reduce(0.0) { $0 + CharacterLayout.widthWeight($1) }
            let rows = max(1, Int((weight / perLine).rounded(.up)))
            if used + rows > linesPerPage, !current.isEmpty {
                pages.append(current.joined(separator: "\n"))
                current = []
                used = 0
            }
            current.append(line)
            used += rows
        }
        if !current.isEmpty { pages.append(current.joined(separator: "\n")) }
        return pages.isEmpty ? [""] : pages
    }
}

/// « Comparer » : texte de deux moteurs côte à côte pour la page lue.
struct CompareEnginesView: View {
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var results: [String: Result<OCRPage, Error>] = [:]
    private let engines = [OCREngineID.pdfText, OCREngineID.vision]

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                ForEach(engines, id: \.self) { engine in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(OCREngineID.displayName(engine)).font(.headline)
                        switch results[engine] {
                        case nil:
                            ProgressView()
                        case .failure(let error)?:
                            Text(error.localizedDescription).foregroundStyle(.secondary)
                        case .success(let page)?:
                            Text("\(page.durationMs) ms · \(page.lines.count) lignes").font(.caption).foregroundStyle(.secondary)
                            if let other = otherText(than: engine) {
                                Text("Écart avec l'autre moteur : \(Int((CharacterErrorRate.cer(reference: other, hypothesis: page.text) * 100).rounded())) %")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ScrollView {
                                Text(page.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if engine != engines.last { Divider() }
                }
            }
            .navigationTitle("Comparer — page \(reader.currentSourcePage + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task {
                for engine in engines {
                    do { results[engine] = .success(try await reader.ocr(engine: engine)) }
                    catch { results[engine] = .failure(error) }
                }
            }
        }
    }

    private func otherText(than engine: String) -> String? {
        for e in engines where e != engine {
            if case .success(let page)? = results[e] { return page.text }
        }
        return nil
    }
}
