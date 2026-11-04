// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import MeCabC

/// MeCab avec le dictionnaire UniDic (téléchargé à part) : découpage en mots courts, lecture en kana de chaque
/// mot **selon son contexte** (上手 うわて / じょうず, 今日, 一日…), forme de base et catégorie.
/// Le dictionnaire est lu en mémoire projetée (`mmap`) : peu de mémoire vive malgré sa taille sur le disque.
public final class MeCab: @unchecked Sendable {
    public struct Token: Sendable, Equatable {
        public let surface: String
        /// Zone dans le texte (index UTF-16, ceux de `NSString`).
        public let range: NSRange
        /// Lecture du mot tel qu'écrit, en hiragana (vide si inconnue).
        public let reading: String
        /// Forme de base (lemme UniDic, ex. 読む pour 読ん).
        public let lemma: String
        /// Catégorie (nom, verbe, particule…), sous-catégories ensuite.
        public let pos: [String]
    }

    public enum Failure: LocalizedError {
        case load(String)
        public var errorDescription: String? { if case .load(let m) = self { return String(localized: "MeCab : \(m)", bundle: .main) }; return nil }
    }

    private let model: OpaquePointer
    private let tagger: OpaquePointer
    private let lattice: OpaquePointer
    private let lock = NSLock()

    /// `dictionary` : dossier contenant `sys.dic`, `matrix.bin`, `char.bin`, `unk.dic`, `dicrc`.
    public init(dictionary: URL) throws {
        // Arguments passés un par un : un chemin avec espace (« Application Support ») ne doit pas être coupé.
        let args = ["mecab", "-r", "/dev/null", "-d", dictionary.path]
        var cArgs = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }
        guard let model = cArgs.withUnsafeMutableBufferPointer({ mecab_model_new(Int32(args.count), $0.baseAddress) }) else {
            throw Failure.load(String(localized: "dictionnaire illisible (\(dictionary.lastPathComponent))", bundle: .main))
        }
        guard let tagger = mecab_model_new_tagger(model), let lattice = mecab_model_new_lattice(model) else {
            mecab_model_destroy(model)
            throw Failure.load(String(localized: "analyseur non créé", bundle: .main))
        }
        self.model = model
        self.tagger = tagger
        self.lattice = lattice
    }

    deinit {
        mecab_lattice_destroy(lattice)
        mecab_destroy(tagger)
        mecab_model_destroy(model)
    }

    public func tokens(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let utf8 = Array(text.utf8)
        // Octet UTF-8 → index UTF-16 (MeCab rend des pointeurs dans le texte UTF-8).
        var utf16At = [Int](repeating: 0, count: utf8.count + 1)
        var b = 0, u = 0
        for scalar in text.unicodeScalars {
            let n = scalar.utf8.count
            for k in 0..<n { utf16At[b + k] = u }
            b += n
            u += scalar.utf16.count
        }
        utf16At[utf8.count] = u

        lock.lock()
        defer { lock.unlock() }
        var out: [Token] = []
        utf8.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { chars in
                guard let base = chars.baseAddress else { return }
                mecab_lattice_set_sentence2(lattice, base, utf8.count)
                guard mecab_parse_lattice(tagger, lattice) != 0 else { return }
                var node = mecab_lattice_get_bos_node(lattice)
                while let current = node {
                    let n = current.pointee
                    // 0 : mot normal, 1 : mot inconnu (MECAB_NOR_NODE / MECAB_UNK_NODE).
                    if n.stat == 0 || n.stat == 1, let surface = n.surface, n.length > 0 {
                        let start = surface - base
                        let end = start + Int(n.length)
                        if start >= 0, end <= utf8.count {
                            let word = String(decoding: utf8[start..<end], as: UTF8.self)
                            let fields = n.feature.map { Self.csv(String(cString: $0)) } ?? []
                            func field(_ i: Int) -> String { i < fields.count && fields[i] != "*" ? fields[i] : "" }
                            let kana = field(17).applyingTransform(.hiraganaToKatakana, reverse: true) ?? ""
                            out.append(Token(surface: word,
                                             range: NSRange(location: utf16At[start], length: utf16At[end] - utf16At[start]),
                                             reading: kana, lemma: field(7),
                                             pos: (0..<4).map(field).filter { !$0.isEmpty }))
                        }
                    }
                    node = n.next
                }
            }
        }
        return out
    }

    /// Champs du trait UniDic (CSV, guillemets possibles autour d'un champ qui contient une virgule).
    static func csv(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            if c == "\"" {
                if quoted, chars.first == "\"" { current.append("\""); chars.removeFirst() } else { quoted.toggle() }
            } else if c == ",", !quoted {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(current)
        return fields
    }
}
