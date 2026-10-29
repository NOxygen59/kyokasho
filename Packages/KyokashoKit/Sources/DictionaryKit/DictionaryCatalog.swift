// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import ZIPFoundation

/// Dictionnaires téléchargeables dans l'app (Issue #50, plan validé par NOxygen59 le 29/10/2026).
///
/// Aucun dictionnaire n'est dans le dépôt : le catalogue ne garde que l'adresse de l'**index de mise à jour**
/// publié par chaque projet (format Yomitan : `title`, `revision`, `downloadUrl`, `indexUrl`). L'app lit cet index,
/// télécharge le .zip à l'adresse qu'il donne, puis l'importe avec `DictionaryImporter`. Les fichiers changent chaque
/// jour ou chaque mois : une empreinte figée serait toujours fausse ; l'intégrité repose sur HTTPS, la taille
/// attendue et la lecture complète du zip par l'importeur.
public struct CatalogEntry: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable { case general, names, kanji }
    public enum Language: String, Sendable { case english = "en", french = "fr" }

    public let id: String
    public let name: String
    public let summary: String
    public let role: Role
    public let language: Language
    public let indexURL: URL
    /// Taille approximative du .zip (affichage), en octets.
    public let approxBytes: Int64
    public let license: String
    /// Début du titre des versions publiées (« JMdict (French) [2026-10-28] » → « JMdict (French) »).
    public let titlePrefix: String
    public let recommended: Bool
}

public enum DictionaryCatalog {
    public static let entries: [CatalogEntry] = [
        CatalogEntry(id: "jitendex", name: "Jitendex", summary: "Dictionnaire japonais → anglais le plus complet, avec exemples (successeur de JMdict).",
                     role: .general, language: .english, indexURL: URL(string: "https://jitendex.org/static/yomitan.json")!,
                     approxBytes: 39_000_000, license: "CC BY-SA 4.0 (JMdict, EDRDG ; Tatoeba)",
                     titlePrefix: "Jitendex.org", recommended: true),
        CatalogEntry(id: "jmdict-fr", name: "JMdict (français)", summary: "Sens en français de JMdict : moins de mots que l'anglais, mais dans ta langue.",
                     role: .general, language: .french,
                     indexURL: URL(string: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_french.json")!,
                     approxBytes: 600_000, license: "Licence EDRDG (CC BY-SA 4.0) ; traductions françaises : droits de leurs auteurs, usage personnel",
                     titlePrefix: "JMdict (French)", recommended: true),
        CatalogEntry(id: "jmnedict", name: "JMnedict (noms propres)", summary: "Noms de personnes, de lieux et d'entreprises, avec leur lecture.",
                     role: .names, language: .english,
                     indexURL: URL(string: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMnedict.json")!,
                     approxBytes: 11_500_000, license: "CC BY-SA 4.0 (EDRDG)", titlePrefix: "JMnedict", recommended: false),
        CatalogEntry(id: "kanjidic-fr", name: "KANJIDIC (français)", summary: "Fiche de chaque kanji : lectures on et kun, sens en français, traits.",
                     role: .kanji, language: .french,
                     indexURL: URL(string: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/KANJIDIC_french.json")!,
                     approxBytes: 300_000, license: "CC BY-SA 4.0 (EDRDG)", titlePrefix: "KANJIDIC (French)", recommended: true),
        CatalogEntry(id: "kanjidic-en", name: "KANJIDIC (anglais)", summary: "Fiche de chaque kanji, sens en anglais (plus complet que le français).",
                     role: .kanji, language: .english,
                     indexURL: URL(string: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/KANJIDIC_english.json")!,
                     approxBytes: 720_000, license: "CC BY-SA 4.0 (EDRDG)", titlePrefix: "KANJIDIC", recommended: false),
    ]

    /// « Jitendex.org [2026-10-03] » → « Jitendex.org » : le titre sans la date de version.
    public static func baseTitle(_ title: String) -> String {
        guard title.hasSuffix("]"), let open = title.lastIndex(of: "[") else { return title.trimmingCharacters(in: .whitespaces) }
        return String(title[..<open]).trimmingCharacters(in: .whitespaces)
    }

    /// Ordre de priorité quand NOxygen59 choisit la langue qui passe en premier (#50, D2) : parmi les places occupées
    /// par des dictionnaires du catalogue, ceux de `first` passent devant les autres langues, chacun gardant son rang
    /// relatif ; les dictionnaires importés à la main (lexique, autres) ne bougent pas.
    public static func ordered(titles: [String], first: CatalogEntry.Language) -> [Int] {
        let language = titles.map { entry(forInstalledTitle: $0)?.language }
        let slots = language.indices.filter { language[$0] != nil }
        let refill = slots.filter { language[$0] == first } + slots.filter { language[$0] != first }
        var order = Array(titles.indices)
        for (slot, index) in zip(slots, refill) { order[slot] = index }
        return order
    }

    /// Entrée du catalogue d'un dictionnaire installé (par son titre), s'il en vient.
    public static func entry(forInstalledTitle title: String) -> CatalogEntry? {
        let base = baseTitle(title)
        return entries.first { $0.titlePrefix == base }
    }
}

/// Index de mise à jour publié avec chaque dictionnaire Yomitan (même contenu que `index.json` dans le zip).
public struct YomitanIndex: Decodable, Equatable, Sendable {
    public let title: String
    public let revision: String?
    public let downloadUrl: URL?
    public let indexUrl: URL?
    public let isUpdatable: Bool?
    public let attribution: String?

    /// Version comparable : `revision` si présente, sinon le titre (qui porte la date chez Jitendex).
    public var version: String { revision ?? title }

    public static func decode(_ data: Data) throws -> YomitanIndex { try JSONDecoder().decode(YomitanIndex.self, from: data) }

    /// Mise à jour disponible : la version publiée diffère de celle installée (titre et révision gardés en base).
    public func isNewer(thanInstalledTitle title: String, revision: String) -> Bool {
        (self.revision.map { $0 != revision } ?? false) || (self.revision == nil && self.title != title)
    }
}

/// Dictionnaire **fourni avec l'app** (#50, D4 piste B ; décision de NOxygen59 du 29/10/2026) : le lexique du design
/// d'intérieur, construit sur le Mac par `tools/build_domain_lexicon.py` et ajouté au paquet par `build_ipa.sh`. Il
/// n'est jamais dans le dépôt ; une app construite sans lui le signale. L'installer l'importe depuis le paquet, sans
/// réseau ; le titre ne porte pas de date, donc une nouvelle version remplace l'ancienne à la même place.
public enum BundledLexicon {
    public static let resource = "lexique-interieur"
    public static let title = "Lexique du design d'intérieur (Wikipédia, Wiktionnaire)"
    public static let name = "Lexique du design d'intérieur"
    public static let summary = "Termes de l'architecture, de l'intérieur, du mobilier et des matériaux : sens en français (Wiktionnaire), titres français et anglais et première phrase (Wikipédia)."
    public static let license = "CC BY-SA 4.0 (contributeurs du Wiktionnaire et de Wikipédia)"

    /// Le fichier dans le paquet de l'app, s'il y a été ajouté au build.
    public static func url(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resource, withExtension: "zip")
    }

    /// Version du fichier (`revision` de son `index.json`), lue sans importer.
    public static func revision(of zip: URL) throws -> String {
        let archive = try Archive(url: zip, accessMode: .read)
        guard let entry = archive["index.json"] else { throw DictionaryImporter.ImportError.notADictionary }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return try YomitanIndex.decode(data).version
    }

    /// Une mise à jour existe si la version fournie diffère de celle installée.
    public static func needsUpdate(installedRevision: String, bundledRevision: String) -> Bool {
        installedRevision != bundledRevision
    }
}
