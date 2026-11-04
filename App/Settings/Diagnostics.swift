// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
#if canImport(MLX)
import MLX
#endif
import ReaderCore
import SwiftUI
import UIKit

/// Mode diagnostic : un journal texte (Documents/Diagnostics/journal.txt, visible dans l'app Fichiers) que
/// l'utilisateur peut partager pour aider à corriger un bug. Les erreurs sont toujours notées ; le détail
/// (chargement des modèles, durées, étapes de l'OCR) seulement si le mode est allumé.
enum Diagnostics {
    static let enabledKey = "diagnostics.enabled"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("journal.txt") }

    private static let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.diagnostics")
    private static let limit = 2_000_000

    /// Étape détaillée (seulement en mode diagnostic).
    static func log(_ message: @autoclosure () -> String, _ area: String = "app") {
        guard enabled else { return }
        write("[\(area)] \(message())")
    }

    /// Erreur : toujours notée.
    static func error(_ message: String, _ area: String = "app") {
        write("[\(area)] ERREUR : \(message)")
    }

    /// Écrit tout de suite (synchrone) : utilisé juste avant un arrêt de l'app.
    static func write(_ line: String, sync: Bool = false) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withFractionalSeconds])
        let text = "\(stamp) \(line)\n"
        let work = {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue, size > limit {
                // Trop gros : on garde la seconde moitié.
                if let data = try? Data(contentsOf: file) { try? data.suffix(limit / 2).write(to: file) }
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? Data(text.utf8).write(to: file)
            }
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// Attend les écritures déjà en file avant de lire ; aucun changement du fichier exporté.
    static func snapshot() -> String {
        queue.sync { DiagnosticLogSnapshot.read(from: file) }
    }

    /// Fin du journal pour l'écran « Journal » (RET-045, #67). Lit sur la file du journal pour ne pas croiser une
    /// écriture ou une rotation ; à appeler hors du fil principal.
    static func tail() -> DiagnosticLogSnapshot.Tail {
        queue.sync { DiagnosticLogSnapshot.readTail(from: file) }
    }

    /// Au lancement : en-tête (version, appareil, mémoire) et gestionnaire d'erreurs MLX global, qui note le
    /// message **avant** l'arrêt (sinon le rapport de plantage d'iOS ne le contient pas).
    static func start() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let memory = ProcessInfo.processInfo.physicalMemory / 1_048_576
        write("=== Lancement Kyōkasho \(version) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion) · mémoire \(memory) Mo · diagnostic \(enabled ? "activé" : "désactivé")")
        #if canImport(MLX)
        setErrorHandler({ message, _ in
            let text = message.map { String(cString: $0) } ?? "(sans message)"
            Diagnostics.write("[mlx] ERREUR FATALE : \(text) · mémoire de l'app \(Int(Diagnostics.footprintMB())) Mo", sync: true)
            fatalError("MLX : \(text)")
        })
        #endif
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Mesure une étape (mode diagnostic) : durée et mémoire avant / après.
    static func measure<T>(_ name: String, _ area: String = "app", _ body: () async throws -> T) async rethrows -> T {
        let start = Date()
        if enabled { log("→ \(name) (mémoire \(Int(footprintMB())) Mo)", area) }
        do {
            let result = try await body()
            let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
            remember(area, "✓ \(name) en \(seconds) s")
            if enabled { log("✓ \(name) en \(seconds) s (mémoire \(Int(footprintMB())) Mo)", area) }
            return result
        } catch {
            remember(area, "✗ \(name) : \(error.localizedDescription)")
            Diagnostics.error("\(name) : \(error.localizedDescription)", area)
            throw error
        }
    }

    // MARK: Dernières tâches (en mémoire, toujours) : journal de chaque IA dans les Réglages.

    private static let recentLock = NSLock()
    nonisolated(unsafe) private static var recentLines: [(area: String, line: String)] = []

    static func remember(_ area: String, _ line: String) {
        let time = Date().formatted(date: .abbreviated, time: .standard)
        recentLock.withLock {
            recentLines.append((area, "\(time)  \(line)"))
            if recentLines.count > 300 { recentLines.removeFirst(recentLines.count - 300) }
        }
    }

    /// Les plus récentes d'abord.
    static func recent(areas: Set<String>, limit: Int = 30) -> [String] {
        recentLock.withLock { Array(recentLines.filter { areas.contains($0.area) }.map(\.line).reversed().prefix(limit)) }
    }
}

/// Fenêtres ouvertes depuis la page de diagnostic.
struct DiagnosticsPresentations {
    var log = false
    var energy = false
    var readingExport = false
}

extension View {
    /// À poser sur le `Form`, jamais sur une `Section` : SwiftUI recopie un modificateur de `Section` sur chaque ligne,
    /// et cliquer sur « Voir le résumé » fermait toute la feuille Réglages sur Mac (essai du 04/11/2026).
    func diagnosticsPresentations(_ presented: Binding<DiagnosticsPresentations>) -> some View {
        sheet(isPresented: presented.log) { DiagnosticLogView() }
            .sheet(isPresented: presented.energy) { EnergySummaryView() }
            .sheet(isPresented: presented.readingExport) { OvisReadingExportView() }
    }
}

/// Réglages → Aide et informations → Aide au diagnostic.
struct DiagnosticsSection: View {
    @AppStorage(Diagnostics.enabledKey) private var enabled = false
    @AppStorage(EnergyMeter.enabledKey) private var energy = false
    @Binding var presented: DiagnosticsPresentations

    var body: some View {
        Section {
            Toggle("Mode diagnostic", isOn: $enabled)
            #if targetEnvironment(macCatalyst)
            // Mac : une feuille ouverte depuis la feuille Réglages les fermait toutes les deux (essai du 30/10/2026).
            NavigationLink { DiagnosticLogView(embedded: true) } label: {
                Label("Voir le journal", systemImage: "doc.text.magnifyingglass")
            }
            #else
            Button { presented.log = true } label: {
                Label("Voir le journal", systemImage: "doc.text.magnifyingglass")
            }
            #endif
            ShareLink(item: Diagnostics.file) { Label("Partager le journal", systemImage: "square.and.arrow.up") }
            Button("Effacer le journal", role: .destructive) { try? FileManager.default.removeItem(at: Diagnostics.file) }
        } header: {
            Text("Diagnostic")
        } footer: {
            Text("Note dans un journal ce que fait l'app (chargement des modèles, durées, mémoire, erreurs) pour aider à corriger un bug. Les erreurs sont toujours notées. Le journal reste sur l'iPad (app Fichiers → Kyōkasho → Diagnostics) ; partage-le quand on te le demande. Rien ne part tout seul.")
        }
        Section {
            Toggle("Relevé de batterie", isOn: $energy)
                .onChange(of: energy) { EnergyMeter.shared.setEnabled($0) }
            Button { presented.energy = true } label: { Label("Voir le résumé", systemImage: "battery.75") }
            Button("Effacer le relevé", role: .destructive) { EnergyFile.erase() }
        } header: {
            Text("Batterie")
        } footer: {
            Text("Note chaque minute le niveau de batterie, la chaleur et ce que fait l'app (lecture, IA, analyse), pour savoir quelle fonction consomme. Pour une mesure utile : luminosité fixe, iPad débranché, au moins 15 minutes par activité. Le fichier reste sur l'iPad (Fichiers → Kyōkasho → Diagnostics → energie.csv).")
        }
        Section {
            Button { presented.readingExport = true } label: {
                Label("Extraire les lectures OvisOCR2 d'un document", systemImage: "doc.plaintext")
            }
        } header: {
            Text("Lectures IA")
        } footer: {
            Text("Crée un seul fichier texte avec tout ce qu'OvisOCR2 a lu dans le document choisi. Le fichier contient le texte de ton livre : ne le publie pas.")
        }
    }
}

/// Choix du document, puis fichier texte de ses lectures OvisOCR2, à partager.
private struct OvisReadingExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var working: String?
    @State private var message: String?
    @State private var file: SharedFile?
    /// Pages lues par document, comptées à l'ouverture et hors du fil principal.
    @State private var readCounts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
                }
                Section {
                    ForEach(model.documents) { document in
                        let read = readCounts[document.id]
                        Button { export(document) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.title).foregroundStyle(read == 0 ? Atelier.textTertiary : Atelier.textPrimary)
                                    if let read {
                                        Text(read == 0 ? String(localized: "Aucune page lue : rien à extraire")
                                                       : String(localized: "\(read) / \(document.pageCount) pages lues : prêt à extraire"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if working == document.id { ProgressView() }
                            }
                        }
                        .disabled(working != nil || read == 0)
                    }
                } footer: {
                    Text("Touche un document : le fichier se prépare, puis la fenêtre de partage s'ouvre pour l'enregistrer ou l'envoyer.")
                }
            }
            .task {
                let ids = model.documents.map(\.id)
                let reader = ModelSpec.ovisocr2.id
                readCounts = await Task.detached(priority: .userInitiated) {
                    Dictionary(uniqueKeysWithValues: ids.map { ($0, DocumentAITextStore.pageCount(documentId: $0, reader: reader)) })
                }.value
            }
            .navigationTitle("Lectures OvisOCR2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .sheet(item: $file) { ActivityShareSheet(url: $0.url) }
    }

    private func export(_ document: LibraryDocument) {
        working = document.id
        message = nil
        let reader = ModelSpec.ovisocr2.id
        Task {
            // Hors du fil principal : un gros manuel, c'est des centaines de fichiers à lire.
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL?, Error> in
                let pages = (0..<document.pageCount).compactMap { page -> AIReadingExport.Page? in
                    DocumentAITextStore.read(documentId: document.id, reader: reader, page: page)
                        .map { AIReadingExport.Page(label: document.pageLabel(page), text: $0) }
                }
                guard !pages.isEmpty else { return .success(nil) }
                let text = AIReadingExport.text(title: document.title, reader: reader, totalPages: document.pageCount, pages: pages)
                return Result { try AIReadingExport.write(text, title: document.title, reader: reader) }
            }.value
            working = nil
            switch result {
            case .success(let url?): file = SharedFile(url: url)
            case .success(nil): message = String(localized: "OvisOCR2 n'a encore lu aucune page de « \(document.title) ».")
            case .failure(let error):
                message = String(localized: "Extraction impossible : \(error.localizedDescription)")
                Diagnostics.error("extraction des lectures : \(error.localizedDescription)", "diagnostic")
            }
        }
    }
}

/// La feuille possède son état : la première lecture se fait après sa présentation, pas dans le parent.
/// Instantané explicite, sans suivi périodique ni changement de la position de lecture.
struct DiagnosticLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tail: DiagnosticLogSnapshot.Tail?
    /// Affiché dans une navigation existante (Mac) : ni pile de navigation propre, ni bouton OK.
    var embedded = false

    /// Seule la fin du journal est lue, hors du fil principal, et affichée ligne par ligne dans une liste paresseuse :
    /// un journal de 2 Mo dans un seul `Text` mettait plus de 30 s à s'ouvrir (RET-045, #67).
    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    if let tail {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if tail.omittedBytes > 0 {
                                Text("Fin du journal seulement (\(tail.lines.count) dernières lignes). « Partager le journal » transmet le fichier complet.")
                                    .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
                            }
                            ForEach(tail.lines.indices, id: \.self) { index in
                                Text(tail.lines[index]).font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding()
                    } else {
                        ProgressView("Chargement du journal…").padding(.top, 40)
                    }
                }
                // Les lignes les plus récentes sont en bas : y aller dès le chargement.
                .onChange(of: tail) { tail in
                    if let last = tail?.lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Actualiser") { Task { await load() } }
                }
                if !embedded { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            }
            .task { await load() }
    }

    private func load() async {
        tail = await Task.detached(priority: .userInitiated) { Diagnostics.tail() }.value
    }
}
