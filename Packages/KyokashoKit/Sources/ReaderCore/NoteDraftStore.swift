// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Brouillons de notes pas encore ajoutées, un par page source d'un document (RET-008, Issue #11).
///
/// Stockés hors de la base, dans `<dossier>/<documentId>.json`, et écrits à chaque modification
/// (écriture atomique) : un brouillon survit au changement d'onglet, à la fermeture du livre et à un
/// arrêt brutal de l'app (manque de mémoire pendant une analyse IA, par exemple).
///
/// Invariant : les clés sont des index de **page source** (0 = première page du PDF), comme
/// `PageComment.pageIndex`. Un ajout de pages devant le document décale donc aussi les brouillons :
/// `PageShift` prépare la valeur finale avec ``shifted(_:by:)`` et l'installe dans son journal rejouable.
/// Un texte vide ou blanc n'est jamais conservé ; un document sans brouillon n'a pas de fichier.
public struct NoteDraftStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Magasin de l'app : Application Support, sauvegardé avec le conteneur (pas dans Caches).
    /// Remplacé par les tests Mac pour travailler dans un dossier temporaire.
    nonisolated(unsafe) public static var shared = NoteDraftStore(
        folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true)
            .appendingPathComponent("NoteDrafts", isDirectory: true))

    /// Fichier du document. `documentId` est un identifiant interne (hash), jamais un titre.
    public func url(documentId: String) -> URL {
        folder.appendingPathComponent(documentId + ".json")
    }

    /// Tous les brouillons du document, par page source. Fichier absent ou illisible : aucun brouillon.
    public func drafts(documentId: String) -> [Int: String] {
        guard let data = try? Data(contentsOf: url(documentId: documentId)) else { return [:] }
        return (try? Self.decode(data)) ?? [:]
    }

    /// Brouillon d'une page, ou chaîne vide.
    public func draft(documentId: String, page: Int) -> String {
        drafts(documentId: documentId)[page] ?? ""
    }

    /// Enregistre (ou efface, si le texte est vide ou blanc) le brouillon d'une page.
    /// Le texte est conservé tel quel, espaces et retours compris : seul le test de vacuité les ignore.
    /// - Throws: erreur d'écriture du système de fichiers ; le fichier précédent reste alors intact.
    public func setDraft(_ text: String, documentId: String, page: Int) throws {
        var all = drafts(documentId: documentId)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard all.removeValue(forKey: page) != nil else { return }
        } else {
            guard all[page] != text else { return }
            all[page] = text
        }
        try write(all, documentId: documentId)
    }

    /// Supprime tous les brouillons d'un document (document effacé de la bibliothèque).
    public func removeAll(documentId: String) throws {
        let file = url(documentId: documentId)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// Remplace l'ensemble des brouillons d'un document ; ensemble vide = fichier supprimé.
    public func write(_ drafts: [Int: String], documentId: String) throws {
        if drafts.isEmpty { return try removeAll(documentId: documentId) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encode(drafts).write(to: url(documentId: documentId), options: .atomic)
    }

    /// Brouillons après insertion de `offset` pages **avant** le document (fonction pure, pour PageShift).
    public static func shifted(_ drafts: [Int: String], by offset: Int) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: drafts.map { ($0.key + offset, $0.value) })
    }

    /// Brouillons suivant une modification des pages (#49). Ceux des pages retirées ne sont pas dans le résultat :
    /// l'appelant les archive avant (le fichier d'origine est gardé dans la copie de l'opération).
    public static func remapped(_ drafts: [Int: String], with mapping: PageMapping) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: drafts.compactMap { page, text in mapping.target(of: page).map { ($0, text) } })
    }

    /// Format disque versionné : `{"version":1,"pages":{"3":"texte"}}`.
    private struct File: Codable {
        var version: Int
        var pages: [String: String]
    }

    public static func decode(_ data: Data) throws -> [Int: String] {
        let file = try JSONDecoder().decode(File.self, from: data)
        var result: [Int: String] = [:]
        for (key, text) in file.pages {
            guard let page = Int(key) else { throw CocoaError(.coderInvalidValue) }
            result[page] = text
        }
        return result
    }

    public static func encode(_ drafts: [Int: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(File(version: 1, pages: Dictionary(uniqueKeysWithValues: drafts.map { (String($0.key), $0.value) })))
    }
}
