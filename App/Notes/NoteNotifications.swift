// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ReaderCore
import SwiftUI
import UIKit
import UserNotifications

/// Notifications iOS des rappels de notes (PLAN-NOTIF-001, E3 ; DEC-03 à DEC-05 = A, NOxygen59 13/11/2026).
///
/// Notifications **locales** : programmées sur l'iPad, sans serveur ; rien ne sort de l'appareil. iOS en garde 64 au
/// plus : on programme les `NoteReminderPlan.limit` rappels les plus proches, et tout est reprogrammé à chaque changement de note, au
/// lancement et au retour dans l'app (`AppModel.refreshNotesToReview`). Note archivée, sans échéance, ou document à la
/// corbeille : aucun rappel. L'autorisation d'iOS n'est demandée qu'au premier rappel à programmer.
enum NoteNotifications {
    static let prefix = NoteReminderPlan.prefix
    /// Réglages › Notes : rappel d'une nouvelle échéance, en minutes avant (−1 : aucun). Défaut : à l'heure.
    static let defaultReminderKey = "notes.defaultReminder"

    /// Rappels par défaut, d'après les Réglages.
    static var defaultReminders: [Int] {
        let value = UserDefaults.standard.object(forKey: defaultReminderKey) as? Int ?? 0
        return value < 0 ? [] : [value]
    }

    /// Heure par défaut d'une échéance sans heure, d'après les Réglages.
    static var defaultDueMinute: Int {
        let value = UserDefaults.standard.object(forKey: NoteSettingsView.defaultDueMinuteKey) as? Int ?? NoteReminder.defaultDueMinute
        return (0..<1_440).contains(value) ? value : NoteReminder.defaultDueMinute
    }

    /// Reprogramme les rappels de notes (les autres notifications de l'app ne sont pas touchées).
    /// #96 (PLAN-16-001, E4) : numéro de page imprimé, autorisation relue après la demande, et seuls les rappels qui
    /// changent sont retirés ou ajoutés (`NoteReminderPlan`), au lieu de tout retirer puis tout recréer.
    static func reschedule(database: AppDatabase, documents: [String: LibraryDocument], libraryLoaded: Bool,
                           excluded: Set<String>) {
        // Revue R2 NOTIF (n°1) : bibliothèque pas encore lue (lancement) : on ne touche à rien, sinon tous les rappels
        // seraient retirés faute de titres. Lue mais vide (dernier livre à la corbeille) : tout est retiré (revue R2 #96).
        guard libraryLoaded else { return }
        let titles = documents.mapValues(\.title)
        let defaultMinute = defaultDueMinute, reminders = defaultReminders
        let generation = Generation.next()
        // Revue R2 #96 : une réconciliation à la fois, jusqu'au bout des écritures d'iOS ; une demande dépassée par une
        // plus récente ne fait rien. Sinon une ancienne pouvait rajouter un rappel qu'une plus récente venait de retirer.
        ReconcileQueue.enqueue {
            guard Generation.isCurrent(generation) else { return }
            let notes: [OrganizedNote]
            do { notes = try database.organizedNotes(includeArchived: false, excludingDocuments: excluded) } catch {
                Diagnostics.error("rappels des notes : \(Diagnostics.describe(error))", "notes")
                return
            }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }.map(Self.pending)
            let plan = NoteReminderPlan.make(
                notes, titles: titles, pageLabel: { id, index in documents[id]?.pageLabel(index) },
                now: Date(), pending: pending, defaultMinute: defaultMinute, defaultReminders: reminders,
                calendar: NoteDay.calendar, makeTitle: { book, label in String(localized: "\(book) · p. \(label)") },
                emptyBody: String(localized: "Note sans texte"))
            var status = await center.notificationSettings().authorizationStatus
            if !plan.updates.isEmpty, status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                // Relue : la réponse de l'utilisateur décide, pas l'état d'avant la question.
                status = await center.notificationSettings().authorizationStatus
            }
            // Deux reprogrammations de suite : seule la dernière écrit (pas de rappels en double ni retirés à tort).
            guard Generation.isCurrent(generation) else { return }
            center.removePendingNotificationRequests(withIdentifiers: plan.removals)
            guard [UNAuthorizationStatus.authorized, .provisional, .ephemeral].contains(status) else {
                // Refus : rien n'est programmé ; Réglages › Rappels l'explique (« Notifications refusées »).
                if !plan.updates.isEmpty { Diagnostics.log("rappels : notifications non autorisées, \(plan.updates.count) rappel(s) non programmé(s)", "notes") }
                return
            }
            for update in plan.updates {
                guard Generation.isCurrent(generation) else { return }
                let reminder: NoteReminderPlan.Reminder
                switch update { case .add(let r), .replace(let r): reminder = r }
                let content = UNMutableNotificationContent()
                content.title = reminder.content.title
                content.body = reminder.content.body
                content.sound = .default
                content.threadIdentifier = reminder.content.documentId
                content.userInfo = ["noteId": reminder.content.noteId, "documentId": reminder.content.documentId]
                // Même identifiant : iOS remplace la demande existante, sans retrait préalable.
                let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: reminder.trigger.components,
                                                                                           repeats: reminder.trigger.repeats))
                do { try await center.add(request) } catch {
                    Diagnostics.error("rappel non programmé : \(Diagnostics.describe(error))", "notes")
                }
            }
        }
    }

    /// Demande déjà programmée → forme comparable par le plan (`nil` si contenu ou déclencheur inattendu : remplacé).
    private static func pending(_ request: UNNotificationRequest) -> NoteReminderPlan.PendingReminder {
        let info = request.content.userInfo
        let content = (info["noteId"] as? String).flatMap { noteId in
            (info["documentId"] as? String).map { documentId in
                NoteReminderPlan.Content(title: request.content.title, body: request.content.body,
                                         noteId: noteId, documentId: documentId)
            }
        }
        let trigger = (request.trigger as? UNCalendarNotificationTrigger).map {
            NoteReminderPlan.Trigger(components: $0.dateComponents, repeats: $0.repeats)
        }
        return .init(id: request.identifier, content: content, trigger: trigger)
    }
}

/// File des réconciliations de rappels : chacune attend la fin complète de la précédente (revue R2 #96).
private enum ReconcileQueue {
    private static let lock = NSLock()
    private static var tail: Task<Void, Never>?

    static func enqueue(_ work: @escaping @Sendable () async -> Void) {
        lock.lock(); defer { lock.unlock() }
        let previous = tail
        tail = Task.detached(priority: .utility) {
            await previous?.value
            await work()
        }
    }
}

/// Numéro de la dernière reprogrammation demandée (revue R2 NOTIF n°1).
private enum Generation {
    private static let lock = NSLock()
    private static var current = 0

    static func next() -> Int { lock.lock(); defer { lock.unlock() }; current += 1; return current }
    static func isCurrent(_ value: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == current }
}

/// Toucher une notification de note ouvre le livre à sa page (PLAN-NOTIF-001, E4) ; dans l'app, la bannière s'affiche
/// quand même.
final class NoteNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NoteNotificationDelegate()
    /// Posé par l'écran racine. Une notification touchée avant (lancement à froid) attend dans `pending`.
    weak var model: AppModel? {
        didSet {
            guard let model, let pending else { return }
            self.pending = nil
            DispatchQueue.main.async { model.openNote(documentId: pending.documentId, noteId: pending.noteId) }
        }
    }
    private var pending: (documentId: String, noteId: String)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let noteId = info["noteId"] as? String, let documentId = info["documentId"] as? String {
            // Revue R2 NOTIF (n°7) : `model` et `pending` ne sont lus et écrits que sur le fil principal.
            DispatchQueue.main.async {
                if let model = self.model {
                    model.openNote(documentId: documentId, noteId: noteId)
                } else {
                    self.pending = (documentId, noteId)
                }
            }
        }
        completionHandler()
    }
}

/// Réglages des rappels (PLAN-NOTIF-001, E4), ouverts par la cloche de l'écran Notes : heure d'une échéance sans
/// heure, rappel d'une nouvelle échéance, état de l'autorisation d'iOS. Fermer reprogramme les rappels.
struct NoteReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NoteSettingsView.defaultDueMinuteKey) private var defaultDueMinute = NoteReminder.defaultDueMinute
    @AppStorage(NoteNotifications.defaultReminderKey) private var defaultReminder = 0
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(String(localized: "Heure d'une échéance sans heure"), selection: Binding(
                        get: { NoteSettingsView.time(defaultDueMinute) },
                        set: { defaultDueMinute = NoteSettingsView.minute(of: $0) }), displayedComponents: .hourAndMinute)
                    Picker(String(localized: "Rappel d'une nouvelle échéance"), selection: $defaultReminder) {
                        Text("Aucun").tag(-1)
                        ForEach(NoteReminder.choices, id: \.self) { Text(NoteSettingsView.reminderTitle($0)).tag($0) }
                    }
                } footer: {
                    Text("Valent pour les notes dont l'heure ou les rappels n'ont pas été réglés.")
                }
                Section {
                    switch status {
                    case .authorized, .provisional, .ephemeral:
                        Label("Notifications autorisées", systemImage: "checkmark.circle")
                    case .denied:
                        Label("Notifications refusées", systemImage: "bell.slash")
                        Button("Ouvrir les Réglages d'iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    case .notDetermined:
                        Text("iOS demandera l'autorisation au premier rappel.")
                    default:
                        ProgressView()
                    }
                } header: {
                    Text("Notifications d'iOS")
                } footer: {
                    Text("Les rappels sont programmés sur l'iPad, sans serveur. Le texte de la note s'affiche sur l'écran verrouillé selon Réglages › Notifications › Afficher les aperçus.")
                }
            }
            .navigationTitle("Rappels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task { await refresh() }
            .onChange(of: scenePhase) { if $0 == .active { Task { await refresh() } } }
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
