// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Restauration d'une sauvegarde complète (#51, C1 ; plan `PLAN-SAUVEGARDE-CLOUD.md` § 6). Deux temps :
///
/// 1. **Préparer** (app ouverte, rien de modifié) : la sauvegarde est vérifiée et extraite dans
///    `Application Support/RestoreStaging/<id>/` par `LibraryBackup.open`, une sauvegarde de sécurité de l'état actuel
///    est faite, puis le marqueur `restore-pending.json` est écrit. L'app demande de la relancer.
/// 2. **Appliquer** au lancement suivant, **avant l'ouverture des bases** : chaque emplacement actuel est mis de côté
///    dans `RestoreOld/<id>/`, la version de la sauvegarde prend sa place (déplacements sur le même volume), les modèles
///    d'IA (absents des sauvegardes) reviennent dans le nouveau dossier, les réglages sont rétablis, puis tout ce qui
///    est mis de côté est effacé et le marqueur retiré en dernier.
///
/// Chaque étape se rejoue : une coupure à n'importe quel moment reprend au lancement suivant sans rien perdre, car
/// l'état se déduit de ce qui existe (actuel, mis de côté, préparé) et de la liste des emplacements du marqueur.
public enum LibraryRestore {
    public struct Marker: Codable, Equatable, Sendable {
        public var id: String
        public var createdAt: Date
        /// Nom du fichier de sauvegarde restauré (affichage).
        public var backupName: String
        /// Emplacements présents dans la sauvegarde préparée (`kyokasho`, `analysis`, `support/<fichier>`). Un
        /// emplacement absent de la sauvegarde est quand même vidé, pour ne pas mêler deux bibliothèques.
        public var staged: [String]
        /// Installation terminée (réglages compris) : un rejeu ne fait plus que le nettoyage, sans réappliquer les
        /// réglages de la sauvegarde par-dessus ceux modifiés depuis (revue Codex de e777c68).
        public var installed: Bool?

        public init(id: String, createdAt: Date, backupName: String, staged: [String], installed: Bool? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.backupName = backupName
            self.staged = staged
            self.installed = installed
        }
    }

    /// Résultat au lancement. `cleanupPending` : la bibliothèque restaurée est en place et utilisable, mais des copies
    /// mises de côté n'ont pas pu être effacées ; le marqueur reste pour réessayer au prochain lancement.
    public enum Outcome: Equatable { case nothing, restored(Marker), cleanupPending(Marker) }

    public struct RestoreError: LocalizedError, Equatable {
        public let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// Injection de panne pour les tests Mac ; nil dans l'app.
    public static var checkpoint: ((String) throws -> Void)?
    private static func hit(_ name: String) throws { try checkpoint?(name) }

    public static func markerURL(support: URL) -> URL { support.appendingPathComponent("restore-pending.json") }
    public static func stagingURL(support: URL, id: String) -> URL {
        support.appendingPathComponent("RestoreStaging", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }
    static func oldURL(support: URL, id: String) -> URL {
        support.appendingPathComponent("RestoreOld", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    /// Marqueur en attente. Absent : `nil`. Présent mais illisible : **erreur**, jamais « pas de restauration » :
    /// après une coupure, ouvrir la bibliothèque dans un état incomplet perdrait des données (revue Codex de e777c68).
    public static func pending(support: URL) throws -> Marker? {
        let url = markerURL(support: support)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(Marker.self, from: Data(contentsOf: url)) } catch {
            throw RestoreError(String(localized: "Marqueur de restauration illisible : restauration arrêtée, fichiers gardés.", bundle: .main))
        }
    }

    private static func save(_ marker: Marker, support: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(marker).write(to: markerURL(support: support), options: .atomic)
    }

    /// Dernière étape de la préparation : écrit le marqueur (la sauvegarde est déjà extraite et vérifiée dans le
    /// dossier de préparation). Les emplacements notés sont ceux réellement présents.
    public static func writeMarker(support: URL, id: String, backupName: String, date: Date = Date()) throws -> Marker {
        let staging = stagingURL(support: support, id: id)
        let fm = FileManager.default
        var staged: [String] = []
        for name in ["kyokasho", "analysis"] where fm.fileExists(atPath: staging.appendingPathComponent(name).path) { staged.append(name) }
        for name in (try? fm.contentsOfDirectory(atPath: staging.appendingPathComponent("support").path)) ?? [] where !name.hasPrefix(".") {
            staged.append("support/" + name)
        }
        guard staged.contains("kyokasho") else { throw RestoreError(String(localized: "Sauvegarde sans bibliothèque : restauration refusée.", bundle: .main)) }
        let marker = Marker(id: id, createdAt: date, backupName: backupName, staged: staged.sorted())
        try save(marker, support: support)
        return marker
    }

    /// Préparation abandonnée (ou refusée) : dossier de préparation effacé, rien d'autre touché.
    public static func cancel(support: URL) {
        guard let marker = try? pending(support: support), marker.installed != true else { return }
        try? FileManager.default.removeItem(at: stagingURL(support: support, id: marker.id))
        try? FileManager.default.removeItem(at: markerURL(support: support))
    }

    /// Applique la restauration en attente, s'il y en a une. `analysis` : dossier des lectures IA de l'app.
    /// `applyPreferences` reçoit les réglages sauvegardés (domaine UserDefaults). Renvoie le marqueur appliqué.
    @discardableResult
    public static func apply(support: URL, analysis: URL, applyPreferences: ([String: Any]) -> Void) throws -> Outcome {
        guard var marker = try pending(support: support) else { return .nothing }
        let fm = FileManager.default
        let staging = stagingURL(support: support, id: marker.id), old = oldURL(support: support, id: marker.id)
        if marker.installed != true {
            try install(marker, support: support, analysis: analysis, staging: staging, old: old, applyPreferences: applyPreferences)
            marker.installed = true
            try save(marker, support: support)
            try hit("marked")
        }
        // L'état d'avant a sa sauvegarde de sécurité (faite avant le marqueur) : il peut partir. Un échec garde le
        // marqueur pour réessayer au prochain lancement, sans bloquer la bibliothèque déjà en place.
        do {
            try hit("cleanup")
            for url in [old, staging] where fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            for parent in [old.deletingLastPathComponent(), staging.deletingLastPathComponent()]
                where ((try? fm.contentsOfDirectory(atPath: parent.path)) ?? ["?"]).isEmpty {
                try fm.removeItem(at: parent)
            }
        } catch {
            return .cleanupPending(marker)
        }
        try hit("cleaned")
        try fm.removeItem(at: markerURL(support: support))
        return .restored(marker)
    }

    private static func install(_ marker: Marker, support: URL, analysis: URL, staging: URL, old: URL,
                                applyPreferences: ([String: Any]) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: old.appendingPathComponent("support", isDirectory: true), withIntermediateDirectories: true)
        // Emplacements : nom dans la sauvegarde → emplacement réel de l'app.
        var targets: [(String, URL)] = [("kyokasho", support.appendingPathComponent("Kyokasho", isDirectory: true)),
                                        ("analysis", analysis)]
        let supportFiles = Set(marker.staged.filter { $0.hasPrefix("support/") })
        for name in supportFiles.sorted() { targets.append((name, support.appendingPathComponent(String(name.dropFirst("support/".count))))) }
        for (name, live) in targets {
            let staged = staging.appendingPathComponent(name), aside = old.appendingPathComponent(name)
            let wasStaged = marker.staged.contains(name)
            let liveExists = fm.fileExists(atPath: live.path), asideExists = fm.fileExists(atPath: aside.path)
            let stagedExists = fm.fileExists(atPath: staged.path)
            if wasStaged {
                // Déjà installé (rejeu après une coupure) : rien à faire.
                if !stagedExists { guard liveExists else { throw RestoreError(String(localized: "Restauration incohérente pour « \(name) ».", bundle: .main)) }; continue }
                if liveExists {
                    guard !asideExists else { throw RestoreError(String(localized: "Restauration incohérente pour « \(name) » : fichiers gardés.", bundle: .main)) }
                    try fm.moveItem(at: live, to: aside)
                    try hit("aside.\(name)")
                }
                try fm.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: staged, to: live)
                try hit("installed.\(name)")
            } else if liveExists, !asideExists {
                // Absent de la sauvegarde : vidé, pour ne pas mêler l'ancienne bibliothèque à la restaurée.
                try fm.moveItem(at: live, to: aside)
                try hit("aside.\(name)")
            }
        }
        // Modèles d'IA : jamais sauvegardés ; ceux de l'appareil reviennent dans la bibliothèque restaurée.
        let oldModels = old.appendingPathComponent("kyokasho/Models", isDirectory: true)
        let liveModels = support.appendingPathComponent("Kyokasho/Models", isDirectory: true)
        if fm.fileExists(atPath: oldModels.path), !fm.fileExists(atPath: liveModels.path) {
            try fm.moveItem(at: oldModels, to: liveModels)
            try hit("models")
        }
        let preferences = staging.appendingPathComponent("preferences.plist")
        if let data = try? Data(contentsOf: preferences),
           let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            applyPreferences(domain)
            try hit("preferences")
        }
    }
}
