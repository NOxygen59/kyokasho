// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import OCRKit
import MLX
import DiagnosticKit
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
    /// Version du format du journal déjà en place (DEC-07) et sel des références de documents (`DiagnosticRef`).
    private static let formatKey = "diagnostics.formatVersion"
    private static let saltKey = "diagnostics.refSalt"

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true)
    }
    // Noms écrits en clair : la garde de l'inventaire des données (DATA-02) les lit ; un test vérifie qu'ils sont
    // ceux de `DiagnosticJournalPolicy` (`tests/test_diagnostics_privacy.py`).
    static var file: URL { folder.appendingPathComponent("journal.txt") }
    /// Journal précédent, gardé à la rotation (DEC-06 B).
    static var previousFile: URL { folder.appendingPathComponent("journal.1.txt") }
    /// Journal écrit avant PLAN-DIAG-001, mis à l'écart (DEC-07 A) : jamais partagé, effacé avec le reste.
    static var quarantinedFile: URL { folder.appendingPathComponent("journal-avant-diagnostics.txt") }
    /// Relevé de batterie de l'ancien format, mis à l'écart comme l'ancien journal : jamais partagé, effacé avec le relevé.
    static var quarantinedEnergyFile: URL { folder.appendingPathComponent("energie-avant-diagnostics.csv") }

    private static let queue = DispatchQueue(label: "fr.noxygen59.kyokasho.diagnostics")
    /// Lignes en attente d'écriture et lignes perdues faute de place (file bornée, PLAN-DIAG-001 E1).
    private static let pendingLock = NSLock()
    nonisolated(unsafe) private static var pending = 0
    nonisolated(unsafe) private static var dropped = 0

    /// Étape détaillée (seulement en mode diagnostic).
    static func log(_ message: @autoclosure () -> String, _ area: String = "app") {
        guard enabled else { return }
        write(message(), level: .info, area: area)
    }

    /// Relevé du moniteur CPU et des fils (AV-DIAG-001, AV-03) : zone fermée, `op` du relevé et étape, comme les
    /// événements ; les mesures viennent de `DiagnosticCPULog` (nombres et noms de fils filtrés).
    static func logCPU(_ measures: String, op: DiagnosticOperation, step: StaticString, zone: DiagnosticZone = .cpu) {
        guard enabled else { return }
        enqueue(DiagnosticLine.monitor(.info, zone: zone, op: op, step: step, measures: measures, at: Date()), sync: false,
                diagnosticOnly: true)
    }

    /// Erreur : toujours notée. Le message est un texte du code : jamais un titre, un chemin ni le message d'une
    /// erreur système (`describe(_:)` à la place) ; garde `tests/test_diagnostics_privacy.py`.
    static func error(_ message: String, _ area: String = "app") {
        write(message, level: .erreur, area: area)
    }

    /// Anomalie qui n'arrête rien (coupe du journal, mémoire haute, fichier trop gros) : toujours notée.
    static func alert(_ message: String, _ area: String = "app") {
        write(message, level: .alerte, area: area)
    }

    /// Cause d'une erreur pour le journal : domaine et numéro seulement (DEC-01), jamais `localizedDescription`,
    /// qui peut contenir un chemin ou un nom de fichier.
    static func describe(_ error: Error) -> String { DiagnosticCause.from(error).text }

    /// Référence courte et salée d'un document pour le journal, à la place de son titre (DEC-01).
    static func ref(_ documentId: String) -> String { DiagnosticCenter.shared.ref(documentId).text }

    /// Une ligne : heure ISO, niveau, zone, message. Écrite tout de suite si `sync`
    /// (utilisé juste avant un arrêt de l'app).
    static func write(_ message: String, level: Level = .info, area: String = "app", sync: Bool = false) {
        write(message, level: level, area: area, sync: sync, diagnosticOnly: false)
    }

    private static func write(_ message: String, level: Level = .info, area: String, sync: Bool = false, diagnosticOnly: Bool) {
        // Zone fermée (contrat commun avec les événements typés) ; une ancienne zone inconnue devient `app`.
        let zone = DiagnosticZone.legacy(area)
        enqueue(DiagnosticLine.legacy(level, area: zone.rawValue, message: message, at: Date()), sync: sync,
                diagnosticOnly: diagnosticOnly)
    }

    /// Récepteur des événements typés (app et paquets) : même file, même fichier que les anciennes lignes.
    private static func receive(_ event: DiagnosticEvent) {
        enqueue(DiagnosticLine.event(event, at: Date()), sync: false, diagnosticOnly: false)
    }

    /// File d'écriture bornée : au-delà de `maxPendingLines`, la ligne est perdue et comptée ; la ligne suivante
    /// écrite le signale. Rien ici n'appelle le journal : pas de récursion.
    private static func enqueue(_ line: String, sync: Bool, diagnosticOnly: Bool) {
        let accepted: Bool = pendingLock.withLock {
            guard sync || pending < DiagnosticJournalPolicy.maxPendingLines else { dropped += 1; return false }
            pending += 1
            return true
        }
        guard accepted else { return }
        let work = {
            let lost: Int = pendingLock.withLock { pending -= 1; defer { dropped = 0 }; return dropped }
            guard !diagnosticOnly || enabled else { return }
            var text = line + "\n"
            let reentrant = DiagnosticCenter.shared.takeReentrantDrops()
            if lost + reentrant > 0 {
                text = DiagnosticLine.legacy(.alerte, area: DiagnosticZone.journal.rawValue,
                                             message: "Lignes perdues : \(lost) (file pleine), \(reentrant) (émises par le journal)",
                                             at: Date()) + "\n" + text
            }
            append(text)
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// Écrit en fin de journal ; au-delà de 5 Mo, le journal devient `journal.1.txt` (DEC-06 B). Sur la file.
    private static func append(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let size = fileSize(limitPath: file), DiagnosticJournalPolicy.shouldRotate(currentBytes: size) {
            // Le précédent n'est remplacé qu'au moment du déplacement réussi (remplacement atomique) ; l'en-tête de
            // rotation n'est écrit que si le journal a bien changé de nom (revue R2 Codex, B-ROTATION). En cas
            // d'échec, on continue d'ajouter au journal actuel.
            let rotated: Bool
            if fm.fileExists(atPath: previousFile.path) {
                rotated = (try? fm.replaceItemAt(previousFile, withItemAt: file)) != nil
            } else {
                rotated = (try? fm.moveItem(at: file, to: previousFile)) != nil
            }
            if rotated && !fm.fileExists(atPath: file.path) {
                let note = DiagnosticLine.legacy(.alerte, area: DiagnosticZone.journal.rawValue,
                                                 message: "Rotation du journal : l'ancien (\(size) octets) est dans \(DiagnosticJournalPolicy.previousName)",
                                                 at: Date())
                try? Data((note + "\n").utf8).write(to: file)
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

    /// DEC-07 A : un journal écrit avant ce format (il peut contenir des titres et des chemins) est renommé, exclu
    /// du partage et effacé avec le reste. Une seule fois, au premier lancement de la nouvelle version.
    private static func quarantineOldJournalIfNeeded() {
        let defaults = UserDefaults.standard
        let fm = FileManager.default
        queue.sync {
            let stored = defaults.integer(forKey: formatKey)
            guard stored < DiagnosticJournalPolicy.formatVersion else { return }
            // Journal et relevé de batterie de l'ancien format (titres, chemins, préfixes d'empreinte, noms de modèles
            // importés) : mis à l'écart. Le format n'est marqué migré que si **les deux** ont réussi ; sinon on
            // réessaie au prochain lancement (revue R2 Codex, B-QUARANTAINE et B-CSV).
            let moved = [(file, quarantinedFile), (EnergyFile.url, quarantinedEnergyFile)].allSatisfy { source, target in
                guard fm.fileExists(atPath: source.path) else { return true }
                if fm.fileExists(atPath: target.path) {
                    return (try? fm.replaceItemAt(target, withItemAt: source)) != nil && !fm.fileExists(atPath: source.path)
                }
                return (try? fm.moveItem(at: source, to: target)) != nil
            }
            if moved { defaults.set(DiagnosticJournalPolicy.formatVersion, forKey: formatKey) }
        }
    }

    /// Sel des références de documents, tiré une fois par installation.
    private static func referenceSalt() -> UInt64 {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: saltKey), let value = UInt64(stored) { return value }
        let value = UInt64.random(in: 1...UInt64.max)
        defaults.set(String(value), forKey: saltKey)
        return value
    }

    /// Mode diagnostic allumé ou éteint : les événements `info` des paquets suivent.
    static func updateDetail() { DiagnosticCenter.shared.setDetailed(enabled) }

    /// Taille d'un fichier en octets (`nil` s'il n'existe pas).
    private static func fileSize(limitPath url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    /// Tailles lues pour la bannière de taille : journal et relevé de batterie.
    static func diagnosticSizes() -> (journal: Int, energy: Int) {
        let journal = [file, previousFile, quarantinedFile].reduce(0) { $0 + (fileSize(limitPath: $1) ?? 0) }
        return (journal, (fileSize(limitPath: EnergyFile.url) ?? 0) + (fileSize(limitPath: quarantinedEnergyFile) ?? 0))
    }

    /// Les fichiers de diagnostic qui existent, journal d'abord : un seul geste de partage (demande du 10/11/2026).
    /// Le journal mis à l'écart (DEC-07) n'en fait jamais partie.
    static func filesForSharing() -> [URL] {
        [file, previousFile, EnergyFile.url].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// « Effacer le journal » : toutes les générations, ancien journal mis à l'écart compris (DEC-06, DEC-07).
    static func eraseJournal() {
        queue.sync {
            for url in [file, previousFile, quarantinedFile] { try? FileManager.default.removeItem(at: url) }
        }
        postSizeChange()
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
        // Avant toute ligne : ancien journal mis à l'écart, puis récepteur des paquets branché (une seule fois, avant
        // la restauration de la bibliothèque appelée juste après par `KyokashoApp`).
        quarantineOldJournalIfNeeded()
        DiagnosticCenter.shared.install(sink: { receive($0) }, salt: referenceSalt())
        updateDetail()
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
            // Le message natif peut contenir un chemin ou un nom de modèle : le journal n'en garde que la longueur
            // (revue R2 Codex, B-MLX). Le rapport de plantage d'iOS garde le message complet via `fatalError`.
            Diagnostics.write("ERREUR FATALE MLX (message natif de \(text.count) caractères) · mémoire de l'app \(Int(Diagnostics.footprintMB())) Mo",
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
            remember(area, "✗ \(name) : \(describe(error))")
            Diagnostics.error("\(name) : \(describe(error))", area)
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
                .onChange(of: enabled) { _ in
                    DiagnosticCPU.updateActivation()
                    Diagnostics.updateDetail()
                }
            Button { showLog = true } label: {
                Label("Voir le journal", systemImage: "doc.text.magnifyingglass")
            }
            ShareLink(item: Diagnostics.file) { Label("Partager le journal", systemImage: "square.and.arrow.up") }
            // Un seul geste pour les deux fichiers (demande du 10/11/2026) : ils s'expliquent l'un par l'autre.
            ShareLink(items: Diagnostics.filesForSharing()) {
                Label("Partager le relevé et le journal", systemImage: "square.and.arrow.up.on.square")
            }
            Button("Effacer le journal", role: .destructive) { Diagnostics.eraseJournal() }
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
                Diagnostics.error("extraction des lectures : \(Diagnostics.describe(error))", "diagnostic")
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
