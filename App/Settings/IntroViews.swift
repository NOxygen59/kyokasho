// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Préférences de la visite et des nouveautés (dans la sauvegarde, comme toutes les préférences).
enum IntroStore {
    static let tourSeenKey = "intro.tourSeen"
    static let lastSeenKey = "intro.lastSeenVersion"

    /// « 1.3.2 (65) » : les nouveautés reviennent à chaque nouvelle installation, candidate comprise.
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    static var marketingVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// Une fois vue (visite ou nouveautés), la version installée ne se remontre plus.
    static func markSeen(tour: Bool) {
        if tour { UserDefaults.standard.set(true, forKey: tourSeenKey) }
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }
}

/// Visite guidée : une page par étape (comment faire, pourquoi), points de pagination, « Suivant » puis « Commencer ».
struct IntroTourView: View {
    var onFinish: () -> Void
    @State private var page = 0
    private let steps = AppTour.steps

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button("Passer") { onFinish() }.font(.subheadline)
            }
            TabView(selection: $page) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 18) {
                        Image(systemName: step.icon)
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(Atelier.Tint.read)
                            .frame(height: 70)
                        Text(step.title).font(Atelier.display(28)).foregroundStyle(Atelier.textPrimary)
                        VStack(alignment: .leading, spacing: 12) {
                            Label { Text(step.how) } icon: { Image(systemName: "hand.point.up.left") }
                            Label { Text(step.why) } icon: { Image(systemName: "lightbulb") }
                                .foregroundStyle(Atelier.textSecondary)
                        }
                        .font(.body)
                        .frame(maxWidth: 520, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if page < steps.count - 1 { withAnimation { page += 1 } } else { onFinish() }
            } label: {
                Text(page < steps.count - 1 ? "Suivant" : "Commencer").frame(maxWidth: 280)
            }
            .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .background(Atelier.surface.ignoresSafeArea())
    }
}

/// Nouveautés d'une version : ajouté, corrigé, retiré.
struct WhatsNewView: View {
    let notes: ReleaseNotes
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                section("Ajouté", icon: "plus.circle.fill", tint: .green, items: notes.added)
                section("Corrigé", icon: "wrench.and.screwdriver.fill", tint: .orange, items: notes.fixed)
                section("Retiré", icon: "minus.circle.fill", tint: .red, items: notes.removed)
            }
            .navigationTitle("Nouveautés de la \(notes.version)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { onClose() } } }
        }
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, tint: Color, items: [String]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.self) { item in
                    Label { Text(item) } icon: { Image(systemName: icon).foregroundStyle(tint) }
                }
            } header: { Text(title) }
        }
    }
}

/// Au lancement : visite pour un nouvel utilisateur, nouveautés après une mise à jour (`IntroGate`).
struct IntroPresenter: ViewModifier {
    /// Lu après le délai (pas à la création de la vue, où la bibliothèque est encore vide).
    let hasLibrary: () -> Bool
    @State private var showing: IntroGate = .none

    func body(content: Content) -> some View {
        content
            .task {
                // Laisser la bibliothèque se charger : un utilisateur existant voit les nouveautés, pas la visite.
                try? await Task.sleep(nanoseconds: 900_000_000)
                let defaults = UserDefaults.standard
                showing = IntroGate.decide(tourSeen: defaults.bool(forKey: IntroStore.tourSeenKey),
                                           lastSeen: defaults.string(forKey: IntroStore.lastSeenKey),
                                           current: IntroStore.currentVersion,
                                           hasNotes: ReleaseNotes.notes(for: IntroStore.marketingVersion) != nil,
                                           hasLibrary: hasLibrary())
                if showing == .none { IntroStore.markSeen(tour: false) }
            }
            .fullScreenCover(isPresented: Binding(get: { showing == .tour }, set: { if !$0 { showing = .none } })) {
                IntroTourView { IntroStore.markSeen(tour: true); showing = .none }
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: Binding(get: { showing == .whatsNew }, set: { if !$0 { IntroStore.markSeen(tour: false); showing = .none } })) {
                if let notes = ReleaseNotes.notes(for: IntroStore.marketingVersion) {
                    WhatsNewView(notes: notes) { IntroStore.markSeen(tour: false); showing = .none }
                        .preferredColorScheme(.dark)
                }
            }
    }
}

/// Réglages : revoir la visite ou les nouveautés.
struct IntroSettingsSection: View {
    @State private var tour = false
    @State private var news = false

    var body: some View {
        Section {
            Button { tour = true } label: { Label("Revoir la visite guidée", systemImage: "figure.walk") }
            if ReleaseNotes.notes(for: IntroStore.marketingVersion) != nil {
                Button { news = true } label: { Label("Nouveautés de cette version", systemImage: "sparkles") }
            }
        } header: {
            Text("Découvrir l'app")
        } footer: {
            Text("Version \(IntroStore.currentVersion).")
        }
        .fullScreenCover(isPresented: $tour) {
            IntroTourView { IntroStore.markSeen(tour: true); tour = false }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $news) {
            if let notes = ReleaseNotes.notes(for: IntroStore.marketingVersion) {
                WhatsNewView(notes: notes) { news = false }.preferredColorScheme(.dark)
            }
        }
    }
}
