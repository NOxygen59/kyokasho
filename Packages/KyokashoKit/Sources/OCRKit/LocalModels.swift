// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Modèles MLX importés à la main par NOxygen59 (PLAN-MODLOC-001, E2 ; DEC-05 = A et avenant AV-MODLOC-01, décidés le
/// 13/11/2026) : un **dossier** choisi dans Fichiers, vérifié en place, puis **déplacé** dans
/// `Models/local-<nom>/` (copié seulement si iOS refuse le déplacement, après contrôle de la place libre).
///
/// Invariants :
/// - un modèle n'est visible (`installed`) que si son dossier final existe **et** contient `local.json`, écrit dans le
///   dossier de préparation **avant** le renommage final : jamais de modèle à moitié installé dans la liste ;
/// - la préparation se fait dans `Models/.import-<uuid>/`, sur le même disque, puis un seul renommage la rend visible ;
///   un échec (ou une app tuée) laisse au pire un dossier `.import-*`, ignoré par la liste et effacé par `removeLeftovers` ;
/// - un nom déjà pris est refusé (jamais d'écrasement d'un modèle existant, officiel ou importé) ;
/// - la validation ne lit que de petits fichiers (`config.json`, l'index des poids) : aucun poids n'est chargé ici.
public enum LocalModels {
    /// Architectures que la fabrique MLX de l'app sait charger pour le chat (au départ, la famille Qwen3.5).
    public static let supportedTypes: Set<String> = ["qwen3_5"]
    /// Fichiers indispensables au chargement (mêmes que le Qwen3.5 officiel, hors poids).
    public static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json"]
    static let prefix = "local-"
    static let infoFile = "local.json"
    static let stagingPrefix = ".import-"
    static let copyMarker = ".copie"

    public struct Info: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let modelType: String
        public let size: Int64
        public let importedAt: Date
    }

    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let name: String
        public let modelType: String
        public let size: Int64
    }

    public enum ImportError: LocalizedError, Equatable {
        case unreadableConfig, unsupported(String), missing([String]), alreadyInstalled(String), notEnoughSpace(needed: Int64, free: Int64)
        case keptAside(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableConfig:
                return String(localized: "Ce dossier n'est pas un modèle MLX : config.json absent ou illisible.", bundle: .main)
            case .unsupported(let type):
                return String(localized: "Architecture « \(type) » pas encore prise en charge (seulement Qwen3.5).", bundle: .main)
            case .missing(let files):
                return String(localized: "Fichiers manquants : \(files.joined(separator: ", ")).", bundle: .main)
            case .alreadyInstalled(let name):
                return String(localized: "Un modèle « \(name) » est déjà installé : supprime-le d'abord.", bundle: .main)
            case .keptAside(let path):
                return String(localized: "Import interrompu : ton dossier est gardé dans \(path).", bundle: .main)
            case .notEnoughSpace(let needed, let free):
                let f = ByteCountFormatter()
                return String(localized: "Place insuffisante : \(f.string(fromByteCount: needed)) nécessaires, \(f.string(fromByteCount: free)) libres.", bundle: .main)
            }
        }
    }

    // MARK: Validation (avant tout déplacement)

    /// Vérifie le dossier en place : `config.json` lisible, architecture prise en charge, fichiers obligatoires et poids
    /// complets (fichier unique, ou toutes les parties citées par `model.safetensors.index.json`).
    public static func validate(_ folder: URL) throws -> Candidate {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ImportError.unreadableConfig }
        let type = config["model_type"] as? String ?? ""
        guard supportedTypes.contains(type) else { throw ImportError.unsupported(type.isEmpty ? "?" : type) }
        var missing = requiredFiles.filter { !fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let index = folder.appendingPathComponent("model.safetensors.index.json")
        if let indexData = try? Data(contentsOf: index),
           let json = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
           let map = json["weight_map"] as? [String: String] {
            missing += Set(map.values).sorted().filter { !fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        } else if !fm.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path) {
            missing.append("model.safetensors")
        }
        guard missing.isEmpty else { throw ImportError.missing(missing) }
        let name = folder.lastPathComponent
        return Candidate(id: id(for: name), name: name, modelType: type, size: try size(of: folder))
    }

    /// Identifiant stable et sûr pour un nom de dossier : `local-` + lettres, chiffres, `.`, `_`, `-` (le reste devient `-`).
    public static func id(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        let cleaned = String(folded.unicodeScalars.map { $0.isASCII && allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return prefix + String((cleaned.isEmpty ? "modele" : cleaned).prefix(80)).lowercased()
    }

    // MARK: Installation

    public enum Method: Equatable, Sendable { case moved, copied }

    /// Installe le dossier validé dans `root` : déplacement si iOS le permet, sinon copie (place libre vérifiée avant,
    /// + 10 %). `available` : place libre imposée (tests) ; `nil` = celle du disque de `root`. Tout ou rien.
    /// Le dossier de NOxygen59 n'est **jamais** perdu : après un déplacement, toute erreur le remet à sa place ; si même
    /// ce retour échoue, le dossier de préparation est gardé (pas effacé) et l'erreur le dit.
    @discardableResult
    public static func install(_ folder: URL, into root: URL, available: () -> Int64? = { nil },
                               now: Date = Date()) throws -> (Info, Method) {
        let candidate = try validate(folder)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let final = root.appendingPathComponent(candidate.id, isDirectory: true)
        guard !fm.fileExists(atPath: final.path) else { throw ImportError.alreadyInstalled(candidate.name) }
        let staging = root.appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let prepared = staging.appendingPathComponent(candidate.id, isDirectory: true)
        var method = Method.copied
        do {
            do {
                try fm.moveItem(at: folder, to: prepared)
                method = .moved
            } catch {
                // Déplacement refusé (autre fournisseur, iCloud, droits) : copie, seulement si la place suffit.
                let needed = candidate.size + candidate.size / 10
                if let free = available() ?? freeSpace(at: root), free < needed {
                    throw ImportError.notEnoughSpace(needed: needed, free: free)
                }
                // Marque « copie » : seul ce genre de préparation peut être effacé au lancement (`removeLeftovers`).
                try Data().write(to: staging.appendingPathComponent(copyMarker))
                try fm.copyItem(at: folder, to: prepared)
            }
            let info = Info(id: candidate.id, name: candidate.name, modelType: candidate.modelType, size: candidate.size,
                            importedAt: now)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(info).write(to: prepared.appendingPathComponent(infoFile), options: .atomic)
            try fm.moveItem(at: prepared, to: final)
            try? fm.removeItem(at: staging)
            return (info, method)
        } catch {
            if method == .moved {
                try? fm.removeItem(at: prepared.appendingPathComponent(infoFile))
                guard (try? fm.moveItem(at: prepared, to: folder)) != nil else {
                    throw ImportError.keptAside(staging.path)   // dossier gardé tel quel, jamais effacé
                }
            }
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Place libre du disque de `url` (nil si inconnue).
    public static func freeSpace(at url: URL?) -> Int64? {
        let target = url ?? FileManager.default.temporaryDirectory
        let values = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Liste, spécification, suppression

    /// Modèles importés complets (dossier `local-*` avec `local.json`), par nom.
    public static func installed(in root: URL) -> [Info] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.lastPathComponent.hasPrefix(prefix) }.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(infoFile)),
                  let info = try? decoder.decode(Info.self, from: data), info.id == folder.lastPathComponent else { return nil }
            return info
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Fiche du modèle importé, lue par le reste de l'app comme un modèle officiel (`ModelStore.directory`,
    /// `isInstalled`, `installedSize`). Aucune adresse de téléchargement : `url` reste vide, jamais utilisée.
    public static func spec(_ info: Info, in root: URL) -> ModelSpec {
        let folder = root.appendingPathComponent(info.id, isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return ModelSpec(id: info.id, title: info.name,
                         summary: String(localized: "Modèle importé à la main (\(info.modelType)).", bundle: .main),
                         license: String(localized: "Licence du modèle importé : à vérifier par son propriétaire.", bundle: .main),
                         files: names.map { ModelSpec.File(name: $0, url: folder.appendingPathComponent($0), size: 0, sha256: nil) })
    }

    /// Un identifiant de modèle importé (famille Qwen3.5 tant que `supportedTypes` n'a qu'elle).
    public static func isLocal(_ id: String) -> Bool { id.hasPrefix(prefix) }

    public static func delete(_ id: String, in root: URL) throws {
        guard isLocal(id) else { return }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// Préparations laissées par une app tuée pendant un import (au lancement) : une **copie** inachevée est effacée
    /// (l'original est resté à sa place) ; un dossier **déplacé** n'est jamais effacé, il est rendu visible comme
    /// dossier `Modèle-récupéré-…` dans `root` pour que NOxygen59 le retrouve. Renvoie les dossiers récupérés.
    @discardableResult
    public static func removeLeftovers(in root: URL) -> [URL] {
        let fm = FileManager.default
        var recovered: [URL] = []
        for staging in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []
        where staging.lastPathComponent.hasPrefix(stagingPrefix) {
            if fm.fileExists(atPath: staging.appendingPathComponent(copyMarker).path) {
                try? fm.removeItem(at: staging)
                continue
            }
            for moved in (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: moved.appendingPathComponent(infoFile))
                let target = root.appendingPathComponent("Modèle-récupéré-" + moved.lastPathComponent, isDirectory: true)
                if (try? fm.moveItem(at: moved, to: target)) != nil { recovered.append(target) }
            }
            // Effacé seulement s'il est vide : ce qui n'a pas pu être rendu reste tel quel.
            if ((try? fm.contentsOfDirectory(atPath: staging.path)) ?? ["?"]).isEmpty { try? fm.removeItem(at: staging) }
        }
        return recovered
    }

    static func size(of folder: URL) throws -> Int64 {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
}
