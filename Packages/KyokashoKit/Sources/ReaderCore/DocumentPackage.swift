// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GRDB
import ZIPFoundation

/// Paquet d'un document complet (`.kyokasho`), demande de NOxygen59 du 29/10/2026 (plan `PLAN-EXPORT-COMPLET.md`) :
/// le PDF exact et tout ce que l'app a produit **pour ce document** (fiche, annotations, OCR et retouches, identités
/// des pages, lectures IA et traductions, rapport d'analyse, brouillons, réglages du document), pour le retrouver tel
/// quel sur un autre appareil. Choix de NOxygen59 : ni cartes, ni réglages de l'app, ni conversations du chat.
///
/// Contenu du zip (aucun autre chemin n'est accepté à l'ouverture) :
/// `manifest.json`, `document.pdf`, `database.json`, `drafts.json`, `preferences.json`, `report.json` (s'il existe) et
/// `analysis/<fichier>` (lectures IA et traductions). Le manifeste donne l'empreinte SHA-256 de chaque autre fichier :
/// un paquet modifié ou mal assemblé est refusé sans rien toucher. L'identifiant du document est l'empreinte du PDF
/// **importé** ; après un ajout ou une suppression de pages (#49), le PDF change et l'identifiant reste (recette 68).
/// Le PDF du paquet doit donc correspondre à la fiche du document (même taille), pas à son identifiant.
public enum DocumentPackage {
    public static let fileExtension = "kyokasho"
    public static let formatVersion = 1
    /// Tables exportées, dans l'ordre d'installation (`document` d'abord : les autres s'y rattachent). Les opérations
    /// de pages et leurs archives (#49) restent sur l'appareil : leurs copies de 30 jours n'en font pas partie.
    public static let tables = ["document", "pageTransform", "highlight", "inkDrawing", "bookmark", "pageComment",
                                "ocrResult", "pageIdentity"]

    public struct Manifest: Codable, Equatable, Sendable {
        public var formatVersion: Int
        public var appVersion: String
        public var documentId: String
        public var title: String
        public var pageCount: Int
        public var createdAt: Date
        /// Chemin dans le paquet → SHA-256.
        public var files: [String: String]
        /// Dictionnaires installés sur l'appareil d'origine (à retélécharger depuis le catalogue, jamais inclus).
        public var dictionaries: [String]
    }

    /// Ce que l'app fournit à l'export, et ce qu'elle reçoit à l'import (fichiers extraits dans un dossier privé).
    public struct Contents: Sendable {
        public var manifest: Manifest
        public var pdf: URL
        public var rows: [String: [[String: AppDatabase.ArchivedValue]]]
        /// Nom de fichier → fichier extrait (lectures IA et traductions).
        public var analysisFiles: [String: URL]
        public var report: URL?
        public var drafts: [Int: String]
        public var preferences: [String: String]
    }

    public struct PackageError: LocalizedError, Equatable {
        public let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    // MARK: - Écriture

    /// Écrit le paquet `zip`. `analysisFolder` : dossier des lectures IA du document (fichiers seulement).
    public static func write(to zip: URL, documentId: String, title: String, pageCount: Int, appVersion: String,
                             pdf: URL, rows: [String: [[String: AppDatabase.ArchivedValue]]], analysisFolder: URL?,
                             report: URL?, drafts: [Int: String], preferences: [String: String],
                             dictionaries: [String], at date: Date = Date()) throws {
        guard try matches(pdf: pdf, rows: rows, documentId: documentId) else {
            throw PackageError(String(localized: "Le PDF ne correspond plus au document : export annulé.", bundle: .main))
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        let archive = try Archive(url: zip, accessMode: .create)
        var hashes: [String: String] = [:]
        func add(_ path: String, file: URL) throws {
            hashes[path] = try DocumentImporter.sha256(of: file)
            try archive.addEntry(with: path, fileURL: file, compressionMethod: path == "document.pdf" ? .none : .deflate)
        }
        func add(_ path: String, data: Data) throws {
            let folder = fm.temporaryDirectory.appendingPathComponent("PackageWrite-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: folder) }
            let file = folder.appendingPathComponent("data")
            try data.write(to: file)
            try add(path, file: file)
        }
        try add("document.pdf", file: pdf)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try add("database.json", data: encoder.encode(rows))
        try add("drafts.json", data: encoder.encode(Dictionary(uniqueKeysWithValues: drafts.map { (String($0.key), $0.value) })))
        try add("preferences.json", data: encoder.encode(preferences))
        if let report, fm.fileExists(atPath: report.path) { try add("report.json", file: report) }
        if let analysisFolder, let names = try? fm.contentsOfDirectory(atPath: analysisFolder.path) {
            for name in names.sorted() where safeName(name) {
                let url = analysisFolder.appendingPathComponent(name)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                try add("analysis/" + name, file: url)
            }
        }
        let manifest = Manifest(formatVersion: formatVersion, appVersion: appVersion, documentId: documentId, title: title,
                                pageCount: pageCount, createdAt: date, files: hashes, dictionaries: dictionaries)
        let data = try encoder.encode(manifest)
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    // MARK: - Lecture

    /// Ouvre et vérifie le paquet, extrait dans `folder` (vide, privé). Refus avant toute modification de l'app si :
    /// format inconnu, chemin inattendu, lien, fichier manquant ou en trop, empreinte fausse, PDF ≠ identifiant.
    public static func open(_ zip: URL, into folder: URL) throws -> Contents {
        let fm = FileManager.default
        let archive: Archive
        do { archive = try Archive(url: zip, accessMode: .read) } catch { throw PackageError(String(localized: "Ce fichier n'est pas un paquet Kyōkasho.", bundle: .main)) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var extracted: [String: URL] = [:]
        for entry in archive {
            let path = entry.path
            guard entry.type == .file, allowedPath(path), extracted[path] == nil else {
                throw PackageError(String(localized: "Paquet invalide : élément inattendu « \(path) ».", bundle: .main))
            }
            let target = folder.appendingPathComponent(path.replacingOccurrences(of: "/", with: "__"))
            _ = try archive.extract(entry, to: target, skipCRC32: false)
            extracted[path] = target
        }
        guard let manifestURL = extracted["manifest.json"],
              let manifest = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) else {
            throw PackageError(String(localized: "Paquet invalide : fiche absente ou illisible.", bundle: .main))
        }
        guard manifest.formatVersion <= formatVersion else {
            throw PackageError(String(localized: "Ce paquet vient d'une version plus récente de Kyōkasho : mets l'app à jour.", bundle: .main))
        }
        var listed = extracted
        listed["manifest.json"] = nil
        guard Set(listed.keys) == Set(manifest.files.keys) else {
            throw PackageError(String(localized: "Paquet incomplet ou modifié : fichiers différents de sa fiche.", bundle: .main))
        }
        for (path, url) in listed where try DocumentImporter.sha256(of: url) != manifest.files[path] {
            throw PackageError(String(localized: "Paquet modifié : « \(path) » ne correspond pas à son empreinte.", bundle: .main))
        }
        guard let pdf = listed["document.pdf"], let database = listed["database.json"], let drafts = listed["drafts.json"],
              let preferences = listed["preferences.json"] else {
            throw PackageError(String(localized: "Paquet incomplet : PDF ou données du document absents.", bundle: .main))
        }
        let rows = try JSONDecoder().decode([String: [[String: AppDatabase.ArchivedValue]]].self, from: Data(contentsOf: database))
        guard try matches(pdf: pdf, rows: rows, documentId: manifest.documentId) else {
            throw PackageError(String(localized: "Paquet incohérent : le PDF ne correspond pas à la fiche du document.", bundle: .main))
        }
        let draftPages = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: drafts))
        var draftValues: [Int: String] = [:]
        for (key, text) in draftPages {
            guard let page = Int(key), page >= 0, page < manifest.pageCount else { throw PackageError(String(localized: "Paquet invalide : brouillon hors du document.", bundle: .main)) }
            draftValues[page] = text
        }
        var analysis: [String: URL] = [:]
        for (path, url) in listed where path.hasPrefix("analysis/") { analysis[String(path.dropFirst("analysis/".count))] = url }
        return Contents(manifest: manifest, pdf: pdf, rows: rows, analysisFiles: analysis, report: listed["report.json"],
                        drafts: draftValues,
                        preferences: try JSONDecoder().decode([String: String].self, from: Data(contentsOf: preferences)))
    }

    /// Le PDF est celui de la fiche `document` du paquet : une seule fiche, du bon identifiant, de la même taille
    /// (tenue à jour par chaque modification des pages). Les empreintes du manifeste garantissent le reste.
    static func matches(pdf: URL, rows: [String: [[String: AppDatabase.ArchivedValue]]], documentId: String) throws -> Bool {
        guard let fiches = rows["document"], fiches.count == 1, fiches[0]["id"] == .text(documentId),
              case .integer(let expected)? = fiches[0]["fileSize"] else { return false }
        return Int64(try pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1) == expected
    }

    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\") && name != ".."
    }

    static func allowedPath(_ path: String) -> Bool {
        if ["manifest.json", "document.pdf", "database.json", "drafts.json", "preferences.json", "report.json"].contains(path) { return true }
        guard path.hasPrefix("analysis/") else { return false }
        return safeName(String(path.dropFirst("analysis/".count)))
    }
}

// MARK: - Base

extension AppDatabase {
    /// Lignes du document pour un paquet : toutes les colonnes, valeurs SQLite telles quelles (blobs, NULL).
    public func packageRows(documentId: String) throws -> [String: [[String: ArchivedValue]]] {
        try writer.read { db in
            var out: [String: [[String: ArchivedValue]]] = [:]
            for table in DocumentPackage.tables {
                let key = table == "document" ? "id" : "documentId"
                out[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table) WHERE \(key) = ?", arguments: [documentId]).map { row in
                    // Le dossier de l'accueil reste sur l'appareil (DEC-T5-06) : `folder` n'est pas exporté, et un
                    // `folderId` inconnu ferait refuser le paquet à l'installation (clé étrangère).
                    Dictionary(uniqueKeysWithValues: row.columnNames.filter { !(table == "document" && $0 == "folderId") }
                        .map { ($0, ArchivedValue(row[$0] as DatabaseValue)) })
                }
            }
            guard out["document"]?.count == 1 else { throw DocumentPackage.PackageError(String(localized: "Document introuvable.", bundle: .main)) }
            return out
        }
    }

    /// Installe les lignes d'un paquet, en **une** transaction. Document déjà présent : refus, sauf `replacing` (ses
    /// lignes actuelles sont alors effacées dans la même transaction ; l'app a fait une copie de sécurité avant). Toute
    /// ligne d'un autre document, table ou colonne inconnue (paquet plus récent) arrête tout sans rien modifier.
    public func installPackage(documentId: String, rows: [String: [[String: ArchivedValue]]], replacing: Bool) throws {
        try writer.write { db in
            guard Set(rows.keys).isSubset(of: DocumentPackage.tables), rows["document"]?.count == 1 else {
                throw DocumentPackage.PackageError(String(localized: "Données du paquet invalides.", bundle: .main))
            }
            // Remplacement : le document garde son dossier de cet appareil (DEC-T5-06).
            var keptFolder: String?
            if try LibraryDocument.exists(db, key: documentId) {
                guard replacing else { throw DocumentPackage.PackageError(String(localized: "Ce document est déjà dans la bibliothèque.", bundle: .main)) }
                keptFolder = try String.fetchOne(db, sql: "SELECT folderId FROM document WHERE id = ?", arguments: [documentId])
                _ = try LibraryDocument.deleteOne(db, key: documentId) // Cascade : annotations, OCR, identités, opérations.
            }
            for table in DocumentPackage.tables {
                let known = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String })
                let key = table == "document" ? "id" : "documentId"
                for var values in rows[table] ?? [] {
                    // Paquet d'une autre version qui aurait exporté le dossier : ignoré, jamais une clé étrangère cassée.
                    if table == "document" { values["folderId"] = nil }
                    guard values[key] == .text(documentId) else {
                        throw DocumentPackage.PackageError(String(localized: "Le paquet contient des données d'un autre document.", bundle: .main))
                    }
                    guard Set(values.keys).isSubset(of: known) else {
                        throw DocumentPackage.PackageError(String(localized: "Ce paquet vient d'une version plus récente de Kyōkasho : mets l'app à jour.", bundle: .main))
                    }
                    let names = values.keys.sorted()
                    try db.execute(sql: "INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(names.map { _ in "?" }.joined(separator: ", ")))",
                                   arguments: StatementArguments(names.map { values[$0]!.databaseValue }))
                }
            }
            if let keptFolder {
                try db.execute(sql: "UPDATE document SET folderId = ? WHERE id = ? AND EXISTS (SELECT 1 FROM folder WHERE id = ?)",
                               arguments: [keptFolder, documentId, keptFolder])
            }
        }
    }
}
