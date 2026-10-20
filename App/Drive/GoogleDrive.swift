// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Accès direct à Google Drive (lecture seule) : connexion OAuth 2 avec PKCE via
/// `ASWebAuthenticationSession` (la page de connexion de Google, pas une vue web maison),
/// jeton de rafraîchissement dans le Trousseau. Seules les requêtes que tu déclenches partent
/// vers Google ; aucune autre donnée n'est envoyée.
@MainActor
final class GoogleDrive: NSObject, ObservableObject {
    static let shared = GoogleDrive()

    struct File: Identifiable, Hashable, Decodable {
        let id: String
        let name: String
        let mimeType: String
        let size: String?
        let modifiedTime: String?
        let md5Checksum: String?

        var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }
        var isPDF: Bool { mimeType == "application/pdf" }
        /// Google Slides / Docs : exportés en PDF au téléchargement.
        var isGoogleExportable: Bool {
            mimeType == "application/vnd.google-apps.presentation" || mimeType == "application/vnd.google-apps.document"
        }
        /// Empreinte de version : change quand le fichier est modifié sur Drive.
        var revision: String? { md5Checksum ?? modifiedTime }
        var byteSize: Int64? { size.flatMap(Int64.init) }
    }

    enum DriveError: LocalizedError {
        case notConfigured, notSignedIn, http(Int, String), cancelled, badResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google Drive n'est pas encore configuré (identifiant client manquant). Voir README → Google Drive."
            case .notSignedIn: return "Connecte-toi à Google Drive d'abord."
            case .http(let code, let message): return "Erreur Google Drive (\(code)) : \(message)"
            case .cancelled: return "Connexion annulée."
            case .badResponse: return "Réponse inattendue de Google."
            }
        }
    }

    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?

    let clientId: String = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)
    var isConfigured: Bool { clientId.hasSuffix(".apps.googleusercontent.com") }

    private var redirectScheme: String {
        clientId.components(separatedBy: ".").reversed().joined(separator: ".")
    }
    private var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    private static let scope = "https://www.googleapis.com/auth/drive.readonly email"

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private let keychain = KeychainItem(service: "fr.noxygen59.kyokasho.google", account: "refresh_token")
    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        isSignedIn = keychain.read() != nil
        accountEmail = UserDefaults.standard.string(forKey: "googleEmail")
    }

    // MARK: Connexion

    func signIn() async throws {
        guard isConfigured else { throw DriveError.notConfigured }
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: DriveError.cancelled)
                } else { continuation.resume(throwing: error ?? DriveError.badResponse) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw DriveError.badResponse }
        let token = try await tokenRequest([
            "code": code, "client_id": clientId, "redirect_uri": redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
        if let refresh = token.refresh_token { keychain.write(refresh) }
        store(token)
        isSignedIn = true
        if let idToken = token.id_token, let email = Self.email(fromIDToken: idToken) {
            accountEmail = email
            UserDefaults.standard.set(email, forKey: "googleEmail")
        }
    }

    func signOut() {
        if let refresh = keychain.read() {
            // Révocation côté Google (au mieux ; sans attendre la réponse).
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(refresh.formEncoded)".data(using: .utf8)
            URLSession.shared.dataTask(with: request).resume()
        }
        keychain.delete()
        accessToken = nil
        accountEmail = nil
        UserDefaults.standard.removeObject(forKey: "googleEmail")
        isSignedIn = false
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let id_token: String?
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, Date() < accessTokenExpiry { return accessToken }
        guard let refresh = keychain.read() else {
            isSignedIn = false
            throw DriveError.notSignedIn
        }
        do {
            let token = try await tokenRequest(["client_id": clientId, "refresh_token": refresh, "grant_type": "refresh_token"])
            store(token)
            return token.access_token
        } catch DriveError.http(400, _), DriveError.http(401, _) {
            // Jeton révoqué ou expiré : il faut se reconnecter.
            keychain.delete()
            isSignedIn = false
            throw DriveError.notSignedIn
        }
    }

    // MARK: Fichiers

    enum Location: Hashable {
        case folder(id: String, name: String)
        case sharedWithMe
        case search(String)
    }

    func list(_ location: Location) async throws -> [File] {
        let base = "trashed = false and (mimeType = 'application/pdf' or mimeType = 'application/vnd.google-apps.folder' or mimeType = 'application/vnd.google-apps.presentation' or mimeType = 'application/vnd.google-apps.document')"
        let query: String
        switch location {
        case .folder(let id, _): query = "'\(id.queryEscaped)' in parents and \(base)"
        case .sharedWithMe: query = "sharedWithMe and \(base)"
        case .search(let text): query = "name contains '\(text.queryEscaped)' and \(base)"
        }
        var files: [File] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            components.queryItems = [
                .init(name: "q", value: query),
                .init(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)"),
                .init(name: "orderBy", value: "folder,name_natural"),
                .init(name: "pageSize", value: "200"),
                .init(name: "supportsAllDrives", value: "true"),
                .init(name: "includeItemsFromAllDrives", value: "true"),
            ]
            if let pageToken { components.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            struct Page: Decodable { let files: [File]; let nextPageToken: String? }
            let page: Page = try await get(components.url!)
            files += page.files
            pageToken = page.nextPageToken
        } while pageToken != nil && files.count < 2000
        return files
    }

    func metadata(fileId: String) async throws -> File {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        components.queryItems = [.init(name: "fields", value: "id,name,mimeType,size,modifiedTime,md5Checksum"),
                                 .init(name: "supportsAllDrives", value: "true")]
        return try await get(components.url!)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Télécharge le fichier (export PDF pour Slides/Docs) dans un fichier temporaire, avec progression.
    func download(_ file: File, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url: URL
        if file.isGoogleExportable {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(file.id)/export")!
            c.queryItems = [.init(name: "mimeType", value: "application/pdf")]
            url = c.url!
        } else {
            var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(file.id)")!
            c.queryItems = [.init(name: "alt", value: "media"), .init(name: "supportsAllDrives", value: "true")]
            url = c.url!
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let delegate = DownloadProgress(expected: file.byteSize, onProgress: progress)
        let (temp, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = (try? String(contentsOf: temp)) ?? ""
            throw DriveError.http(http.statusCode, body.prefix(200).description)
        }
        // Nom propre (sert de titre à l'import).
        var name = file.name
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }

    // MARK: Utilitaires

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DriveError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct GoogleError: Decodable {
                struct Inner: Decodable { let message: String? }
                let error: Inner?
                let error_description: String?
            }
            let decoded = try? JSONDecoder().decode(GoogleError.self, from: data)
            throw DriveError.http(http.statusCode, decoded?.error?.message ?? decoded?.error_description ?? "")
        }
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URL
    }

    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}

extension GoogleDrive: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

private final class DownloadProgress: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let expected: Int64?
    let onProgress: @Sendable (Double) -> Void

    init(expected: Int64?, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expected = expected
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (expected ?? 0)
        if total > 0 { onProgress(min(1, Double(totalBytesWritten) / Double(total))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

/// Petit accès au Trousseau (un seul secret : le jeton de rafraîchissement Google).
struct KeychainItem {
    let service: String
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    /// Échappement pour les requêtes Drive (`name contains '…'`).
    var queryEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
}
