// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

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
        var progress: (done: Int, total: Int)?

        static func == (a: Job, b: Job) -> Bool {
            a.id == b.id && a.progress?.done == b.progress?.done && a.progress?.total == b.progress?.total
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
    func run(_ key: String, title: String, _ work: @escaping @MainActor (_ id: UUID) async throws -> Void) -> Bool {
        guard !isRunning(key) else { return false }
        let job = Job(key: key, title: title)
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

/// Pastille « IA : … » posée sur le lecteur et la bibliothèque. Toucher → liste des tâches ; « Arrêter » demande
/// deux confirmations (une tâche IA coûte des minutes).
struct AITaskPill: View {
    @ObservedObject private var center = AITaskCenter.shared
    @State private var showList = false
    /// Tâche à arrêter (`nil` + `stopAll` = toutes) : 1re puis 2e confirmation.
    @State private var stopping: AITaskCenter.Job?
    @State private var stopAll = false
    @State private var confirm1 = false
    @State private var confirm2 = false

    var body: some View {
        // Alertes et popover sur un conteneur toujours présent : la dernière tâche peut finir pendant la confirmation.
        ZStack {
            if let first = center.jobs.first {
                Button { showList = true } label: {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(label(first)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Atelier.Tint.ai.opacity(0.9), in: Capsule())
                }
                .accessibilityLabel("Tâches IA en cours")
            }
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

    private func label(_ job: AITaskCenter.Job) -> String {
        var text = "IA : \(job.title)"
        if let p = job.progress { text += " (\(p.done)/\(p.total))" }
        if center.jobs.count > 1 { text += " +\(center.jobs.count - 1)" }
        return text
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tâches IA en cours").font(.headline)
            ForEach(center.jobs) { job in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title).font(.subheadline.weight(.semibold))
                        Text(detail(job)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Arrêter", role: .destructive) { ask(job) }
                }
            }
            if center.jobs.count > 1 {
                Button("Tout arrêter", role: .destructive) { ask(nil) }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(minWidth: 320)
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
