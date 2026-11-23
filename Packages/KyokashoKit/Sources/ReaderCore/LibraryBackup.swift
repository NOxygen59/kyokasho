// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB
import ZIPFoundation

/// Sauvegarde complète de la bibliothèque (#51, étape C1 ; plan `PLAN-SAUVEGARDE-CLOUD.md` § 6, décisions de NOxygen59
/// du 29/10/2026) : un zip `.kyokasho-sauvegarde` avec les bases, copiées par l'API de sauvegarde SQLite (cohérentes
/// app ouverte, jamais une copie brute pendant le WAL), et les dossiers et fichiers que l'app désigne. Les modèles
/// d'IA, caches, fichiers temporaires et identifiants du Trousseau n'en font jamais partie : l'app ne les passe pas.
///
/// Cette partie ne connaît pas les emplacements de l'app : l'appelant fournit la liste (`Source`). Elle garantit le
/// format : chemins sûrs, aucun lien symbolique, une empreinte SHA-256 par fichier, vérification complète avant
/// toute restauration.
public enum LibraryBackup {
    public static let fileExtension = "kyokasho-sauvegarde"
    public static let formatVersion = 1

    public struct Manifest: Codable, Equatable, Sendable {
        public var formatVersion: Int
        public var appVersion: String
        public var createdAt: Date
        /// Comptes affichés avant une restauration (documents, cartes, notes…).
        public var counts: [String: Int]
        /// Chemin dans la sauvegarde → SHA-256.
        public var files: [String: String]
        /// Chemins des bases SQLite dans la sauvegarde (vérifiées à l'ouverture).
        public var databases: [String]
        /// Modèles installés sur l'appareil d'origine, à retélécharger (jamais inclus).
        public var models: [String]
    }

    /// Ce que l'app sauvegarde. Les chemins dans la sauvegarde sont relatifs (`kyokasho/kyokasho.sqlite`, `pdf/`…).
    public struct Source {
        public var databases: [(path: String, writer: any DatabaseWriter)]
        public var folders: [(path: String, url: URL)]
        public var files: [(path: String, url: URL)]
        public var counts: [String: Int]
        public var models: [String]
        /// Chemins de sauvegarde exclus des dossiers (préfixes : `kyokasho/Models` exclut tout ce dossier).
        public var excluded: [String]

        public init(databases: [(path: String, writer: any DatabaseWriter)], folders: [(path: String, url: URL)],
                    files: [(path: String, url: URL)], counts: [String: Int], models: [String], excluded: [String] = []) {
            self.databases = databases
            self.folders = folders
            self.files = files
            self.counts = counts
            self.models = models
            self.excluded = excluded
        }
    }

    public struct BackupError: LocalizedError, Equatable {
        public let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// Un chemin de sauvegarde : relatif, sans `..`, `.` ni composant vide ou caché, sans `\`.
    static func safePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.contains("\\") && !path.hasPrefix("/")
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
    }

    // MARK: - Écriture

    /// Écrit la sauvegarde dans `zip` (remplacé s'il existe), puis la relit et la vérifie entièrement. Un dossier
    /// absent est simplement vide ; un lien symbolique ou un chemin dangereux arrête tout.
    /// `progress(fait, total)` (recette 1.5.6, 4.2) : fichiers écrits sur le total, au plus une fois par point de
    /// pourcentage, appelé depuis le fil de l'écriture ; la relecture finale n'est pas comptée.
    public static func write(_ source: Source, to zip: URL, appVersion: String, at date: Date = Date(),
                             progress: ((Int, Int) -> Void)? = nil) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("BackupWrite-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        let archive = try Archive(url: zip, accessMode: .create)
        var hashes: [String: String] = [:]
        // Fichiers des dossiers listés d'abord : le total est connu avant la première écriture (même ordre qu'avant).
        var folderEntries: [(String, URL)] = []
        for folder in source.folders {
            for (relative, url) in try regularFiles(in: folder.url) {
                let path = folder.path + "/" + relative
                // Les bases SQLite ne passent que par l'API de sauvegarde (`databases`) : jamais leur fichier brut,
                // ni leurs fichiers annexes du WAL.
                guard !isSQLiteFile(url.lastPathComponent),
                      !source.excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
                folderEntries.append((path, url))
            }
        }
        let presentFiles = source.files.filter { fm.fileExists(atPath: $0.url.path) }
        let total = source.databases.count + presentFiles.count + folderEntries.count
        var done = 0, reported = -1
        func add(_ path: String, file: URL) throws {
            guard safePath(path), hashes[path] == nil else { throw BackupError(String(localized: "Chemin de sauvegarde invalide : \(path)", bundle: .main)) }
            hashes[path] = try DocumentImporter.sha256(of: file)
            try archive.addEntry(with: path, fileURL: file, compressionMethod: path.hasSuffix(".pdf") ? .none : .deflate)
            done += 1
            if let progress, done * 100 / max(total, 1) != reported {
                reported = done * 100 / max(total, 1)
                progress(done, total)
            }
        }
        for (index, database) in source.databases.enumerated() {
            let copy = work.appendingPathComponent("db-\(index).sqlite")
            let destination = try DatabaseQueue(path: copy.path)
            try database.writer.backup(to: destination)
            // La copie hérite du mode WAL de la base de l'app : la remettre en un seul fichier, autonome (lisible en
            // lecture seule à la vérification ; l'app la rouvre en WAL elle-même après une restauration).
            try destination.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = DELETE") }
            try destination.close()
            try add(database.path, file: copy)
        }
        for file in presentFiles {
            try checkRegular(file.url)
            try add(file.path, file: file.url)
        }
        for (path, url) in folderEntries {
            try add(path, file: url)
        }
        let manifest = Manifest(formatVersion: formatVersion, appVersion: appVersion, createdAt: date, counts: source.counts,
                                files: hashes, databases: source.databases.map(\.path), models: source.models)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
        // Relue tout de suite : une sauvegarde qu'on ne sait pas rouvrir ne protège rien.
        let check = work.appendingPathComponent("check", isDirectory: true)
        _ = try open(zip, into: check)
    }

    private static func checkRegular(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw BackupError(String(localized: "Élément inattendu (lien ou fichier spécial) : sauvegarde arrêtée.", bundle: .main))
        }
    }

    /// Fichiers ordinaires d'un dossier, triés, chemins relatifs ; les fichiers cachés (`.DS_Store`, fichiers de
    /// passage `.package-…`) sont ignorés, un lien symbolique arrête tout.
    static func regularFiles(in folder: URL) throws -> [(String, URL)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [] }
        var out: [(String, URL)] = []
        func visit(_ url: URL, _ relative: String) throws {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true else { throw BackupError(String(localized: "Lien symbolique dans « \(relative) » : sauvegarde arrêtée.", bundle: .main)) }
            if values.isDirectory == true {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    where !child.lastPathComponent.hasPrefix(".") {
                    try visit(child, relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            } else if values.isRegularFile == true {
                out.append((relative, url))
            } else {
                throw BackupError(String(localized: "Fichier spécial dans « \(relative) » : sauvegarde arrêtée.", bundle: .main))
            }
        }
        try visit(folder, "")
        return out
    }

    static func isSQLiteFile(_ name: String) -> Bool {
        [".sqlite", ".sqlite-wal", ".sqlite-shm", ".sqlite-journal"].contains { name.hasSuffix($0) }
    }

    /// Nom d'une sauvegarde : `Kyokasho-AAAA-MM-JJ-HHMMSS.kyokasho-sauvegarde` (tri par nom = tri par date).
    public static func fileName(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Kyokasho-\(f.string(from: date)).\(fileExtension)"
    }

    /// Fichier produit par Kyōkasho : bon nom, et zip qui contient une fiche. Rien d'autre n'est jamais effacé.
    public static func isBackup(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("Kyokasho-"), url.pathExtension == fileExtension,
              let archive = try? Archive(url: url, accessMode: .read) else { return false }
        return archive["manifest.json"] != nil
    }

    /// Garde les `keep` sauvegardes les plus récentes du dossier (choix de NOxygen59 : 10) et efface les plus anciennes,
    /// **seulement** parmi les fichiers reconnus par `isBackup`. Renvoie les fichiers effacés.
    @discardableResult
    public static func rotate(in folder: URL, keep: Int) throws -> [URL] {
        let fm = FileManager.default
        let backups = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter(isBackup).sorted { $0.lastPathComponent > $1.lastPathComponent }
        let old = Array(backups.dropFirst(max(keep, 1)))
        for url in old { try fm.removeItem(at: url) }
        return old
    }

    // MARK: - Lecture

    /// Extrait et vérifie la sauvegarde dans `folder` (vide, privé), sans rien toucher à l'app. Refus si : élément au
    /// chemin dangereux ou en double, fiche absente ou plus récente, fichiers différents de la fiche, empreinte fausse,
    /// base SQLite illisible ou qui échoue `PRAGMA integrity_check`.
    public static func open(_ zip: URL, into folder: URL) throws -> Manifest {
        let fm = FileManager.default
        let archive: Archive
        do { archive = try Archive(url: zip, accessMode: .read) } catch { throw BackupError(String(localized: "Ce fichier n'est pas une sauvegarde Kyōkasho.", bundle: .main)) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var extracted: [String: URL] = [:]
        for entry in archive {
            let path = entry.path
            guard entry.type == .file, safePath(path), extracted[path] == nil else {
                throw BackupError(String(localized: "Sauvegarde invalide : élément inattendu « \(path) ».", bundle: .main))
            }
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: url)
            extracted[path] = url
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifestURL = extracted.removeValue(forKey: "manifest.json"),
              let manifest = try? decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL)) else {
            throw BackupError(String(localized: "Sauvegarde invalide : fiche absente ou illisible.", bundle: .main))
        }
        guard manifest.formatVersion <= formatVersion else {
            throw BackupError(String(localized: "Cette sauvegarde vient d'une version plus récente de Kyōkasho : mets l'app à jour.", bundle: .main))
        }
        guard Set(extracted.keys) == Set(manifest.files.keys), Set(manifest.databases).isSubset(of: extracted.keys) else {
            throw BackupError(String(localized: "Sauvegarde incomplète ou modifiée : fichiers différents de sa fiche.", bundle: .main))
        }
        for (path, url) in extracted where try DocumentImporter.sha256(of: url) != manifest.files[path] {
            throw BackupError(String(localized: "Sauvegarde modifiée : « \(path) » ne correspond pas à son empreinte.", bundle: .main))
        }
        for path in manifest.databases {
            var readOnly = Configuration()
            readOnly.readonly = true
            let ok = try? DatabaseQueue(path: extracted[path]!.path, configuration: readOnly).read { db in
                try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok"
            }
            guard ok == true else { throw BackupError(String(localized: "Base « \(path) » abîmée dans la sauvegarde.", bundle: .main)) }
        }
        return manifest
    }
}
