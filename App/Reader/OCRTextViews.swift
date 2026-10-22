// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

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
                PagedText(text: text, size: geo.size, settings: settings, font: font)
            }
        }
    }
}

/// Mode « pages » : découpage calculé une seule fois par texte / taille / réglages
/// (et non à chaque redessin de la vue).
private struct PagedText: View {
    let text: String
    let size: CGSize
    let settings: TextReaderSettings
    let font: Font
    @State private var pages: [String]

    init(text: String, size: CGSize, settings: TextReaderSettings, font: Font) {
        self.text = text
        self.size = size
        self.settings = settings
        self.font = font
        _pages = State(initialValue: TextPaginator.pages(text, size: size, settings: settings))
    }

    private struct Key: Equatable {
        var text: String
        var size: CGSize
        var settings: TextReaderSettings
    }

    var body: some View {
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
        .onChange(of: Key(text: text, size: size, settings: settings)) { key in
            pages = TextPaginator.pages(key.text, size: key.size, settings: key.settings)
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
    private let engines = [OCREngineID.pdfText, OCREngineID.vision] + OCREngineMenu.extra

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
            .navigationTitle("Comparer — page \(reader.document.pageLabel(reader.currentSourcePage))")
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
