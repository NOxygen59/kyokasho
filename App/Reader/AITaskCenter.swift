// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import SwiftUI

/// Toutes les tâches IA lancées depuis le lecteur (relecture GLM-OCR, vérification et mise en page OvisOCR2,
/// traduction Qwen3-VL). Elles appartiennent à l'app, pas aux vues : changer de page, de vue ou fermer le lecteur
/// ne les arrête pas, et leur résultat est écrit dans le cache même si la page n'est plus affichée. Seul
/// « Arrêter » (pastille, double confirmation) les annule.
@MainActor
final class AITaskCenter: ObservableObject {
    static let shared = AITaskCenter()

    struct Job: Identifiable, Equatable {
        let id = UUID()
        /// Une seule tâche par clé (ex. `layout|<document>|<page>`) : relancer la même ne fait rien.
        let key: String
        let title: String
        let started = Date()
        /// Modèle et action affichés dans les pastilles, sans déduire le rôle du titre.
        let modelId: String?
        let activity: String?
        var progress: (done: Int, total: Int)?
        /// Journal en direct (« Voir le détail »), 200 lignes au plus.
        var log: [String] = []

        init(key: String, title: String, modelId: String?, activity: String?) {
            self.key = key
            self.title = title
            self.modelId = modelId
            self.activity = activity
        }

        static func == (a: Job, b: Job) -> Bool {
            a.id == b.id && a.progress?.done == b.progress?.done && a.progress?.total == b.progress?.total
                && a.log.count == b.log.count && a.log.last == b.log.last
        }
    }

    @Published private(set) var jobs: [Job] = []
    /// Dernière erreur par clé (affichée par la vue concernée, effacée au relancement).
    @Published private(set) var errors: [String: String] = [:]
    /// +1 à chaque tâche finie : les vues qui affichent un résultat (fichier, cache) se rechargent.
    @Published private(set) var finished = 0
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func isRunning(_ key: String) -> Bool { jobs.contains { $0.key == key } }
    func isRunning(prefix: String) -> Bool { jobs.contains { $0.key.hasPrefix(prefix) } }

    /// Lance `work` sous `key` (rien si une tâche de même clé tourne déjà). Une erreur levée est gardée dans `errors`.
    @discardableResult
    func run(_ key: String, title: String, modelId: String? = nil, activity: String? = nil,
             _ work: @escaping @MainActor (_ id: UUID) async throws -> Void) -> Bool {
        guard !isRunning(key) else { return false }
        let job = Job(key: key, title: title, modelId: modelId, activity: activity)
        jobs.append(job)
        errors[key] = nil
        tasks[job.id] = Task { [weak self] in
            do {
                try await work(job.id)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.errors[key] = error.localizedDescription }
            }
            self?.jobs.removeAll { $0.id == job.id }
            self?.tasks[job.id] = nil
            self?.finished += 1
        }
        return true
    }

    func setProgress(_ id: UUID, done: Int, total: Int) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].progress = (done, total)
    }

    func log(_ id: UUID, _ line: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        let time = Date().formatted(date: .omitted, time: .standard)
        jobs[i].log.append("\(time)  \(line)")
        if jobs[i].log.count > 200 { jobs[i].log.removeFirst(jobs[i].log.count - 200) }
    }

    /// Arrêt demandé par l'utilisateur (la génération s'arrête au jeton suivant).
    func cancel(_ id: UUID) { tasks[id]?.cancel() }

    func cancel(key: String) { jobs.filter { $0.key == key }.forEach { cancel($0.id) } }

    /// Remplacement par une version plus récente (pas un arrêt de l'utilisateur) : la tâche quitte la liste tout de
    /// suite, son résultat sera jeté.
    func cancel(prefix: String) {
        for job in jobs where job.key.hasPrefix(prefix) {
            cancel(job.id)
            jobs.removeAll { $0.id == job.id }
        }
    }

    func cancelAll() { tasks.values.forEach { $0.cancel() } }
}

/// Lit l'état MLX pendant que les pastilles sont visibles. Une seule lecture périodique suffit pour le lecteur et
/// la bibliothèque ; elle s'arrête lorsque les vues disparaissent ou que l'option est désactivée.
@MainActor
private final class AIModelBadgeMonitor: ObservableObject {
    static let shared = AIModelBadgeMonitor()

    @Published private(set) var status: AIModelStatus?
    private var observers = 0
    private var polling: Task<Void, Never>?

    func start() {
        observers += 1
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let next = await GLMOCREngine.status()
                guard let self, !Task.isCancelled else { break }
                if self.status?.loaded != next.loaded || self.status?.loading != next.loading
                    || self.status?.inUse != next.inUse {
                    self.status = next
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    func stop() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        polling?.cancel()
        polling = nil
        status = nil
    }
}

/// Pastilles des modèles MLX, dans le lecteur et la bibliothèque. Toucher ouvre les tâches ; « Arrêter » demande
/// deux confirmations (une tâche IA coûte des minutes).
struct AITaskPill: View {
    static let visibleKey = "ai.showActivityBadges"

    @ObservedObject private var center = AITaskCenter.shared
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @ObservedObject private var monitor = AIModelBadgeMonitor.shared
    @AppStorage(AITaskPill.visibleKey) private var visible = true
    @State private var showList = false
    /// Tâches dont le journal est déplié (« Voir le détail »).
    @State private var expanded: Set<UUID> = []
    /// Tâche à arrêter (`nil` + `stopAll` = toutes) : 1re puis 2e confirmation.
    @State private var stopping: AITaskCenter.Job?
    @State private var stopAll = false
    @State private var confirm1 = false
    @State private var confirm2 = false

    var body: some View {
        // Conteneur permanent : la dernière tâche peut finir pendant la confirmation.
        HStack(spacing: 6) {
            if visible {
                ForEach(badges) { badge in
                    Button { showList = true } label: {
                        HStack(spacing: 5) {
                            Circle().fill(badge.active ? Atelier.Tint.ai : Atelier.textSecondary)
                                .frame(width: 5, height: 5)
                            Text("\(badge.name) · \(badge.activity)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Atelier.textPrimary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .atelierPanel(radius: 14)
                        .opacity(badge.active ? 0.82 : 0.48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(badge.name), \(badge.activity)")
                }
            }
        }
        .onAppear { if visible { monitor.start() } }
        .onDisappear { if visible { monitor.stop() } }
        .onChange(of: visible) { enabled in
            if enabled { monitor.start() } else { monitor.stop() }
        }
        .popover(isPresented: $showList) { list }
        .alert(stopTitle, isPresented: $confirm1) {
            Button("Continuer la tâche", role: .cancel) {}
            Button("Arrêter", role: .destructive) {
                // Laisser la 1re alerte se fermer avant la 2e.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirm2 = true }
            }
        } message: {
            Text("Le travail déjà fait sur la page en cours sera perdu.")
        }
        .alert("Vraiment arrêter ?", isPresented: $confirm2) {
            Button("Non, continuer", role: .cancel) {}
            Button("Oui, arrêter", role: .destructive) {
                if stopAll { center.cancelAll() } else if let stopping { center.cancel(stopping.id) }
                stopping = nil
                stopAll = false
            }
        }
    }

    private var stopTitle: String {
        stopAll ? "Arrêter toutes les tâches IA ?" : "Arrêter « \(stopping?.title ?? "") » ?"
    }

    private struct Badge: Identifiable {
        let id: String
        let name: String
        let activity: String
        let active: Bool
    }

    private var badges: [Badge] {
        [
            (ModelSpec.ovisocr2, "OvisOCR2"),
            (ModelSpec.glmocr, "GLM-OCR"),
            (ModelSpec.qwen3vl4b, "Qwen3-VL"),
            (ModelSpec.qwen35chat4b, "Qwen3.5")
        ].compactMap { spec, name in
            let url = ModelStore.shared.directory(spec)
            let jobs = center.jobs.filter { $0.modelId == spec.id }
            let phase = analysis.progress?.phase ?? ""
            let analysisActivity: String? = switch spec.id {
            case ModelSpec.ovisocr2.id where phase == "Lecture OvisOCR2": "analyse"
            case ModelSpec.glmocr.id where phase == "Lecture GLM-OCR": "analyse"
            case ModelSpec.qwen3vl4b.id where phase == "Lecture Qwen3-VL-4B": "analyse"
            case ModelSpec.qwen3vl4b.id where phase == "Traduction (Qwen3-VL)": "traduction"
            default: nil
            }
            if monitor.status?.loading == url { return Badge(id: spec.id, name: name, activity: "chargement", active: true) }
            if monitor.status?.loaded == url, monitor.status?.inUse == true {
                let chatActive = spec.id == ModelSpec.qwen3vl4b.id || spec.id == ModelSpec.qwen35chat4b.id
                let activity = jobs.count > 1 ? "\(jobs.count) tâches" : jobs.first?.activity ?? analysisActivity
                    ?? (chatActive ? "chat" : "utilisée")
                return Badge(id: spec.id, name: name, activity: activity, active: true)
            }
            if !jobs.isEmpty || analysisActivity != nil {
                return Badge(id: spec.id, name: name, activity: "en attente", active: false)
            }
            if monitor.status?.loaded == url { return Badge(id: spec.id, name: name, activity: "chargée", active: false) }
            return nil
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activité des IA").font(.headline)
            if center.jobs.isEmpty {
                Text("Aucune tâche IA en cours.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let loaded = badges.first(where: { $0.activity == "chargée" }) {
                Text("\(loaded.name) reste brièvement en mémoire pour une prochaine demande.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(center.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).font(.subheadline.weight(.semibold))
                            Text(detail(job)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Arrêter", role: .destructive) { ask(job) }
                    }
                    if let p = job.progress, p.total > 0 {
                        ProgressView(value: Double(p.done), total: Double(p.total)) {
                            EmptyView()
                        } currentValueLabel: {
                            Text("\(p.done * 100 / p.total) %").font(.caption2.monospacedDigit())
                        }
                    }
                    if !job.log.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(job.id) },
                                                            set: { if $0 { expanded.insert(job.id) } else { expanded.remove(job.id) } })) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(job.log.enumerated().reversed()), id: \.offset) { _, line in
                                        Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxHeight: 180)
                        } label: {
                            Text("Voir le détail").font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            if center.jobs.count > 1 {
                Button("Tout arrêter", role: .destructive) { ask(nil) }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(minWidth: 360)
    }

    private func detail(_ job: AITaskCenter.Job) -> String {
        let minutes = Int(Date().timeIntervalSince(job.started) / 60)
        var text = minutes < 1 ? "Démarrée il y a moins d'une minute" : "Démarrée il y a \(minutes) min"
        if let p = job.progress { text += " · \(p.done) sur \(p.total)" }
        return text
    }

    private func ask(_ job: AITaskCenter.Job?) {
        stopping = job
        stopAll = job == nil
        showList = false
        // Popover fermé avant l'alerte (sinon iOS 16 n'affiche rien).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirm1 = true }
    }
}
