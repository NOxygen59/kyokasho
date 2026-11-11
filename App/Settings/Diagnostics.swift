// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import MLX
import ReaderCore
import SwiftUI
import UIKit

/// Mode diagnostic : un journal texte (Documents/Diagnostics/journal.txt, visible dans l'app Fichiers) que
/// l'utilisateur peut partager pour aider à corriger un bug. Les erreurs sont toujours notées ; le détail
/// (chargement des modèles, durées, étapes de l'OCR) seulement si le mode est allumé.
enum Diagnostics {
    /// Niveau d'une ligne du journal : `info`, `alerte`, `erreur` (type commun avec le paquet, testé).
    typealias Level = DiagnosticLevel

    static let enabledKey = "diagnostics.enabled"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("journal.txt") }

    private static let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.diagnostics")
    private static let limit = DiagnosticFiles.journalRotationBytes

    /// Étape détaillée (seulement en mode diagnostic).
    static func log(_ message: @autoclosure () -> String, _ area: String = "app") {
        guard enabled else { return }
        write(message(), level: .info, area: area)
    }

    /// Erreur : toujours notée.
    static func error(_ message: String, _ area: String = "app") {
        write(message, level: .erreur, area: area)
    }

    /// Anomalie qui n'arrête rien (coupe du journal, mémoire haute, fichier trop gros) : toujours notée.
    static func alert(_ message: String, _ area: String = "app") {
        write(message, level: .alerte, area: area)
    }

    /// Une ligne : heure ISO, niveau, zone, message. Écrite tout de suite si `sync`
    /// (utilisé juste avant un arrêt de l'app).
    static func write(_ message: String, level: Level = .info, area: String = "app", sync: Bool = false) {
        let now = Date()
        let text = DiagnosticFiles.journalLine(level, area: area, message: message, at: now) + "\n"
        let work = {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = fileSize(limitPath: file), size > limit {
                // Trop gros : on garde la seconde moitié. La coupe est écrite **en tête** du fichier (date, taille
                // coupée) : elle ne peut plus passer inaperçue (demande du 10/11/2026).
                if let data = try? Data(contentsOf: file) {
                    let kept = data.suffix(limit / 2)
                    let note = DiagnosticFiles.journalLine(.alerte, area: "journal",
                                                           message: "Coupe du journal : fichier de \(size) octets, on garde la fin (\(kept.count) octets)",
                                                           at: now)
                    try? (Data((note + "\n").utf8) + kept).write(to: file)
                }
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

    /// Taille d'un fichier en octets (`nil` s'il n'existe pas).
    private static func fileSize(limitPath url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    /// Tailles lues pour la bannière de taille : journal et relevé de batterie.
    static func diagnosticSizes() -> (journal: Int, energy: Int) {
        (fileSize(limitPath: file) ?? 0, fileSize(limitPath: EnergyFile.url) ?? 0)
    }

    /// Les deux fichiers de diagnostic qui existent, journal d'abord : un seul geste de partage (demande du 10/11/2026).
    static func filesForSharing() -> [URL] {
        [file, EnergyFile.url].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Les fichiers ont changé (effacement, coupe) : la bannière de taille se remet à jour.
    static func postSizeChange() {
        NotificationCenter.default.post(name: .diagnosticFilesChanged, object: nil)
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

    /// Au lancement : en-tête (date, version, appareil, iOS, batterie, luminosité, réglages qui consomment) et
    /// gestionnaire d'erreurs MLX global, qui note le **message avant** l'arrêt (sinon le rapport de plantage d'iOS
    /// ne le contient pas). L'en-tête est réécrit à chaque lancement (demande du 10/11/2026) : c'est lui qui dit dans
    /// quelles conditions le journal a été produit.
    static func start() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let memory = ProcessInfo.processInfo.physicalMemory / 1_048_576
        let device = UIDevice.current
        let battery = batteryPercent(device)
        let brightness = Int((UIScreen.main.brightness * 100).rounded())
        write(launchHeader(version: version, model: device.model, system: device.systemVersion, memoryMB: memory,
                           battery: battery, brightness: brightness),
              level: .info, area: "app")
        setErrorHandler({ message, _ in
            let text = message.map { String(cString: $0) } ?? "(sans message)"
            Diagnostics.write("ERREUR FATALE : \(text) · mémoire de l'app \(Int(Diagnostics.footprintMB())) Mo",
                              level: .erreur, area: "mlx", sync: true)
            fatalError("MLX : \(text)")
        })
    }

    /// Ligne d'en-tête d'un lancement, sans titre de document ni texte de page : le journal partageable ne doit
    /// contenir que des conditions de mesure et des réglages.
    private static func launchHeader(version: String, model: String, system: String, memoryMB: UInt64,
                                     battery: Double, brightness: Int) -> String {
        let defaults = UserDefaults.standard
        // Lecture IA automatique : même valeur par défaut que `DocumentScan` (« oui » tant que rien n'est réglé).
        let autoScan = defaults.object(forKey: "scan.auto") as? Bool ?? true
        // Relecture GLM-OCR : même valeur par défaut que `ReaderController.aiRereadKey`.
        let reread = defaults.object(forKey: "ocr.aiReread") as? Bool ?? true
        let furigana = defaults.bool(forKey: "reader.furigana")
        func yesNo(_ on: Bool) -> String { on ? String(localized: "oui") : String(localized: "non") }
        let level = battery < 0 ? String(localized: "inconnue") : String(format: "%.0f", battery * 100) + " %"
        let state = enabled ? String(localized: "activé") : String(localized: "désactivé")
        return "=== Lancement Kyōkasho \(version) · \(model) iOS \(system) · mémoire \(memoryMB) Mo · batterie \(level)"
            + " · luminosité \(brightness) % · lecture IA auto \(yesNo(autoScan)) · relecture GLM-OCR \(yesNo(reread))"
            + " · furigana \(yesNo(furigana)) · diagnostic \(state)"
    }

    /// Niveau de batterie (0…1), -1 si iOS ne le donne pas. La surveillance n'est allumée que le temps de la mesure
    /// quand le relevé de batterie est éteint : elle coûte des notifications périodiques.
    private static func batteryPercent(_ device: UIDevice) -> Double {
        let wasEnabled = device.isBatteryMonitoringEnabled
        if !wasEnabled { device.isBatteryMonitoringEnabled = true }
        let level = Double(device.batteryLevel)
        if !wasEnabled { device.isBatteryMonitoringEnabled = UserDefaults.standard.bool(forKey: EnergyMeter.enabledKey) }
        return level
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

/// L'utilisateur vient d'effacer un fichier de diagnostic : la bannière de taille se remet à jour sans attendre.
extension Notification.Name {
    static let diagnosticFilesChanged = Notification.Name("fr.noxygen59.kyokasho.diagnosticFilesChanged")
}

/// Réglages → Aide et informations → Aide au diagnostic.
struct DiagnosticsSection: View {
    @AppStorage(Diagnostics.enabledKey) private var enabled = false
    @AppStorage(EnergyMeter.enabledKey) private var energy = false
    @State private var showLog = false
    @State private var showEnergy = false
    @State private var showReadingExport = false

    var body: some View {
        Section {
            Toggle("Mode diagnostic", isOn: $enabled)
            Button { showLog = true } label: {
                Label("Voir le journal", systemImage: "doc.text.magnifyingglass")
            }
            ShareLink(item: Diagnostics.file) { Label("Partager le journal", systemImage: "square.and.arrow.up") }
            // Un seul geste pour les deux fichiers (demande du 10/11/2026) : ils s'expliquent l'un par l'autre.
            ShareLink(items: Diagnostics.filesForSharing()) {
                Label("Partager le relevé et le journal", systemImage: "square.and.arrow.up.on.square")
            }
            Button("Effacer le journal", role: .destructive) {
                try? FileManager.default.removeItem(at: Diagnostics.file)
                Diagnostics.postSizeChange()
            }
        } header: {
            Text("Diagnostic")
        } footer: {
            #if targetEnvironment(macCatalyst)
            Text("Note dans un journal ce que fait l'app (chargement des modèles, durées, mémoire, erreurs) pour aider à corriger un bug. Les erreurs sont toujours notées. Le journal reste sur ce MacBook ; partage-le quand on te le demande. Rien ne part tout seul.")
            #else
            Text("Note dans un journal ce que fait l'app (chargement des modèles, durées, mémoire, erreurs) pour aider à corriger un bug. Les erreurs sont toujours notées. Le journal reste sur l'iPad (app Fichiers → Kyōkasho → Diagnostics) ; partage-le quand on te le demande. Rien ne part tout seul.")
            #endif
        }
        .sheet(isPresented: $showLog) { DiagnosticLogView() }
        Section {
            Toggle("Relevé de batterie", isOn: $energy)
                .onChange(of: energy) { EnergyMeter.shared.setEnabled($0) }
            Button { showEnergy = true } label: { Label("Voir le résumé", systemImage: "battery.75") }
            Button("Effacer le relevé", role: .destructive) {
                EnergyFile.erase()
                Diagnostics.postSizeChange()
            }
        } header: {
            Text("Batterie")
        } footer: {
            #if targetEnvironment(macCatalyst)
            Text("Note chaque minute le niveau de batterie, la chaleur et ce que fait l'app (lecture, IA, analyse), pour savoir quelle fonction consomme. Pour une mesure utile : luminosité fixe, MacBook débranché, au moins 15 minutes par activité. Le fichier reste sur ce MacBook.")
            #else
            Text("Note chaque minute le niveau de batterie, la chaleur et ce que fait l'app (lecture, IA, analyse), pour savoir quelle fonction consomme. Pour une mesure utile : luminosité fixe, iPad débranché, au moins 15 minutes par activité. Le fichier reste sur l'iPad (Fichiers → Kyōkasho → Diagnostics → energie.csv).")
            #endif
        }
        .sheet(isPresented: $showEnergy) { EnergySummaryView() }
        Section {
            Button { showReadingExport = true } label: {
                Label("Extraire les lectures OvisOCR2 d'un document", systemImage: "doc.plaintext")
            }
        } header: {
            Text("Lectures IA")
        } footer: {
            Text("Crée un seul fichier texte avec tout ce qu'OvisOCR2 a lu dans le document choisi. Le fichier contient le texte de ton livre : ne le publie pas.")
        }
        .sheet(isPresented: $showReadingExport) { OvisReadingExportView() }
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

    /// Seule la fin du journal est lue, hors du fil principal, et affichée ligne par ligne dans une liste paresseuse :
    /// un journal de 2 Mo dans un seul `Text` mettait plus de 30 s à s'ouvrir (RET-045, #67).
    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func load() async {
        tail = await Task.detached(priority: .userInitiated) { Diagnostics.tail() }.value
    }
}
