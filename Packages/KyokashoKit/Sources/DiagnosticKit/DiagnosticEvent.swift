// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Niveau d'une ligne du journal (demande du 10/11/2026) : l'ancien format ne disait pas si une ligne était une
/// simple étape ou une erreur, et il fallait lire le message pour le deviner. Déplacé de `ReaderCore` (PLAN-DIAG-001,
/// E1) ; `ReaderCore.DiagnosticLevel` en reste un alias.
public enum DiagnosticLevel: String, Sendable, CaseIterable {
    case info, alerte, erreur
}

/// Zone du journal : liste **fermée** (PLAN-DIAG-001, DEC-01). Les valeurs brutes sont celles des anciennes lignes,
/// pour que les outils de lecture (`docs/DEBOGAGE.md`) continuent de filtrer pareil.
public enum DiagnosticZone: String, Sendable, CaseIterable {
    case app, ui, journal, diagnostic, memoire, cpu, cpuPersistant = "cpu-persistant", energie, performances
    case bibliotheque, importation = "import", export, sauvegarde, drive, pages, analyse, scan, verif
    case lecteur, panneau, affichage, gestes, clavier, notes, furigana
    case ocr, ocrScroll = "ocr-scroll", ocrUI = "ocr-ui", ocrPanel = "ocr-panel", relecture, miseEnPage = "miseenpage"
    case ia, mlx, chat, modeles, traduction
    case dictionnaire, lookup, lookupWeb = "lookup-web", mecab, cartes, revision

    /// Ancienne zone écrite en texte libre → zone fermée ; une zone inconnue devient `app` (rien ne se perd :
    /// la ligne reste, seule sa zone est générique).
    public static func legacy(_ area: String) -> DiagnosticZone {
        DiagnosticZone(rawValue: area) ?? legacyAliases[area] ?? .app
    }

    /// Anciennes zones écrites avec des accents (relevé du 25/11 dans `App/`).
    static let legacyAliases: [String: DiagnosticZone] = [
        "bibliothèque": .bibliotheque, "mémoire": .memoire, "énergie": .energie, "révision": .revision,
    ]
}

/// Issue d'une étape : une opération a exactement **une** issue terminale (`succes`, `erreur`, `annule`, `refus`,
/// `repli`) ; `debut` et `etape` la précèdent.
public enum DiagnosticOutcome: String, Sendable, CaseIterable {
    case debut, etape, succes, erreur, annule, refus, repli
}

/// Cause d'un échec : codes **fermés** (DEC-01). Une erreur système garde seulement son domaine et son numéro, jamais
/// son message (`localizedDescription` peut contenir un chemin ou un nom de fichier).
public enum DiagnosticCause: Sendable, Equatable {
    case aucune, inconnue, lecture, ecriture, introuvable, permission, annulee, donneesInvalides, memoire, delai, doublon
    /// Erreur d'un autre module : domaine (nom de type ou domaine `NSError`) et numéro.
    case systeme(domain: String, code: Int)

    /// Cause tirée d'une erreur : annulation reconnue, sinon domaine et numéro seulement.
    public static func from(_ error: Error) -> DiagnosticCause {
        if error is CancellationError { return .annulee }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return .annulee }
        return .systeme(domain: ns.domain, code: ns.code)
    }

    /// Texte de la ligne : un mot fixe, ou `domaine#numéro`. Le domaine est nettoyé (lettres, chiffres, `._-`)
    /// et borné : il vient d'un type, pas des données, mais une ligne de journal ne doit jamais pouvoir se couper.
    public var text: String {
        switch self {
        case .aucune: return "aucune"
        case .inconnue: return "inconnue"
        case .lecture: return "lecture"
        case .ecriture: return "ecriture"
        case .introuvable: return "introuvable"
        case .permission: return "permission"
        case .annulee: return "annulee"
        case .donneesInvalides: return "donnees-invalides"
        case .memoire: return "memoire"
        case .delai: return "delai"
        case .doublon: return "doublon"
        case .systeme(let domain, let code):
            let safe = String(domain.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }.prefix(60))
            return "\(safe.isEmpty ? "erreur" : safe)#\(code)"
        }
    }
}

/// Identifiant d'opération : opaque, court, tiré au hasard (jamais dérivé d'un contenu). Une action de l'utilisateur
/// a un seul parent ; ses sous-opérations le citent dans `parent`.
public struct DiagnosticOperation: Sendable, Hashable {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
    public static func new() -> DiagnosticOperation { DiagnosticOperation(raw: UInt32.random(in: 1...UInt32.max)) }
    public var text: String { String(format: "%08x", raw) }
}

/// Un nombre nommé (pages, lignes, octets…) : le nom est un littéral du code, la valeur un entier.
public struct DiagnosticCount: Sendable {
    public let name: StaticString
    public let value: Int
    public init(_ name: StaticString, _ value: Int) { self.name = name; self.value = value }
}

/// Événement typé du journal (PLAN-DIAG-001, E1). **Aucune chaîne venue des données** : l'étape est un littéral
/// (`StaticString`), la zone, l'issue et la cause sont fermées, le reste est fait de nombres et d'identifiants opaques.
public struct DiagnosticEvent: Sendable {
    public var level: DiagnosticLevel
    public var zone: DiagnosticZone
    public var step: StaticString
    public var outcome: DiagnosticOutcome
    public var cause: DiagnosticCause
    public var op: DiagnosticOperation?
    public var parent: DiagnosticOperation?
    /// Durée sur horloge monotone, en millisecondes.
    public var durationMs: Int?
    /// Empreinte mémoire de l'app, en Mo.
    public var memoryMB: Int?
    public var counts: [DiagnosticCount]
    /// Référence courte et salée d'un document (`DiagnosticRef`), jamais son titre ni son empreinte.
    public var ref: String?

    public init(_ level: DiagnosticLevel, _ zone: DiagnosticZone, _ step: StaticString, outcome: DiagnosticOutcome = .etape,
                cause: DiagnosticCause = .aucune, op: DiagnosticOperation? = nil, parent: DiagnosticOperation? = nil,
                durationMs: Int? = nil, memoryMB: Int? = nil, counts: [DiagnosticCount] = [], ref: String? = nil) {
        self.level = level
        self.zone = zone
        self.step = step
        self.outcome = outcome
        self.cause = cause
        self.op = op
        self.parent = parent
        self.durationMs = durationMs
        self.memoryMB = memoryMB
        self.counts = counts
        self.ref = ref
    }
}

/// Référence d'un document dans le journal : six caractères tirés de son identifiant **et d'un sel propre à
/// l'installation**. Les identifiants de documents sont des empreintes du fichier (`DocumentImporter`) : un préfixe
/// brut permettrait de reconnaître un livre d'un journal à l'autre ; avec le sel, la référence ne sert qu'à relier
/// les lignes d'un même journal.
public enum DiagnosticRef {
    public static func short(_ id: String, salt: UInt64) -> String {
        // FNV-1a 64 bits : stable d'une version à l'autre (contrairement à `hashValue`), sans dépendance.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(String(hash, radix: 36).suffix(6))
    }
}
