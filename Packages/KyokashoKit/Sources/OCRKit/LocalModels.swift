// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CryptoKit
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
    /// Fichiers indispensables au chargement par la fabrique MLX de l'app (revue R2 E2, C2) ; le gabarit de conversation
    /// peut aussi se trouver dans `tokenizer_config.json` (`chat_template`), voir `validate`.
    public static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json", "preprocessor_config.json",
                                       "processor_config.json"]
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

        public init(id: String, name: String, modelType: String, size: Int64, importedAt: Date) {
            self.id = id
            self.name = name
            self.modelType = modelType
            self.size = size
            self.importedAt = importedAt
        }
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
        case badWeights(String), alreadyHasInfo, unknownFreeSpace, symbolicLink(String), unreadableTokenizer

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
            case .unreadableTokenizer:
                return String(localized: "tokenizer_config.json est illisible : le modèle a peut-être été abîmé pendant le transfert.", bundle: .main)
            case .badWeights(let detail):
                return String(localized: "Poids du modèle incomplets : \(detail).", bundle: .main)
            case .alreadyHasInfo:
                return String(localized: "Ce dossier contient déjà un fichier local.json : choisis le dossier d'origine du modèle.", bundle: .main)
            case .unknownFreeSpace:
                return String(localized: "Place libre inconnue : la copie n'est pas lancée. Place le dossier dans « Sur mon iPad » pour qu'il soit déplacé.", bundle: .main)
            case .symbolicLink(let name):
                return String(localized: "« \(name) » est un lien, pas un vrai fichier : copie le modèle complet dans le dossier.", bundle: .main)
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
        func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
        func size(_ name: String) -> Int64? {
            let values = try? file(name).resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { return nil }
            return Int64(values?.fileSize ?? 0)
        }
        guard let data = try? Data(contentsOf: file("config.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ImportError.unreadableConfig }
        // Revue R2 E2 (C9) : certains convertisseurs ne mettent le type que dans `text_config`.
        let type = (config["model_type"] as? String) ?? ((config["text_config"] as? [String: Any])?["model_type"] as? String) ?? ""
        guard supportedTypes.contains(type) else { throw ImportError.unsupported(type.isEmpty ? "?" : type) }
        // C7 : un `local.json` déjà présent serait écrasé ; C14 : un lien arriverait cassé après une copie.
        guard !fm.fileExists(atPath: file(infoFile).path) else { throw ImportError.alreadyHasInfo }
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where !name.hasPrefix(".") {
            if (try? file(name).resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw ImportError.symbolicLink(name)
            }
        }
        var missing = requiredFiles.filter { size($0) == nil }
        // Revue R2 MODLOC E3 (n°6) : lu une fois, ici ; illisible = refusé avant tout déplacement.
        var template = false
        if size("tokenizer_config.json") != nil {
            guard let tokenizerData = try? Data(contentsOf: file("tokenizer_config.json")),
                  let tokenizer = try? JSONSerialization.jsonObject(with: tokenizerData) as? [String: Any] else {
                throw ImportError.unreadableTokenizer
            }
            template = tokenizer["chat_template"] != nil
        }
        if !template && size("chat_template.jinja") == nil && size("chat_template.json") == nil { missing.append("chat_template.jinja") }
        // C3 : poids entiers = chaque fichier présent et non vide, et, avec un index, toutes ses parties au moins aussi
        // grosses que la taille annoncée (`metadata.total_size`, en-têtes en plus).
        if fm.fileExists(atPath: file("model.safetensors.index.json").path) {
            guard let indexData = try? Data(contentsOf: file("model.safetensors.index.json")),
                  let json = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
                  let map = json["weight_map"] as? [String: String], !map.isEmpty else {
                throw ImportError.badWeights(String(localized: "index des poids illisible ou vide", bundle: .main))
            }
            let parts = Set(map.values).sorted()
            missing += parts.filter { size($0) == nil }
            if missing.isEmpty {
                let total = parts.compactMap { size($0) }.reduce(0, +)
                if parts.contains(where: { size($0) == 0 }) {
                    throw ImportError.badWeights(String(localized: "une partie des poids est vide", bundle: .main))
                }
                if let announced = (json["metadata"] as? [String: Any])?["total_size"] as? NSNumber, total < announced.int64Value {
                    throw ImportError.badWeights(String(localized: "\(total) octets pour \(announced.int64Value) annoncés", bundle: .main))
                }
            }
        } else if let weights = size("model.safetensors") {
            if weights == 0 { throw ImportError.badWeights(String(localized: "model.safetensors est vide", bundle: .main)) }
        } else {
            missing.append("model.safetensors")
        }
        guard missing.isEmpty else { throw ImportError.missing(missing) }
        let name = folder.lastPathComponent
        return Candidate(id: id(for: name), name: name, modelType: type, size: try Self.size(of: folder))
    }

    /// Identifiant stable et sûr pour un nom de dossier : `local-` + lettres, chiffres, `.`, `_`, `-` (le reste devient `-`).
    public static func id(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        let cleaned = String(folded.unicodeScalars.map { $0.isASCII && allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        // Revue R2 E2 (C5) : un nom qui garde des caractères non latins (japonais, emoji) reçoit une courte empreinte
        // du nom d'origine, pour que deux dossiers différents ne donnent jamais le même identifiant.
        let base = String((cleaned.isEmpty ? "modele" : cleaned).prefix(80)).lowercased()
        guard folded.unicodeScalars.contains(where: { !$0.isASCII }) else { return prefix + base }
        let digest = SHA256.hash(data: Data(name.precomposedStringWithCanonicalMapping.utf8))
        return prefix + base + "-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
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
                guard let free = available() ?? freeSpace(at: root) else { throw ImportError.unknownFreeSpace }
                if free < needed { throw ImportError.notEnoughSpace(needed: needed, free: free) }
                // Marque « copie » : seul ce genre de préparation peut être effacé au lancement (`removeLeftovers`).
                try Data().write(to: staging.appendingPathComponent(copyMarker))
                try fm.copyItem(at: folder, to: prepared)
            }
            try normalizeTokenizer(in: prepared)
            let info = Info(id: candidate.id, name: candidate.name, modelType: candidate.modelType, size: candidate.size,
                            importedAt: now)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(info).write(to: prepared.appendingPathComponent(infoFile), options: .atomic)
            try fm.moveItem(at: prepared, to: final)
            try? fm.removeItem(at: staging)
            invalidate(root)
            return (info, method)
        } catch {
            if method == .moved {
                try? fm.removeItem(at: prepared.appendingPathComponent(infoFile))
                // Revue R2 MODLOC E3 (n°7) : le dossier rendu est exactement celui de départ (tokenizer d'origine remis).
                restoreTokenizer(in: prepared)
                guard (try? fm.moveItem(at: prepared, to: folder)) != nil else {
                    throw ImportError.keptAside(staging.path)   // dossier gardé tel quel, jamais effacé
                }
            }
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Noms de tokenizer écrits par certains convertisseurs (mlx-vlm 0.7) pour Qwen3.5, inconnus de `swift-transformers`,
    /// alors que le découpage est le BPE ordinaire que le Qwen3.5 officiel déclare `TokenizersBackend` (essai sur Mac du
    /// 13/11/2026 : `unsupportedTokenizer("Qwen3_5Tokenizer")`).
    static let tokenizerAliases = ["Qwen3_5Tokenizer": "TokenizersBackend", "Qwen3_5TokenizerFast": "TokenizersBackend"]

    /// Remplace un nom de tokenizer inconnu par son équivalent connu dans `tokenizer_config.json` du modèle **installé**
    /// (jamais ailleurs) ; l'original est gardé tel quel à côté (`tokenizer_config.original.json`). Renvoie l'ancien nom.
    @discardableResult
    public static func normalizeTokenizer(in folder: URL) throws -> String? {
        let config = folder.appendingPathComponent("tokenizer_config.json")
        let data = try Data(contentsOf: config)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["tokenizer_class"] as? String, let known = tokenizerAliases[current] else { return nil }
        let backup = folder.appendingPathComponent("tokenizer_config.original.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
        json["tokenizer_class"] = known
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: config, options: .atomic)
        return current
    }

    /// Remet `tokenizer_config.json` d'origine (s'il avait été corrigé) et retire la copie de sauvegarde.
    static func restoreTokenizer(in folder: URL) {
        let fm = FileManager.default
        let backup = folder.appendingPathComponent("tokenizer_config.original.json")
        let config = folder.appendingPathComponent("tokenizer_config.json")
        guard fm.fileExists(atPath: backup.path) else { return }
        if (try? fm.removeItem(at: config)) != nil || !fm.fileExists(atPath: config.path) {
            try? fm.moveItem(at: backup, to: config)
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

    /// Fiches des modèles importés de `store` (E3 : choix du chat, Stockage, pastilles, relevé d'énergie). Lues par des
    /// vues redessinées souvent : gardées en mémoire, relues après un import, une suppression ou un nettoyage.
    public static func specs(store: ModelStore = .shared) -> [ModelSpec] { cached(store.root).specs }

    /// Nom affiché d'un modèle importé, `nil` pour un autre identifiant.
    public static func name(_ id: String, store: ModelStore = .shared) -> String? {
        guard isLocal(id) else { return nil }
        return cached(store.root).infos.first { $0.id == id }?.name
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [URL: (infos: [Info], specs: [ModelSpec])] = [:]

    private static func cached(_ root: URL) -> (infos: [Info], specs: [ModelSpec]) {
        if let hit = cacheLock.withLock({ cache[root] }) { return hit }
        let infos = installed(in: root)
        let value = (infos: infos, specs: infos.map { spec($0, in: root) })
        cacheLock.withLock { cache[root] = value }
        return value
    }

    /// À appeler après tout changement du dossier des modèles importés.
    public static func invalidate(_ root: URL) { cacheLock.withLock { _ = cache.removeValue(forKey: root) } }

    public static func delete(_ id: String, in root: URL) throws {
        guard isLocal(id) else { return }
        let folder = root.appendingPathComponent(id, isDirectory: true)
        defer { invalidate(root) }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// Préparations laissées par une app tuée pendant un import (au lancement) : une **copie** inachevée est effacée
    /// (l'original est resté à sa place) ; un dossier **déplacé** n'est jamais effacé, il est rendu visible comme
    /// dossier `Modèle-récupéré-…` dans `root` pour que NOxygen59 le retrouve. Renvoie les dossiers récupérés.
    /// `recoverTo` : dossier où rendre un dossier déplacé (l'app y met `Documents/Modèles récupérés`, visible dans Fichiers,
    /// revue R2 E2 C4) ; par défaut `root`.
    @discardableResult
    public static func removeLeftovers(in root: URL, recoverTo: URL? = nil) -> [URL] {
        let fm = FileManager.default
        var recovered: [URL] = []
        defer { invalidate(root) }
        for staging in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []
        where staging.lastPathComponent.hasPrefix(stagingPrefix) {
            if fm.fileExists(atPath: staging.appendingPathComponent(copyMarker).path) {
                try? fm.removeItem(at: staging)
                continue
            }
            for moved in (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: moved.appendingPathComponent(infoFile))
                let destination = recoverTo ?? root
                try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
                // Revue R2 MODLOC E3 (n°10) : nom libre garanti (« -2 », « -3 »…), jamais d'échec silencieux sur un nom pris.
                var target = destination.appendingPathComponent("Modèle-récupéré-" + moved.lastPathComponent, isDirectory: true)
                var rank = 2
                while fm.fileExists(atPath: target.path) {
                    target = destination.appendingPathComponent("Modèle-récupéré-\(moved.lastPathComponent)-\(rank)", isDirectory: true)
                    rank += 1
                }
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
