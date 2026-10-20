// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Source audio de prononciation, essayée dans l'ordre.
public struct AudioSource: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case localFolder, url }

    public var id: String
    public var name: String
    public var kind: Kind
    /// Pour `.url` : modèle avec {term} et {reading}. Pour `.localFolder` : modèles de noms de
    /// fichiers séparés par « | » (ex. « {term}_{reading}.mp3|{reading}.mp3 »).
    public var template: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, kind: Kind, template: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.enabled = enabled
    }

    public static let defaults: [AudioSource] = [
        AudioSource(id: "local", name: "Fichiers audio de l'iPad", kind: .localFolder,
                    template: "{term}_{reading}.mp3|{term}.mp3|{reading}.mp3|{term}_{reading}.m4a|{reading}.m4a"),
        AudioSource(id: "jpod101", name: "JapanesePod101 (en ligne)", kind: .url,
                    template: "https://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kanji={term}&kana={reading}"),
    ]

    /// URL ou nom de fichier pour un mot (paramètres encodés pour une URL).
    public func resolve(term: String, reading: String) -> [String] {
        template.split(separator: "|").map { pattern in
            var s = String(pattern)
            let encode = { (v: String) in kind == .url ? (v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v) : v }
            s = s.replacingOccurrences(of: "{term}", with: encode(term))
            s = s.replacingOccurrences(of: "{reading}", with: encode(reading))
            return s
        }
    }
}

/// Profil de réglages du dictionnaire (comme les profils de Yomitan) : on peut en avoir
/// plusieurs (ex. « Cours », « Lecture rapide ») et changer d'un geste.
public struct DictionaryProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var lookup: LookupOptions
    public var display: GlossaryRenderer.Options
    public var audioSources: [AudioSource]
    public var autoPlayAudio: Bool

    public init(id: String = UUID().uuidString, name: String, lookup: LookupOptions = LookupOptions(),
                display: GlossaryRenderer.Options = GlossaryRenderer.Options(),
                audioSources: [AudioSource] = AudioSource.defaults, autoPlayAudio: Bool = false) {
        self.id = id
        self.name = name
        self.lookup = lookup
        self.display = display
        self.audioSources = audioSources
        self.autoPlayAudio = autoPlayAudio
    }

    public static let standard = DictionaryProfile(id: "default", name: "Standard")
}

/// Liste des profils + profil actif (enregistrés dans la base de l'app).
public struct DictionaryProfiles: Codable, Equatable, Sendable {
    public var profiles: [DictionaryProfile] = [.standard]
    public var activeId: String = DictionaryProfile.standard.id

    public init() {}

    public var active: DictionaryProfile {
        get { profiles.first { $0.id == activeId } ?? profiles.first ?? .standard }
        set {
            if let i = profiles.firstIndex(where: { $0.id == newValue.id }) { profiles[i] = newValue } else { profiles.append(newValue) }
        }
    }
}
