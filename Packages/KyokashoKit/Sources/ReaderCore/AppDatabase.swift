// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import Foundation
import GRDB

/// Base SQLite de l'app (GRDB). Fichier : mode WAL (`DatabasePool`) → lectures concurrentes,
/// écritures sans bloquer l'interface. Tests : base en mémoire.
public final class AppDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Base sur disque.
    public static func open(at url: URL) throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            // Cache de pages plus généreux et E/S mappées en mémoire : lectures plus rapides.
            try db.execute(sql: "PRAGMA cache_size = -16000")   // ~16 Mo
            try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256 Mo
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path, configuration: config))
    }

    /// Base en mémoire (tests, aperçus).
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "document") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("originalFileName", .text).notNull()
                t.column("pageCount", .integer).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("importedAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime)
                t.column("lastPageIndex", .integer).notNull().defaults(to: 0)
                t.column("settingsJSON", .text)
                t.column("driveFileId", .text).indexed()
                t.column("driveRevision", .text)
            }
            try db.create(table: "pageTransform") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("rotation", .integer).notNull().defaults(to: 0)
                t.column("split", .boolean).notNull().defaults(to: false)
                t.column("autoCrop", .text)
                t.primaryKey(["documentId", "pageIndex"])
            }
            try db.create(table: "highlight") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("rectsJSON", .text).notNull()
                t.column("color", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "highlight_page", on: "highlight", columns: ["documentId", "pageIndex"])
            try db.create(table: "inkDrawing") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("data", .blob).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.primaryKey(["documentId", "pageIndex"])
            }
            try db.create(table: "bookmark") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "bookmark_doc", on: "bookmark", columns: ["documentId", "pageIndex"])
            try db.create(table: "pageComment") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("body", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "pageComment_doc", on: "pageComment", columns: ["documentId", "pageIndex"])
            try db.create(table: "aiPrompt") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("position", .integer).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            for prompt in AIPrompt.defaults { try prompt.insert(db) }
        }
        m.registerMigration("v2-ocr") { db in
            // Cache OCR : une ligne par (document, page source, moteur). Changer de moteur n'efface rien.
            try db.create(table: "ocrResult") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("pageIndex", .integer).notNull()
                t.column("engine", .text).notNull()
                t.column("json", .blob).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["documentId", "pageIndex", "engine"])
            }
            try db.create(table: "benchSample") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("imageFile", .text).notNull()
                t.column("referenceText", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "benchRun") { t in
                t.primaryKey("id", .text)
                t.column("sampleId", .text).notNull().references("benchSample", onDelete: .cascade)
                t.column("engine", .text).notNull()
                t.column("cer", .double).notNull()
                t.column("durationMs", .integer).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "benchRun_sample", on: "benchRun", columns: ["sampleId", "engine"])
        }
        m.registerMigration("v3-page-one") { db in
            try db.alter(table: "document") { t in
                t.add(column: "firstPageIndex", .integer).notNull().defaults(to: 0)
            }
        }
        m.registerMigration("v4-note-canvas-anchor") { db in
            try db.alter(table: "pageComment") { t in
                t.add(column: "drawing", .blob)
                t.add(column: "anchorX", .double)
                t.add(column: "anchorY", .double)
                t.add(column: "anchorWidth", .double)
                t.add(column: "anchorHeight", .double)
                t.add(column: "anchorText", .text)
            }
        }
        // Colonne facultative (NULL = non classé) : les documents existants ne changent pas (RET-039, #54).
        m.registerMigration("v5-document-category") { db in
            try db.alter(table: "document") { t in
                t.add(column: "category", .text)
            }
        }
        m.registerMigration("v5-page-edits") { db in
            // Modifications des pages (#49) : voir AppDatabase+PageEdits.swift.
            try db.alter(table: "document") { t in
                t.add(column: "layoutVersion", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "pageIdentity") { t in
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("position", .integer).notNull()
                t.column("pageId", .text).notNull()
                t.column("printedNumber", .integer)
                t.primaryKey(["documentId", "position"])
                t.uniqueKey(["documentId", "pageId"])
            }
            try db.create(table: "pageEdit") { t in
                t.primaryKey("id", .text)
                t.column("documentId", .text).notNull().references("document", onDelete: .cascade, onUpdate: .cascade)
                t.column("kind", .text).notNull()
                t.column("versionBefore", .integer).notNull()
                t.column("versionAfter", .integer).notNull()
                t.column("appliedAt", .datetime).notNull()
                t.column("mappingJSON", .blob).notNull()
                t.column("pageOrderJSON", .blob).notNull()
                // Suppression seulement : opération qui l'a restaurée, ou date de l'effacement de son archive (30 j).
                // Ajoutées avant toute livraison de cette migration (branche locale) : pas de migration séparée.
                t.column("restoredBy", .text)
                t.column("purgedAt", .datetime)
            }
            try db.create(index: "pageEdit_doc", on: "pageEdit", columns: ["documentId", "appliedAt"])
            try db.create(table: "pageEditRow") { t in
                t.column("editId", .text).notNull().references("pageEdit", onDelete: .cascade)
                t.column("tableName", .text).notNull()
                t.column("pageId", .text).notNull()
                t.column("rowJSON", .blob).notNull()
            }
            try db.create(index: "pageEditRow_edit", on: "pageEditRow", columns: ["editId"])
        }
        return m
    }
}

// MARK: - Documents

extension AppDatabase {
    public func allDocuments() throws -> [LibraryDocument] {
        try writer.read { db in
            try LibraryDocument.order(sql: "COALESCE(lastOpenedAt, importedAt) DESC").fetchAll(db)
        }
    }

    public func document(id: String) throws -> LibraryDocument? {
        try writer.read { db in try LibraryDocument.fetchOne(db, key: id) }
    }

    public func save(_ document: LibraryDocument) throws {
        try writer.write { db in try document.save(db) }
    }

    /// Change seulement l'espace du document, dans une transaction : ses autres réglages ne sont pas réécrits.
    public func updateMangaSpace(documentId: String, inManga: Bool) throws {
        try writer.write { db in
            guard var document = try LibraryDocument.fetchOne(db, key: documentId) else { return }
            var settings = document.settingsOverride
            settings.mangaSpace = inManga ? true : nil
            document.settingsOverride = settings
            try db.execute(sql: "UPDATE document SET settingsJSON = ? WHERE id = ?", arguments: [document.settingsJSON, documentId])
        }
    }

    /// Document et correspondance d'archive enregistrés ensemble, ou pas du tout.
    func saveComic(_ document: LibraryDocument, sources: [String: String], sourcesKey: String) throws {
        try writer.write { db in
            try document.save(db)
            let json = String(decoding: try JSONEncoder.sorted.encode(sources), as: UTF8.self)
            try db.execute(sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [sourcesKey, json])
        }
    }

    public func deleteDocument(id: String) throws {
        try writer.write { db in _ = try LibraryDocument.deleteOne(db, key: id) }
    }

    /// Change seulement la catégorie (requête ciblée) : une copie du document gardée ailleurs ne l'écrase pas, et
    /// cette mise à jour n'écrase rien d'autre (RET-039, #54).
    public func updateCategory(documentId: String, category: DocumentCategory?) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET category = ? WHERE id = ?", arguments: [category?.rawValue, documentId])
        }
    }

    /// Enregistre la position de lecture (appelé souvent : requête minimale).
    public func updateReadingPosition(documentId: String, pageIndex: Int, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE document SET lastPageIndex = ?, lastOpenedAt = ? WHERE id = ?",
                           arguments: [pageIndex, date, documentId])
        }
    }

    /// Une nouvelle version d'un document (ex. cours mis à jour sur Drive) remplace l'ancienne :
    /// toutes les annotations suivent grâce aux clés étrangères `ON UPDATE CASCADE`.
    ///
    /// Décision DEC-C1 = A (10/11/2026) : après un remplacement, **tout l'OCR est relu**. L'ancienne
    /// version est un autre PDF : ses boîtes de caractères, ses corrections et son rognage automatique
    /// ne décriront jamais le contenu réel des nouvelles pages — les servir serait mentir à l'utilisateur
    /// (Lot C2.1, fiche f85d0c0). Les rotations et les coupures manuelles des pages restent : ce sont des
    /// choix de l'utilisateur, par page, pas des mesures du contenu. Effacement du cache OCR et remise
    /// à zéro du rognage automatique (un rognage calculé de l'ancienne version est faux) sont faits
    /// **dans la même transaction** que la bascule, pour les deux branches :
    /// - le document final est un renommage (`ON UPDATE CASCADE` suit le renommage : le cache à effacer
    ///   est donc celui du nouvel identifiant, après lui) ;
    /// - le document final existait déjà (fusion) : la suppression en cascade emporte l'OCR de l'ancien
    ///   identifiant, celui du survivant est effacé par la requête qui suit.
    ///
    /// Types des « mises de côté » d'une bascule. `pageJSON` est le résultat OCR brut tel qu'en
    /// base : seul l'appelant (qui connaît le format, `OCRKit`) sait y repérer les lignes
    /// corrigées à la main (`OCRLine.originalText`) et les écrire de côté.
    public typealias AsideCorrections =
        (_ sourceDocumentId: String, _ newDocumentId: String, _ pageIndex: Int, _ engine: String, _ pageJSON: Data) throws -> Void

    /// Si l'identifiant ne change pas (`oldId == newDocument.id`) le contenu n'a pas varié : ce n'est
    /// pas un remplacement, aucun cache valable ne doit être effacé.
    ///
    /// - Parameter asideCorrections: DEC-C3 (10/11/2026) — appelé pour **chaque** résultat OCR
    ///   avant tout changement (renommage compris : les lignes deviendront celles du nouvel
    ///   identifiant, puis partiront avec l'effacement ; fusion incluse, les deux versions
    ///   partiront). Les lignes corrigées à la main y sont extraites et écrites dans
    ///   `Corrections-remplacement/…`, jamais écrasées.
    public func rekeyDocument(from oldId: String, to newDocument: LibraryDocument,
                              asideCorrections: AsideCorrections? = nil) throws {
        try writer.write { db in
            if oldId != newDocument.id {
                // DEC-C3 : AVANT la bascule et l'effacement, tous les résultats OCR des deux
                // identifiants sont proposés à l'appelant (un résultat illisible interrompt
                // l'opération : les corrections manuelles seraient perdues sans lui). Jamais
                // rejoué : la reprise ne repasse par ici qu'après une bascule annulée, où rien
                // manquait encore (l'ancien document existait toujours).
                for record in try OCRResultRecord
                    .filter(sql: "documentId = ? OR documentId = ?", arguments: [oldId, newDocument.id])
                    .fetchAll(db) {
                    try asideCorrections?(record.documentId, newDocument.id, record.pageIndex, record.engine, record.json)
                }
                if try LibraryDocument.exists(db, key: newDocument.id) {
                    // La nouvelle version existe déjà : on y rattache les annotations de l'ancienne.
                    //
                    // P3 n°9 (revue R2) — rotation et coupure **manuelles** : une page n'attend
                    // qu'un réglage, les deux versions font donc concurrence ; le choix est fait
                    // et documenté : le réglage du livre **remplacé** gagne, parce que c'est la
                    // fiche que l'utilisateur entretient et met à jour (le survivant n'est qu'un
                    // doublon du même fichier, reconnu à sa même empreinte). La ligne du
                    // survivant est retirée d'abord, celle du document remplacé la reprend ;
                    // les autres tables gardent `UPDATE OR IGNORE` : plusieurs annotations
                    // par page peuvent coexister.
                    try db.execute(sql: "DELETE FROM pageTransform WHERE documentId = ? AND pageIndex IN (SELECT pageIndex FROM pageTransform WHERE documentId = ?)",
                                   arguments: [newDocument.id, oldId])
                    try db.execute(sql: "UPDATE pageTransform SET documentId = ? WHERE documentId = ?",
                                   arguments: [newDocument.id, oldId])
                    for table in ["highlight", "inkDrawing", "bookmark", "pageComment"] {
                        try db.execute(sql: "UPDATE OR IGNORE \(table) SET documentId = ? WHERE documentId = ?",
                                       arguments: [newDocument.id, oldId])
                    }
                    // Archives des pages retirées (#49) : gardées avec le document qui reste, jamais effacées en passant.
                    try db.execute(sql: "UPDATE pageEdit SET documentId = ? WHERE documentId = ?", arguments: [newDocument.id, oldId])
                    _ = try LibraryDocument.deleteOne(db, key: oldId)
                    // P3 n°9 (revue R2) : le survivant garde son titre, ses réglages, sa catégorie
                    // et sa position de lecture — la fiche qui reste décrit déjà le **fichier qui
                    // reste** (le PDF de l'arrivée est le même fichier que le survivant, reconnu à
                    // son empreinte) ; la fusion d'annotations d'un doublon ne justifie pas de
                    // l'écraser par la fiche remplacée. Seules les mesures du fichier réel et la
                    // révision Drive de l'opération suivent (la révision n'écrase jamais une
                    // valeur absente : aucune opération Drive dans ce cas).
                    if newDocument.driveRevision == nil {
                        try db.execute(sql: "UPDATE document SET pageCount = ?, fileSize = ? WHERE id = ?",
                                       arguments: [newDocument.pageCount, newDocument.fileSize, newDocument.id])
                    } else {
                        try db.execute(sql: "UPDATE document SET pageCount = ?, fileSize = ?, driveRevision = ? WHERE id = ?",
                                       arguments: [newDocument.pageCount, newDocument.fileSize, newDocument.driveRevision, newDocument.id])
                    }
                } else {
                    try db.execute(sql: "UPDATE document SET id = ? WHERE id = ?", arguments: [newDocument.id, oldId])
                    try newDocument.update(db)
                }
                // DEC-C1 = A : un remplacement oppose un PDF différent. Même transaction : le cache OCR
                // (boîtes de caractères et corrections incluses) est effacé et le rognage automatique
                // repart de zéro. Le rognage manuel (`rotation`, `split`) reste.
                try db.execute(sql: "DELETE FROM ocrResult WHERE documentId = ?", arguments: [newDocument.id])
                try db.execute(sql: "UPDATE pageTransform SET autoCrop = NULL WHERE documentId = ?", arguments: [newDocument.id])
            }
            // #49 (revue Codex F1) : un autre PDF n'a pas les mêmes pages, même s'il en a autant. Les identités sont
            // refaites à la prochaine modification des pages, et la version change sans opération enregistrée : la
            // chaîne des versions est rompue, donc une archive d'avant le remplacement n'est plus restaurable telle
            // quelle (S2/S3 le vérifient). Les archives elles-mêmes restent jusqu'à leur échéance.
            try db.execute(sql: "DELETE FROM pageIdentity WHERE documentId = ?", arguments: [newDocument.id])
            try db.execute(sql: "UPDATE document SET layoutVersion = layoutVersion + 1 WHERE id = ?", arguments: [newDocument.id])
        }
    }

    /// Publie la bibliothèque à chaque changement (pour l'interface).
    public func documentsPublisher() -> AnyPublisher<[LibraryDocument], Error> {
        ValueObservation
            .tracking { db in try LibraryDocument.order(sql: "COALESCE(lastOpenedAt, importedAt) DESC").fetchAll(db) }
            .publisher(in: writer, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

// MARK: - Réglages

extension AppDatabase {
    static let readerDefaultsKey = "reader.defaults"
    static let appSettingsKey = "app.settings"

    func value<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        try writer.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    func setValue<T: Encodable>(_ value: T, forKey key: String) throws {
        let json = String(decoding: try JSONEncoder.sorted.encode(value), as: UTF8.self)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                           arguments: [key, json])
        }
    }

    /// Valeur enregistrée sous `key` (réglages d'autres modules, ex. profils de dictionnaire).
    public func storedValue<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        try value(type, forKey: key)
    }

    public func setStoredValue<T: Encodable>(_ value: T, forKey key: String) throws {
        try setValue(value, forKey: key)
    }

    public func readerDefaults() throws -> ReaderSettings {
        try value(ReaderSettings.self, forKey: Self.readerDefaultsKey) ?? .default
    }

    public func setReaderDefaults(_ settings: ReaderSettings) throws {
        try setValue(settings, forKey: Self.readerDefaultsKey)
    }

    public func appSettings() throws -> AppSettings {
        try value(AppSettings.self, forKey: Self.appSettingsKey) ?? AppSettings()
    }

    public func setAppSettings(_ settings: AppSettings) throws {
        try setValue(settings, forKey: Self.appSettingsKey)
    }
}

// MARK: - Annotations

extension AppDatabase {
    public func pageTransforms(documentId: String) throws -> [Int: PageTransform] {
        try writer.read { db in
            let rows = try PageTransform.filter(Column("documentId") == documentId).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.pageIndex, $0) })
        }
    }

    public func save(_ transform: PageTransform) throws {
        try writer.write { db in try transform.save(db) }
    }

    /// Enregistre plusieurs transformations d'un coup (ex. rognages calculés en tâche de fond).
    public func save(_ transforms: [PageTransform]) throws {
        try writer.write { db in for t in transforms { try t.save(db) } }
    }

    /// Applique les rotations choisies et invalide, dans la même transaction, l'OCR des pages concernées.
    /// Les autres propriétés de la page (découpe, rognage) sont conservées.
    /// `keepingOCR` (JSON, ancienne rotation, nouvelle rotation) : JSON à garder pour un résultat, `nil` pour l'effacer.
    /// ReaderCore ne connaît pas le format OCR : `OCRPage.jsonKeepingManualEdits` protège les corrections manuelles.
    public func applyPageRotations(documentId: String, rotations: [Int: Int],
                                   keepingOCR: (Data, Int, Int) -> Data? = { _, _, _ in nil }) throws {
        guard !rotations.isEmpty else { return }
        try writer.write { db in
            for (page, value) in rotations {
                var transform = try PageTransform.fetchOne(db, key: ["documentId": documentId, "pageIndex": page])
                    ?? PageTransform(documentId: documentId, pageIndex: page)
                let previous = transform.rotation
                transform.rotation = PageTransform.normalizedRotation(value)
                try transform.save(db)
                let records = try OCRResultRecord.filter(Column("documentId") == documentId && Column("pageIndex") == page).fetchAll(db)
                for var record in records {
                    if let kept = keepingOCR(record.json, previous, transform.rotation) {
                        record.json = kept
                        try record.save(db)
                    } else {
                        try record.delete(db)
                    }
                }
            }
        }
    }

    public func highlights(documentId: String) throws -> [Highlight] {
        try writer.read { db in
            try Highlight.filter(Column("documentId") == documentId).order(Column("pageIndex"), Column("createdAt")).fetchAll(db)
        }
    }

    public func save(_ highlight: Highlight) throws {
        try writer.write { db in try highlight.save(db) }
    }

    public func deleteHighlight(id: String) throws {
        try writer.write { db in _ = try Highlight.deleteOne(db, key: id) }
    }

    public func inkDrawing(documentId: String, pageIndex: Int) throws -> InkDrawing? {
        try writer.read { db in
            try InkDrawing.fetchOne(db, key: ["documentId": documentId, "pageIndex": pageIndex])
        }
    }

    /// Pages qui ont un dessin (pour ne charger que celles-là).
    public func pagesWithInk(documentId: String) throws -> Set<Int> {
        try writer.read { db in
            Set(try Int.fetchAll(db, sql: "SELECT pageIndex FROM inkDrawing WHERE documentId = ?", arguments: [documentId]))
        }
    }

    /// Enregistre un dessin ; un dessin vide supprime la ligne.
    public func save(_ drawing: InkDrawing, isEmpty: Bool) throws {
        try writer.write { db in
            if isEmpty {
                _ = try InkDrawing.deleteOne(db, key: ["documentId": drawing.documentId, "pageIndex": drawing.pageIndex])
            } else {
                try drawing.save(db)
            }
        }
    }

    public func bookmarks(documentId: String) throws -> [Bookmark] {
        try writer.read { db in
            try Bookmark.filter(Column("documentId") == documentId).order(Column("pageIndex")).fetchAll(db)
        }
    }

    public func save(_ bookmark: Bookmark) throws {
        try writer.write { db in try bookmark.save(db) }
    }

    public func deleteBookmark(id: String) throws {
        try writer.write { db in _ = try Bookmark.deleteOne(db, key: id) }
    }

    /// Pages insérées **avant** les pages d'un document (« Ajouter des pages… ») : tout ce qui est rangé par numéro
    /// de page avance de `offset` (OCR, surlignages, dessins, repères, notes, transformations, position de lecture,
    /// page 1), puis nombre de pages et taille du PDF. Une seule transaction : tout ou rien. `offset` négatif =
    /// retour en arrière (opération interrompue). Les cartes sont dans `review.sqlite` : `ReviewStore.setSourcePages`.
    public func shiftPages(documentId: String, by offset: Int, pageCount: Int, fileSize: Int64,
                           expectedPageCount: Int? = nil) throws {
        try writer.write { db in
            if let expectedPageCount {
                let current = try LibraryDocument.fetchOne(db, key: documentId)?.pageCount
                if current == pageCount { return } // Effet déjà commis, journal encore présent.
                guard current == expectedPageCount else {
                    throw NSError(domain: "Kyokasho.PageShift", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nombre de pages inattendu en base.", bundle: .main)])
                }
            }
            if offset != 0 {
                // En deux temps (valeurs négatives puis positives) : jamais deux lignes sur la même clé.
                for table in ["ocrResult", "highlight", "inkDrawing", "bookmark", "pageComment", "pageTransform"] {
                    try db.execute(sql: "UPDATE \(table) SET pageIndex = -1 - (pageIndex + ?) WHERE documentId = ?",
                                   arguments: [offset, documentId])
                    try db.execute(sql: "UPDATE \(table) SET pageIndex = -1 - pageIndex WHERE documentId = ? AND pageIndex < 0",
                                   arguments: [documentId])
                }
            }
            try db.execute(sql: """
                UPDATE document SET pageCount = ?, fileSize = ?, lastPageIndex = lastPageIndex + ?,
                firstPageIndex = firstPageIndex + ? WHERE id = ?
                """, arguments: [pageCount, fileSize, offset, offset, documentId])
        }
    }

    public func comments(documentId: String) throws -> [PageComment] {
        try writer.read { db in
            try PageComment.filter(Column("documentId") == documentId).order(Column("pageIndex"), Column("createdAt")).fetchAll(db)
        }
    }

    public func save(_ comment: PageComment) throws {
        try writer.write { db in try comment.save(db) }
    }

    public func deleteComment(id: String) throws {
        try writer.write { db in _ = try PageComment.deleteOne(db, key: id) }
    }

    public func aiPrompts() throws -> [AIPrompt] {
        try writer.read { db in try AIPrompt.order(Column("position")).fetchAll(db) }
    }

    public func save(_ prompt: AIPrompt) throws {
        try writer.write { db in try prompt.save(db) }
    }

    public func deletePrompt(id: String) throws {
        try writer.write { db in _ = try AIPrompt.deleteOne(db, key: id) }
    }
}

// MARK: - OCR

extension AppDatabase {
    public func ocrResult(documentId: String, pageIndex: Int, engine: String) throws -> OCRResultRecord? {
        try writer.read { db in
            try OCRResultRecord.fetchOne(db, key: ["documentId": documentId, "pageIndex": pageIndex, "engine": engine])
        }
    }

    /// Tous les résultats OCR d'un document (recherche dans les pages scannées).
    public func ocrResults(documentId: String) throws -> [OCRResultRecord] {
        try writer.read { db in
            try OCRResultRecord.filter(Column("documentId") == documentId).order(Column("pageIndex")).fetchAll(db)
        }
    }

    /// Moteurs déjà passés sur une page (pour « Comparer » et l'affichage du moteur).
    public func ocrEngines(documentId: String, pageIndex: Int) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT engine FROM ocrResult WHERE documentId = ? AND pageIndex = ? ORDER BY createdAt",
                                arguments: [documentId, pageIndex])
        }
    }

    public func save(_ record: OCRResultRecord) throws {
        try writer.write { db in try record.save(db) }
    }

    /// Taille du cache OCR (octets) et nombre de résultats (une page peut avoir plusieurs moteurs).
    public func ocrCacheStats() throws -> (bytes: Int, results: Int) {
        try writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT COALESCE(SUM(LENGTH(json)), 0) AS b, COUNT(*) AS n FROM ocrResult")
            return (row?["b"] ?? 0, row?["n"] ?? 0)
        }
    }

    public func clearOCRCache(documentId: String? = nil) throws {
        try writer.write { db in
            if let documentId {
                try db.execute(sql: "DELETE FROM ocrResult WHERE documentId = ?", arguments: [documentId])
            } else {
                try db.execute(sql: "DELETE FROM ocrResult")
            }
        }
    }

    // MARK: Banc d'essai

    public func benchSamples() throws -> [BenchSample] {
        try writer.read { db in try BenchSample.order(Column("createdAt")).fetchAll(db) }
    }

    public func save(_ sample: BenchSample) throws {
        try writer.write { db in try sample.save(db) }
    }

    public func deleteBenchSample(id: String) throws {
        try writer.write { db in _ = try BenchSample.deleteOne(db, key: id) }
    }

    public func benchRuns(sampleId: String) throws -> [BenchRun] {
        try writer.read { db in
            try BenchRun.filter(Column("sampleId") == sampleId).order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Dernier essai de chaque (échantillon, moteur).
    public func latestBenchRuns() throws -> [BenchRun] {
        try writer.read { db in
            try BenchRun.fetchAll(db, sql: """
                SELECT r.* FROM benchRun r
                JOIN (SELECT sampleId, engine, MAX(createdAt) AS c FROM benchRun GROUP BY sampleId, engine) last
                ON r.sampleId = last.sampleId AND r.engine = last.engine AND r.createdAt = last.c
                """)
        }
    }

    public func save(_ run: BenchRun) throws {
        try writer.write { db in try run.save(db) }
    }
}
