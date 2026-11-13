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
/// plus : on programme les `limit` rappels les plus proches, et tout est reprogrammé à chaque changement de note, au
/// lancement et au retour dans l'app (`AppModel.refreshNotesToReview`). Note archivée, sans échéance, ou document à la
/// corbeille : aucun rappel. L'autorisation d'iOS n'est demandée qu'au premier rappel à programmer.
enum NoteNotifications {
    static let prefix = "note-"
    static let limit = 60
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

    /// Une notification à programmer : identifiant stable, instant, contenu.
    struct Planned: Equatable {
        let id: String
        let date: Date
        let title: String
        let body: String
        let noteId: String
        let documentId: String
    }

    /// Rappels à programmer, les plus proches d'abord (fonction pure).
    static func plan(_ notes: [OrganizedNote], titles: [String: String], now: Date, defaultMinute: Int,
                     defaultReminders: [Int], calendar: Calendar = NoteDay.calendar) -> [Planned] {
        var planned: [Planned] = []
        for item in notes where !item.organization.archived {
            guard let day = item.organization.dueDay, let book = titles[item.note.documentId] else { continue }
            let dates = NoteReminder.fireDates(day: day, minute: item.organization.dueMinute, reminders: item.organization.reminders,
                                               now: now, defaultMinute: defaultMinute, defaultReminders: defaultReminders,
                                               calendar: calendar)
            let text = item.note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            for date in dates {
                planned.append(Planned(id: "\(prefix)\(item.note.id)-\(Int(date.timeIntervalSince1970))", date: date,
                                       title: String(localized: "\(book) · p. \(item.note.pageIndex + 1)"),
                                       body: text.isEmpty ? String(localized: "Note sans texte") : String(text.prefix(150)),
                                       noteId: item.note.id, documentId: item.note.documentId))
            }
        }
        return Array(planned.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// Reprogramme tous les rappels de notes (les autres notifications de l'app ne sont pas touchées).
    static func reschedule(database: AppDatabase, titles: [String: String], excluded: Set<String>) {
        // Revue R2 NOTIF (n°1) : bibliothèque pas encore lue (lancement) : on ne touche à rien, sinon tous les rappels
        // seraient retirés faute de titres.
        guard !titles.isEmpty else { return }
        let defaultMinute = defaultDueMinute, reminders = defaultReminders
        let generation = Generation.next()
        Task.detached(priority: .utility) {
            let notes: [OrganizedNote]
            do { notes = try database.organizedNotes(includeArchived: false, excludingDocuments: excluded) } catch {
                Diagnostics.error("rappels des notes : \(error.localizedDescription)", "notes")
                return
            }
            let planned = plan(notes, titles: titles, now: Date(), defaultMinute: defaultMinute, defaultReminders: reminders)
            let center = UNUserNotificationCenter.current()
            // Deux reprogrammations de suite : seule la dernière écrit (pas de rappels en double ni retirés à tort).
            guard Generation.isCurrent(generation) else { return }
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard !planned.isEmpty else { return }
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            for item in planned {
                guard Generation.isCurrent(generation) else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.threadIdentifier = item.documentId
                content.userInfo = ["noteId": item.noteId, "documentId": item.documentId]
                let parts = NoteDay.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                let request = UNNotificationRequest(identifier: item.id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                do { try await center.add(request) } catch {
                    Diagnostics.error("rappel non programmé : \(error.localizedDescription)", "notes")
                }
            }
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
