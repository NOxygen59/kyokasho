// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// « Mise à jour disponible » : lit `latest.json` du dépôt public NOxygen59/kyokasho-models (numéro de
/// version seulement ; l'app elle-même reste dans le dépôt privé). Une fois à chaque lancement ; si GitHub est
/// connecté, le `.tipa` est ensuite téléchargé en fond (`UpdateInstaller`).
@MainActor
final class AppUpdate: ObservableObject {
    static let shared = AppUpdate()
    static let url = URL(string: "https://raw.githubusercontent.com/NOxygen59/kyokasho-models/main/latest.json")!

    struct Latest: Decodable, Equatable {
        var version: String
        var build: Int
        /// Page de la release (dépôt privé : ouverte dans Safari, où l'on est connecté à GitHub).
        var page: URL
        var notes: String?
    }

    enum State: Equatable { case idle, checking, upToDate, failed }

    @Published private(set) var available: Latest?
    @Published private(set) var state: State = .idle

    private let lastCheckKey = "update.lastCheck"
    private let dismissedKey = "update.dismissedBuild"

    static var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }

    /// Au lancement (une seule fois par lancement).
    func checkAtLaunch() {
        UpdateInstaller.shared.cleanUp()
        Task { await check(manual: false) }
    }

    func check(manual: Bool = true) async {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.url, timeoutInterval: 10)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Latest.self, from: data) else {
            state = .failed
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        // « Plus tard » sur une version : plus d'avis automatique pour elle (la vérification manuelle la montre).
        let dismissed = UserDefaults.standard.integer(forKey: dismissedKey)
        if latest.build > Self.currentBuild, manual || latest.build != dismissed {
            available = latest
            state = .idle
            UpdateInstaller.shared.prepare(latest)
        } else {
            available = nil
            state = .upToDate
        }
    }

    func dismiss() {
        if let available { UserDefaults.standard.set(available.build, forKey: dismissedKey) }
        available = nil
    }
}

/// Bandeau en haut de la bibliothèque quand une version plus récente existe.
struct UpdateBanner: View {
    @ObservedObject private var update = AppUpdate.shared
    @ObservedObject private var installer = UpdateInstaller.shared
    @Environment(\.openURL) private var openURL
    @State private var installFailed = false

    var body: some View {
        if let latest = update.available {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(Atelier.font(22)).foregroundStyle(Atelier.Tint.read)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kyōkasho \(latest.version) disponible").font(Atelier.font(15, weight: .semibold))
                        .foregroundStyle(Atelier.textPrimary)
                    if let notes = latest.notes {
                        Text(notes).font(.footnote).foregroundStyle(Atelier.textSecondary).lineLimit(2)
                    }
                }
                Spacer()
                Button("Plus tard") { update.dismiss() }.foregroundStyle(Atelier.textSecondary)
                switch installer.state {
                case .downloading:
                    HStack(spacing: 6) { ProgressView(); Text("Téléchargement…") }.foregroundStyle(Atelier.textSecondary)
                case .ready(let file):
                    // Repli si le lien TrollStore n'est pas activé : « Ouvrir avec… » → TrollStore.
                    ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                        .foregroundStyle(installFailed ? Atelier.Tint.read : Atelier.textSecondary)
                        .accessibilityLabel("Ouvrir le fichier dans TrollStore")
                    Button("Installer") { Task { installFailed = !(await installer.installWithTrollStore()) } }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                default:
                    Button("Télécharger") { openURL(latest.page) }
                        .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .atelierPanel(radius: 16)
            .padding(.horizontal, Atelier.gap).padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
