// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import MLX
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

    /// Au lancement : en-tête (version, appareil, mémoire) et gestionnaire d'erreurs MLX global, qui note le
    /// message **avant** l'arrêt (sinon le rapport de plantage d'iOS ne le contient pas).
    static func start() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let memory = ProcessInfo.processInfo.physicalMemory / 1_048_576
        write("=== Lancement Kyōkasho \(version) · \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion) · mémoire \(memory) Mo · diagnostic \(enabled ? "activé" : "désactivé")")
        setErrorHandler({ message, _ in
            let text = message.map { String(cString: $0) } ?? "(sans message)"
            Diagnostics.write("[mlx] ERREUR FATALE : \(text) · mémoire de l'app \(Int(Diagnostics.footprintMB())) Mo", sync: true)
            fatalError("MLX : \(text)")
        })
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

/// Réglages → Outils → Diagnostic.
struct DiagnosticsSection: View {
    @AppStorage(Diagnostics.enabledKey) private var enabled = false
    @State private var text = ""
    @State private var showLog = false

    var body: some View {
        Section {
            Toggle("Mode diagnostic", isOn: $enabled)
            Button { text = (try? String(contentsOf: Diagnostics.file)) ?? "Journal vide."; showLog = true } label: {
                Label("Voir le journal", systemImage: "doc.text.magnifyingglass")
            }
            ShareLink(item: Diagnostics.file) { Label("Partager le journal", systemImage: "square.and.arrow.up") }
            Button("Effacer le journal", role: .destructive) { try? FileManager.default.removeItem(at: Diagnostics.file) }
        } header: {
            Text("Diagnostic")
        } footer: {
            Text("Note dans un journal ce que fait l'app (chargement des modèles, durées, mémoire, erreurs) pour aider à corriger un bug. Les erreurs sont toujours notées. Le journal reste sur l'iPad (app Fichiers → Kyōkasho → Diagnostics) ; partage-le quand on te le demande. Rien ne part tout seul.")
        }
        .sheet(isPresented: $showLog) {
            NavigationStack {
                ScrollView { Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding() }
                    .navigationTitle("Journal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { showLog = false } } }
            }
        }
    }
}
