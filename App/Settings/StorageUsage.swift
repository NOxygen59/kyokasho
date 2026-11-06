// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Charts
import GLMOCRKit
import OCRKit
import ONNXOCRKit
import SwiftUI
import WebKit

/// Place prise par l'app sur l'iPad, par catégorie (Réglages → Stockage). Tailles réelles sur le disque
/// (`totalFileAllocatedSize`), calculées hors du fil principal.
enum StorageUsage {
    struct Item: Identifiable, Equatable, Sendable {
        var id: String { name }
        let name: String
        let detail: String
        let bytes: Int64
    }

    static func compute() -> [Item] {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let app = support.appendingPathComponent("Kyokasho", isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let models = ModelStore.shared.root

        var items: [Item] = []
        // Déjà comptés dans une catégorie précise : retirés des catégories « reste ».
        var counted: [URL] = []
        func add(_ name: String, _ detail: String, _ urls: [URL]) {
            let bytes = urls.reduce(Int64(0)) { $0 + size(of: $1) }
            counted += urls
            if bytes > 0 { items.append(Item(name: name, detail: detail, bytes: bytes)) }
        }

        add(String(localized: "Documents (PDF)"), String(localized: "Tes PDF importés"), [app.appendingPathComponent("Documents", isDirectory: true)])
        // Un élément par modèle d'IA installé (les petits ensemble).
        let titles = Dictionary(uniqueKeysWithValues: [ModelSpec.ndlocr, .ppocr5, .glmocr, .ovisocr2, .qwen3vl4b,
                                                       .qwen35chat].map { ($0.id, $0.title) })
        var small: [URL] = []
        for folder in (try? fm.contentsOfDirectory(at: models, includingPropertiesForKeys: nil)) ?? [] {
            if folder.lastPathComponent == "unidic" { continue }
            if size(of: folder) >= 200 * 1_048_576 {
                add(titles[folder.lastPathComponent] ?? folder.lastPathComponent, String(localized: "Modèle d'IA"), [folder])
            } else {
                small.append(folder)
            }
        }
        add(String(localized: "Autres modèles"), String(localized: "Mise en page, nettoyage des scans…"), small)
        add(String(localized: "UniDic (furigana)"), String(localized: "Dictionnaire de MeCab"), [models.appendingPathComponent("unidic", isDirectory: true)])
        add(String(localized: "Dictionnaires"), String(localized: "Yomitan importés"), [app.appendingPathComponent("Dictionaries", isDirectory: true)])
        add(String(localized: "Analyses IA"), String(localized: "Lectures IA, traductions, rapports"), [support.appendingPathComponent("Analysis", isDirectory: true)])
        let base = ((try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("kyokasho.sqlite") }
        add(String(localized: "Base (OCR, notes, cartes)"), String(localized: "Textes lus, corrections, notes, surlignages, révisions"), base)
        add(String(localized: "Caches"), String(localized: "Vignettes, pages nettoyées, téléchargements (régénérables)"), [caches])
        add(String(localized: "Temporaires"), String(localized: "Exports, fichiers en cours"), [fm.temporaryDirectory])
        // Tout le reste du conteneur (données WebKit, réglages, journal…).
        let rest = size(of: library) + size(of: documents) - counted.filter { $0.path.hasPrefix(library.path) || $0.path.hasPrefix(documents.path) }
            .reduce(Int64(0)) { $0 + size(of: $1) }
        if rest > 0 { items.append(Item(name: String(localized: "Autres"), detail: String(localized: "Réglages, journal, données web"), bytes: rest)) }
        return items.sorted { $0.bytes > $1.bytes }
    }

    /// « Effacer le cache » : seulement ce que l'app sait refaire (vignettes, pages nettoyées, téléchargements de
    /// mise à jour, fichiers temporaires). Jamais : PDF, base (OCR, notes, cartes), analyses IA, modèles, UniDic,
    /// dictionnaires, réglages. Les dossiers restent (les caches les attendent), seul leur contenu part ; ce qui
    /// a bougé depuis moins de 5 min (export ou téléchargement en cours) est laissé. Rend la place libérée.
    static func clearCaches() -> Int64 {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let roots = [caches, fm.temporaryDirectory]
        let before = roots.reduce(Int64(0)) { $0 + size(of: $1) }
        let recent = Date().addingTimeInterval(-300)
        func empty(_ folder: URL, depth: Int) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
            for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [] {
                let values = try? item.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true, depth == 0 {
                    empty(item, depth: 1)
                } else if (values?.contentModificationDate ?? .distantPast) < recent {
                    try? fm.removeItem(at: item)
                }
            }
        }
        roots.forEach { empty($0, depth: 0) }
        let after = roots.reduce(Int64(0)) { $0 + size(of: $1) }
        return max(0, before - after)
    }

    /// Taille sur le disque d'un fichier ou d'un dossier (0 s'il n'existe pas).
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e {
            guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Réglages → Stockage → « Place prise par l'app » : barre empilée + légende détaillée.
struct StorageUsageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [StorageUsage.Item]?
    @State private var free: Int64?
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var cleared: Int64?

    private var total: Int64 { items?.reduce(0) { $0 + $1.bytes } ?? 0 }

    var body: some View {
        List {
            if let items {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(StorageUsage.format(total)).font(.title2.weight(.semibold))
                            Text("utilisés par Kyōkasho").foregroundStyle(.secondary)
                            Spacer()
                            if let free { Text("\(StorageUsage.format(free)) libres").font(.caption).foregroundStyle(.secondary) }
                        }
                        Chart(items) { item in
                            BarMark(x: .value("Taille", item.bytes), y: .value("App", "Kyōkasho"))
                                .foregroundStyle(by: .value("Catégorie", item.name))
                        }
                        .chartForegroundStyleScale(domain: items.map(\.name), range: colors(items.count))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartLegend(.hidden)
                        .frame(height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: Atelier.corner(6)))
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Button(role: .destructive) { confirmClear = true } label: {
                        HStack {
                            Label("Effacer le cache", systemImage: "trash")
                            Spacer()
                            if clearing { ProgressView() }
                        }
                    }
                    .disabled(clearing)
                } footer: {
                    if let cleared {
                        Text("\(StorageUsage.format(cleared)) libérés.")
                    } else {
                        Text("Vignettes, pages nettoyées, fichiers temporaires et cache web : l'app les refait au besoin. Tes PDF, notes, textes lus, analyses et modèles restent.")
                    }
                }
                Section("Détail") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: Atelier.corner(3)).fill(colors(items.count)[i]).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(StorageUsage.format(item.bytes)).monospacedDigit()
                                Text("\(percent(item)) %").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 10) { ProgressView(); Text("Calcul de la place prise…").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Place prise par l'app")
        .confirmationDialog("Effacer le cache ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer le cache", role: .destructive) { Task { await clear() } }
        } message: {
            Text("Rien d'important n'est perdu : PDF, notes, textes lus, analyses, modèles et réglages restent.")
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        let result = await Task.detached(priority: .utility) { StorageUsage.compute() }.value
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        items = result
        free = values?.volumeAvailableCapacityForImportantUsage
    }

    private func clear() async {
        clearing = true
        defer { clearing = false }
        // Mémoire : caches des pages et modèles inactifs (une lecture en cours garde le sien).
        model.thumbnails.trim()
        ScanSharpening.clearMemory()
        FuriganaLayer.clearMemory()
        LayoutRegionsCache.shared.clear()
        PDFPool.release()
        ONNXEngines.unload()
        await GLMOCREngine.unloadIfIdle()
        // Cache web seulement : les connexions (cookies) du navigateur à côté restent.
        let web: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                                WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache]
        await WKWebsiteDataStore.default().removeData(ofTypes: web, modifiedSince: .distantPast)
        cleared = await Task.detached(priority: .userInitiated) { StorageUsage.clearCaches() }.value
        await refresh()
    }

    private func percent(_ item: StorageUsage.Item) -> String {
        guard total > 0 else { return "0" }
        let p = Double(item.bytes) / Double(total) * 100
        return p < 1 ? "< 1" : String(Int(p.rounded()))
    }

    /// Couleurs du thème, puis variantes plus claires si les catégories sont nombreuses.
    private func colors(_ n: Int) -> [Color] {
        let base = [Atelier.Tint.read, Atelier.Tint.ai, Atelier.Tint.japanese, Atelier.Tint.annotate, Atelier.Tint.cloud]
        return (0..<n).map { i in base[i % base.count].opacity(i < base.count ? 1 : 0.55) }
    }
}
