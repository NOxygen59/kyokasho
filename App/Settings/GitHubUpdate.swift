// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit

/// Connexion à GitHub par « device flow » : l'app affiche un code, tu le tapes sur github.com/login/device
/// (connecté à ton compte), GitHub donne à l'app un jeton gardé dans le Trousseau. Aucun mot de passe ne passe
/// par l'app. Le jeton vient d'une **GitHub App à toi** (Client ID collé dans Réglages), limitée au dépôt
/// `NOxygen59/kyokasho` en lecture seule : il sert seulement à télécharger le `.tipa` des releases.
@MainActor
final class GitHubAccount: ObservableObject {
    static let shared = GitHubAccount()
    static let repo = "NOxygen59/kyokasho"
    static let clientIDKey = "github.clientID"

    struct DeviceCode: Equatable {
        let userCode: String
        let verification: URL
        let deviceCode: String
        let interval: Int
        let expires: Date
    }

    @Published private(set) var isConnected: Bool
    @Published private(set) var pending: DeviceCode?
    @Published private(set) var error: String?
    private let keychain = KeychainItem(service: "fr.noxygen59.kyokasho.github", account: "token")
    private var pollTask: Task<Void, Never>?

    var clientID: String { UserDefaults.standard.string(forKey: Self.clientIDKey)?.trimmingCharacters(in: .whitespaces) ?? "" }
    var token: String? { keychain.read() }

    private init() { isConnected = keychain.read() != nil }

    /// Demande un code à GitHub, puis attend que tu l'aies validé sur github.com.
    func connect() {
        error = nil
        guard !clientID.isEmpty else { error = "Colle d'abord le Client ID de ta GitHub App."; return }
        pollTask?.cancel()
        pollTask = Task {
            do {
                let start = try await Self.form("https://github.com/login/device/code", ["client_id": clientID])
                guard let device = start["device_code"] as? String, let user = start["user_code"] as? String,
                      let uri = (start["verification_uri"] as? String).flatMap(URL.init(string:)) else {
                    throw Failure.message(start["error_description"] as? String ?? "Réponse inattendue de GitHub.")
                }
                let code = DeviceCode(userCode: user, verification: uri, deviceCode: device,
                                      interval: start["interval"] as? Int ?? 5,
                                      expires: Date().addingTimeInterval(TimeInterval(start["expires_in"] as? Int ?? 900)))
                pending = code
                try await poll(code)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            pending = nil
        }
    }

    func cancel() {
        pollTask?.cancel()
        pending = nil
    }

    func disconnect() {
        cancel()
        keychain.delete()
        isConnected = false
    }

    private func poll(_ code: DeviceCode) async throws {
        var interval = code.interval
        while Date() < code.expires {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let reply = try await Self.form("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = reply["access_token"] as? String {
                keychain.write(token)
                isConnected = true
                return
            }
            switch reply["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw Failure.message("Connexion refusée sur GitHub.")
            case let other: throw Failure.message(reply["error_description"] as? String ?? other ?? "Erreur GitHub.")
            }
        }
        throw Failure.message("Code expiré : recommence.")
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    private static func form(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parts = URLComponents()
        parts.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = parts.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Requête à l'API GitHub avec le jeton.
    func apiRequest(_ path: String, accept: String = "application/vnd.github+json") throws -> URLRequest {
        guard let token else { throw Failure.message("Connecte GitHub dans Réglages → À propos.") }
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
}

/// Mise à jour par TrollStore : `.tipa` de la release téléchargé en fond (dépôt privé, jeton GitHub),
/// puis installation par `apple-magnifier://install?url=…` (lien temporaire signé par GitHub, que TrollStore
/// télécharge lui-même), ou en ouvrant le fichier téléchargé dans TrollStore. Fichier effacé au lancement
/// suivant dès que la nouvelle version tourne.
@MainActor
final class UpdateInstaller: ObservableObject {
    static let shared = UpdateInstaller()

    enum State: Equatable {
        case idle, downloading(Double), ready(URL), failed(String)
    }

    @Published private(set) var state: State = .idle
    private var assetID: Int?
    private var task: Task<Void, Never>?
    private let downloadedBuildKey = "update.downloadedBuild"

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Update", isDirectory: true)
    }

    /// Au lancement : fichier d'une version déjà installée → effacé.
    func cleanUp() {
        let built = UserDefaults.standard.integer(forKey: downloadedBuildKey)
        guard built > 0, AppUpdate.currentBuild >= built else { return }
        try? FileManager.default.removeItem(at: Self.folder)
        UserDefaults.standard.removeObject(forKey: downloadedBuildKey)
    }

    /// Télécharge le `.tipa` de la version annoncée (si GitHub est connecté). Sans effet s'il est déjà là.
    func prepare(_ latest: AppUpdate.Latest) {
        guard GitHubAccount.shared.isConnected else { return }
        if case .downloading = state { return }
        if case .ready = state { return }
        task = Task { await download(latest) }
    }

    private func download(_ latest: AppUpdate.Latest) async {
        state = .downloading(0)
        do {
            let tag = latest.version.hasPrefix("v") ? latest.version : "v" + latest.version
            let (data, response) = try await URLSession.shared.data(for: GitHubAccount.shared.apiRequest("/repos/\(GitHubAccount.repo)/releases/tags/\(tag)"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw GitHubAccount.Failure.message("Release \(tag) introuvable (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            struct Release: Decodable { struct Asset: Decodable { let id: Int; let name: String }; let assets: [Asset] }
            guard let asset = try JSONDecoder().decode(Release.self, from: data).assets.first(where: { $0.name.hasSuffix(".tipa") }) else {
                throw GitHubAccount.Failure.message("Pas de .tipa dans la release \(tag).")
            }
            assetID = asset.id
            let signed = try await signedURL(asset: asset.id)
            let (temp, reply) = try await URLSession.shared.download(from: signed, delegate: nil)
            guard (reply as? HTTPURLResponse)?.statusCode == 200 else { throw GitHubAccount.Failure.message("Téléchargement refusé.") }
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let target = Self.folder.appendingPathComponent(asset.name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            UserDefaults.standard.set(latest.build, forKey: downloadedBuildKey)
            state = .ready(target)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// GitHub répond 302 vers un lien signé valable quelques minutes ; on le récupère sans le suivre
    /// (le stockage refuse les requêtes qui portent encore le jeton GitHub).
    private func signedURL(asset: Int) async throws -> URL {
        let request = try GitHubAccount.shared.apiRequest("/repos/\(GitHubAccount.repo)/releases/assets/\(asset)",
                                                          accept: "application/octet-stream")
        let (_, response) = try await URLSession.shared.data(for: request, delegate: NoRedirect())
        guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
            throw GitHubAccount.Failure.message("Lien de téléchargement non obtenu.")
        }
        return url
    }

    /// Ouvre TrollStore sur un lien signé tout frais (il installe puis relance l'app).
    func installWithTrollStore() async -> Bool {
        guard let assetID, let signed = try? await signedURL(asset: assetID) else { return false }
        // Lien signé entièrement encodé (ses « & » et « = » ne doivent pas couper le paramètre `url`).
        let encoded = signed.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
        guard let url = URL(string: "apple-magnifier://install?url=" + encoded) else { return false }
        return await UIApplication.shared.open(url)
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Réglages → À propos : connexion GitHub (pour la mise à jour par TrollStore).
struct GitHubUpdateSection: View {
    @ObservedObject private var account = GitHubAccount.shared
    @AppStorage(GitHubAccount.clientIDKey) private var clientID = ""
    @Environment(\.openURL) private var openURL
    @State private var showHelp = false

    var body: some View {
        Section {
            if account.isConnected {
                LabeledContent("GitHub", value: "connecté")
                Button("Se déconnecter", role: .destructive) { account.disconnect() }
            } else if let code = account.pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tape ce code sur GitHub :").font(.subheadline)
                    Text(code.userCode).font(.system(size: 28, weight: .bold, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button { UIPasteboard.general.string = code.userCode } label: { Label("Copier", systemImage: "doc.on.doc") }
                        Spacer()
                        Button { openURL(code.verification) } label: { Label("Ouvrir GitHub", systemImage: "safari") }
                    }
                    .buttonStyle(.bordered)
                    HStack { ProgressView(); Text("En attente de ta validation…").foregroundStyle(.secondary) }
                    Button("Annuler") { account.cancel() }
                }
            } else {
                TextField("Client ID de ta GitHub App (Iv1… / Iv23…)", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button { account.connect() } label: { Label("Se connecter à GitHub", systemImage: "person.badge.key") }
                    .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                DisclosureGroup("Créer la GitHub App (une fois)", isExpanded: $showHelp) {
                    Text("""
                    1. github.com → Settings → Developer settings → GitHub Apps → New GitHub App.
                    2. Nom : « Kyokasho Updater », Homepage : l'adresse de ton dépôt. Webhook : décocher « Active ».
                    3. Cocher « Enable Device Flow ». Décocher « Expire user authorization tokens ».
                    4. Permissions → Repository → Contents : Read-only. Rien d'autre.
                    5. « Only on this account » → Create. Puis Install App → Only select repositories → kyokasho.
                    6. Copier le « Client ID » ici, puis « Se connecter ».
                    """).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = account.error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Mise à jour par TrollStore")
        } footer: {
            Text("Le jeton reste dans le Trousseau de l'iPad et ne sert qu'à lire les releases de ton dépôt privé. Dans TrollStore, active Réglages → « URL Scheme Enabled » pour l'installation en un geste.")
        }
    }
}
