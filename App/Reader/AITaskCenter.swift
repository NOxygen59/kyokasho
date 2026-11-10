// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
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
        /// Journal en direct (« Voir le détail »), 200 lignes au plus, recopié dans le journal de diagnostic (zone `ia`).
        var log: [String] = []
        /// Fin de la tâche (« Terminées récemment ») : `nil` tant qu'elle tourne.
        var outcome: String?

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
    /// Tâches finies, la plus récente en tête (15 au plus), pour voir après coup ce qui s'est passé (#47).
    @Published private(set) var recent: [Job] = []
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
        // Pas de nouvelle tâche IA pendant une sauvegarde complète (#51) : ses écritures viseraient la copie en cours.
        guard !isRunning(key), !PageShift.blocksAI(jobKey: key), !LibraryBackupService.inProgress else { return false }
        let job = Job(key: key, title: title, modelId: modelId, activity: activity)
        jobs.append(job)
        errors[key] = nil
        // Début et fin écrits pour toutes les tâches, même celles qui ne journalisent rien d'autre (#47).
        log(job.id, String(localized: "Démarrée") + (modelId.map { " avec \(Self.modelName($0))" } ?? "")
            + (activity.map { " : \(AIActivityText.explain($0))" } ?? ""))
        tasks[job.id] = Task { [weak self] in
            var failure: String?
            var cancelled = false
            do {
                try await work(job.id)
            } catch is CancellationError {
                cancelled = true
            } catch {
                if Task.isCancelled { cancelled = true } else {
                    failure = error.localizedDescription
                    self?.errors[key] = failure
                }
            }
            if Task.isCancelled { cancelled = true }
            self?.finish(job.id, AIActivityText.outcome(seconds: Date().timeIntervalSince(job.started),
                                                         cancelled: cancelled, error: failure))
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
        Diagnostics.log("\(jobs[i].title) · \(line)", "ia")
    }

    /// Retire la tâche de la liste en cours et la garde dans `recent`, avec sa fin écrite au journal.
    private func finish(_ id: UUID, _ outcome: String) {
        log(id, outcome)
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        var job = jobs.remove(at: i)
        job.outcome = outcome
        recent.insert(job, at: 0)
        if recent.count > 15 { recent.removeLast(recent.count - 15) }
    }

    /// Nom affiché d'un modèle (pastilles, journal).
    static func modelName(_ id: String) -> String {
        switch id {
        case ModelSpec.ovisocr2.id: return "OvisOCR2"
        case ModelSpec.glmocr.id: return "GLM-OCR"
        case ModelSpec.qwen3vl4b.id: return "Qwen3-VL"
        case ModelSpec.qwen35chat4b.id: return "Qwen3.5"
        default: return id
        }
    }

    /// Arrêt demandé par l'utilisateur (la génération s'arrête au jeton suivant).
    func cancel(_ id: UUID) { tasks[id]?.cancel() }

    func cancel(key: String) { jobs.filter { $0.key == key }.forEach { cancel($0.id) } }

    /// Toutes les tâches IA d'un document (clé `…|<document>|…`), la suppression avant tout :
    /// leurs écritures tardives (OCR, lectures IA) ne doivent pas s'installer après l'effacement
    /// de ses PDF et bases. Même prédicat de clé que `PageShift.blocksAI(jobKey:)`.
    func cancel(documentId: String) {
        for job in jobs where job.key.split(separator: "|").contains(documentId) { cancel(job.id) }
    }

    /// Remplacement par une version plus récente (pas un arrêt de l'utilisateur) : la tâche quitte la liste tout de
    /// suite, son résultat sera jeté.
    func cancel(prefix: String) {
        for job in jobs where job.key.hasPrefix(prefix) {
            cancel(job.id)
            finish(job.id, String(localized: "Remplacée par une demande plus récente"))
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
    @State private var showJournal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tâches dont le journal est déplié (« Voir le détail »).
    @State private var expanded: Set<UUID> = []
    /// Tâche à arrêter (`nil` + `stopAll` = toutes) : 1re puis 2e confirmation.
    @State private var stopping: AITaskCenter.Job?
    @State private var stopAll = false
    @State private var confirm1 = false
    @State private var confirm2 = false
    @State private var confirmAnalysisStop = false

    var body: some View {
        // Conteneur permanent : la dernière tâche peut finir pendant la confirmation.
        HStack(spacing: 6) {
            if visible {
                ForEach(badges) { badge in
                    Button { showList = true } label: {
                        HStack(spacing: 5) {
                            Circle().fill(badge.active ? Atelier.Tint.ai : Atelier.textSecondary)
                                .frame(width: 5, height: 5)
                            Text("\(badge.name) · \(AIActivityText.label(badge.activity))")
                                .font(Atelier.font(11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Atelier.textPrimary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .atelierPanel(radius: 14)
                        .opacity(badge.active ? 0.82 : 0.48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(badge.name), \(AIActivityText.label(badge.activity))")
                    // Sort de la gauche (du moniteur, #47) ; fondu seul si « Réduire les animations ».
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85),
                   value: badges.map(\.id))
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
        .alert("Arrêter l'analyse du document ?", isPresented: $confirmAnalysisStop) {
            Button("Continuer", role: .cancel) {}
            Button("Arrêter", role: .destructive) { analysis.cancel() }
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
        stopAll ? String(localized: "Arrêter toutes les tâches IA ?") : String(localized: "Arrêter « \(stopping?.title ?? "") » ?")
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
            case ModelSpec.ovisocr2.id where phase == String(localized: "Lecture OvisOCR2"): "analyse"
            case ModelSpec.glmocr.id where phase == String(localized: "Lecture GLM-OCR"): "analyse"
            case ModelSpec.qwen3vl4b.id where phase == String(localized: "Lecture Qwen3-VL-4B"): "analyse"
            case ModelSpec.qwen3vl4b.id where phase == String(localized: "Traduction (Qwen3-VL)"): "traduction"
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
            Button("Voir le journal de diagnostic") { showJournal = true }
                .font(.subheadline)
            Text("Ce que fait chaque IA maintenant, puis les tâches en cours et terminées. Tout est aussi écrit dans le journal de diagnostic (zone « ia »).")
                .font(.caption).foregroundStyle(.secondary)
            // En clair, modèle par modèle (#47) : la pastille seule ne disait pas ce qui se passait.
            ForEach(badges) { badge in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(badge.active ? Atelier.Tint.ai : Atelier.textSecondary).frame(width: 6, height: 6)
                    Text("**\(badge.name)** \(AIActivityText.explain(badge.activity))").font(.subheadline)
                }
            }
            if let p = analysis.progress {
                // L'analyse du document entier n'est pas une tâche de la liste : la montrer quand même.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Analyse du document entier").font(.subheadline.weight(.semibold))
                        Spacer()
                        // Elle n'est pas dans `center.jobs` : sans ce bouton, rien ne l'arrêtait depuis cette liste.
                        Button("Arrêter", role: .destructive) {
                            showList = false
                            // Popover fermé avant l'alerte (sinon iOS 16 n'affiche rien, recette 1.4.2, essai 4.4).
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmAnalysisStop = true }
                        }
                    }
                    Text("\(p.phase) · page \(p.done) sur \(p.total) · étape commencée il y a \(AIActivityText.duration(Date().timeIntervalSince(p.phaseStarted)))\(p.cancelling ? String(localized: " · arrêt demandé") : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if center.jobs.isEmpty && analysis.progress == nil {
                Text("Aucune tâche IA en cours.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
            if !center.recent.isEmpty {
                Divider()
                Text("Terminées récemment").font(.subheadline.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(center.recent) { job in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(job.log.enumerated()), id: \.offset) { _, line in
                                        Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(job.title).font(.caption.weight(.semibold))
                                    Text(job.outcome ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .frame(minWidth: 360)
        .sheet(isPresented: $showJournal) { DiagnosticLogView() }
        .onAppear { Diagnostics.log("Ouverture des tâches : \(center.jobs.count) en cours", "ui") }
    }

    private func detail(_ job: AITaskCenter.Job) -> String {
        let minutes = Int(Date().timeIntervalSince(job.started) / 60)
        var text = minutes < 1 ? String(localized: "Démarrée il y a moins d'une minute") : String(localized: "Démarrée il y a \(minutes) min")
        if let p = job.progress { text += String(localized: " · \(p.done) sur \(p.total)") }
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
