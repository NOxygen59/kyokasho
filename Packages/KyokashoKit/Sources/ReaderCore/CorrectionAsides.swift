// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Une ligne corrigée à la main, telle qu'elle vient de son résultat OCR :
/// `original` est le texte que l'OCR (et non l'utilisateur) avait lu, `corrected` le texte corrigé.
public struct KeptCorrection: Codable, Hashable, Sendable {
    public var original: String
    public var corrected: String

    public init(original: String, corrected: String) {
        self.original = original
        self.corrected = corrected
    }
}

/// Décision DEC-C3 (10/11/2026) : quand un cours est remplacé, le cache OCR qui porte les
/// corrections faites **à la main** est effacé avec tout le reste (`rekeyDocument`, décision
/// DEC-C1 = A). Ces corrections ne sont pas des mesures du PDF : les garder demande de les
/// remettre le moment venu. Ce magasin tient le dossier de secours :
///
/// - `Corrections-remplacement/<identifiant du nouveau document>/` — fichiers écrits **avant**
///   l'effacement du cache, un par résultat OCR, nommés avec un UUID (jamais écrasés) ;
/// - la remise se fait dans `OCRService.store`, au moment où un nouveau résultat OCR est
///   enregistré : une ligne relue du nouveau PDF dont le texte est **identique** au texte lu
///   d'origine reçoit la correction (comme une correction faite à la main), puis elle est
///   retirée du dossier ; les autres restent pour une relecture suivante ;
/// - `Conflits-remplacement/<ancien identifiant>/Encre/` — dessin d'encre perdu pendant une
///   fusion (revue R2, N2) : PencilKit n'offre pas de fusion publique de deux dessins, le
///   dessin perdant est mis de côté tel quel, jamais écrasé ;
/// - `cote.json` — compteur des données mises de côté, tenu **sur le disque** (revue R2, N8) :
///   la mémoire seule le perdrait à l'arrêt, et l'affichage doit survivre à une reprise au
///   lancement. Les écritures arrivent du fil principal (reprise `reconcile`) **et** de la
///   tâche détachée de l'import (appui direct) : tous les accès passent par un verrou.
///
/// Le dossier est sous le support de l'app (`Kyokasho/`) : la sauvegarde complète copie tout ce
/// dossier (comme `Conflits-remplacement`, gardes DATA-02 et données-copie, commit `c03712a`).
public final class CorrectionAsideStore: @unchecked Sendable {
    /// Magasin de l'app ; remplacé par les tests Mac pour travailler dans un dossier temporaire
    /// (même motif que `NoteDraftStore.shared`). `nonisolated(unsafe)` : les tests injectent un
    /// dossier temporaire depuis le fil principal, les usages le lisent et l'écrivent de partout.
    nonisolated(unsafe) public static var shared = CorrectionAsideStore(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kyokasho", isDirectory: true))

    /// Racine du conteneur de l'app, ici `Application Support/Kyokasho`.
    public let root: URL
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
    }

    // MARK: Corrections manuelles mises de côté

    /// Fichier d'une page mise de côté : format disque versionné, comme `NoteDraftStore` (`File`).
    private struct KeptPageFile: Codable {
        var version: Int
        var pageIndex: Int
        var engine: String
        var entries: [KeptCorrection]
    }

    /// Une mise de côté en attente de remise : la correction, et le fichier qui la porte.
    public struct PendingCorrection: Sendable {
        public let file: URL
        public let entry: KeptCorrection
    }

    /// Dossier des corrections de côté d'un document (suivi d'un remplacement au suivant : revue R2, S1).
    public func folder(documentId: String) -> URL { correctionsFolder(documentId: documentId) }

    private func correctionsFolder(documentId: String) -> URL {
        root.appendingPathComponent("Corrections-remplacement", isDirectory: true)
            .appendingPathComponent(documentId, isDirectory: true)
    }

    /// Écrit les lignes corrigées de **un** résultat OCR de l'ancienne version. `documentId` est
    /// l'identifiant du document relu ensuite (le nouveau), `sourceDocumentId` celui qui va être
    /// effacé : c'est sous lui que le compteur note les corrections, car c'est lui que l'appelant
    /// (rapport final, `PageShift`) connaît.
    /// - Throws: erreur d'écriture du système de fichiers ; l'appelant (`rekeyDocument`) la
    ///   traite : la bascule est refusée plutôt que les corrections perdues en silence.
    public func keep(pageIndex: Int, engine: String, entries: [KeptCorrection],
                     documentId: String, sourceDocumentId: String) throws {
        guard !entries.isEmpty else { return }
        let folder = correctionsFolder(documentId: documentId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = Self.correctionFileName(pageIndex: pageIndex, engine: engine, entries: entries, folder: folder)
        lock.lock()
        defer { lock.unlock() }
        // Revue R2, S5 : nom tiré du contenu. Une transaction annulée puis rejouée réécrit le même
        // fichier au lieu d'en créer un double (jamais appliqué, compté deux fois) ; un contenu
        // différent a un autre nom, rien n'est écrasé.
        let isNew = !FileManager.default.fileExists(atPath: file.path)
        try JSONEncoder().encode(KeptPageFile(version: 1, pageIndex: pageIndex, engine: engine, entries: entries))
            .write(to: file, options: .atomic)
        if isNew { try bumpTally(documentId: sourceDocumentId) { $0.corrections += entries.count } }
    }

    /// Nom de fichier : composants sûrs (le moteur vient d'un identifiant de base), terminé par une
    /// empreinte stable du contenu (FNV-1a 64 bits) : même contenu = même nom ; un autre résultat de
    /// la même page a un autre nom et ne peut pas écraser le premier.
    static func correctionFileName(pageIndex: Int, engine: String, entries: [KeptCorrection], folder: URL) -> URL {
        let engineName = engine.allSatisfy { $0.isLetter || $0.isNumber || "_-.".contains($0) } ? engine : "moteur"
        var hash: UInt64 = 0xcbf29ce484222325
        for entry in entries {
            for byte in Array((entry.original + "\u{1}" + entry.corrected + "\u{2}").utf8) {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
        }
        return folder.appendingPathComponent("corrections-page-\(pageIndex)-\(engineName)-\(String(hash, radix: 16)).json")
    }

    /// Toutes les corrections en attente pour une page et son moteur, dans l'ordre d'écriture.
    /// Un fichier illisible (écrit par un arrêt au pire moment) est sauté, jamais effacé.
    public func pendingCorrections(documentId: String, pageIndex: Int, engine: String) -> [PendingCorrection] {
        let folder = correctionsFolder(documentId: documentId)
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        lock.lock()
        defer { lock.unlock() }
        var result: [PendingCorrection] = []
        for file in names.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let kept = try? decoder.decode(KeptPageFile.self, from: data),
                  kept.version == 1, kept.pageIndex == pageIndex, kept.engine == engine else { continue }
            for entry in kept.entries { result.append(PendingCorrection(file: file, entry: entry)) }
        }
        return result
    }

    /// Retire les entrées **appliquées** d'un fichier : « une correction appliquée est retirée du
    /// dossier, les autres restent ». Meilleur effort : un retrait raté (disque plein) garde
    /// l'entrée, mais elle ne s'appliquera pas deux fois — la ligne relue porte déjà la
    /// correction (`originalText`) et ne concorde plus avec le texte lu d'origine.
    public func removeApplied(documentId: String, file: URL, entries: Set<KeptCorrection>) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: file),
              var kept = try? JSONDecoder().decode(KeptPageFile.self, from: data), kept.version == 1 else { return }
        kept.entries.removeAll { entries.contains($0) }
        if kept.entries.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? JSONEncoder().encode(kept).write(to: file, options: .atomic)
        }
    }

    /// Dossier entier du document : part avec lui quand il est supprimé de la bibliothèque
    /// (des corrections sans document ne peuvent plus être lues).
    public func removeAllCorrections(documentId: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: correctionsFolder(documentId: documentId))
    }

    // MARK: Dessin d'encre perdu pendant une fusion (revue R2, N2)

    /// Écrit le dessin perdant d'une page en conflit, tel quel (`PKDrawing.dataRepresentation()`),
    /// sous `Conflits-remplacement/<ancien identifiant>/Encre/`. Un dessin déjà mis de côté pour
    /// la même page n'est jamais écrasé : le nom gagne alors un UUID.
    public func keepInk(sourceDocumentId: String, pageIndex: Int, data: Data) throws {
        let folder = root.appendingPathComponent("Conflits-remplacement", isDirectory: true)
            .appendingPathComponent(sourceDocumentId, isDirectory: true)
            .appendingPathComponent("Encre", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var file = folder.appendingPathComponent("page-\(pageIndex).ink")
        if FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("page-\(pageIndex)-\(UUID().uuidString).ink")
        }
        try data.write(to: file, options: .atomic)
        lock.lock()
        defer { lock.unlock() }
        try bumpTally(documentId: sourceDocumentId) { $0.conflicts += 1 }
    }

    // MARK: Compteur des mises de côté (revue R2, N8)

    /// Somme des données mises de côté d'un remplacement : un fichier par document remplacé,
    /// écrit à chaque mise de côté, lu et retiré une fois rapporté (`consumeTally`). Le dossier
    /// des données reste ; un compte déjà consommé ne se repésente pas deux fois.
    public struct Tally: Codable, Hashable, Sendable {
        public var version: Int
        public var conflicts: Int
        public var corrections: Int

        public init(version: Int = 1, conflicts: Int = 0, corrections: Int = 0) {
            self.version = version
            self.conflicts = conflicts
            self.corrections = corrections
        }
    }

    private func tallyURL(documentId: String) -> URL {
        root.appendingPathComponent("Conflits-remplacement", isDirectory: true)
            .appendingPathComponent(documentId, isDirectory: true)
            .appendingPathComponent("cote.json")
    }

    /// Accumule une mise de côté sur le compteur du document remplacé ; appelée sous le verrou.
    private func bumpTally(documentId: String, _ bump: (inout Tally) -> Void) throws {
        let url = tallyURL(documentId: documentId)
        var tally: Tally
        if let data = try? Data(contentsOf: url),
           let kept = try? JSONDecoder().decode(Tally.self, from: data), kept.version == 1 {
            tally = kept
        } else {
            tally = Tally()
        }
        bump(&tally)
        // Le dossier du document remplacé n'existe pas encore quand la première mise de côté
        // vient des corrections (créées sous « Corrections-remplacement », pas ici) : le créer
        // avant l'écriture atomique du compteur.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(tally).write(to: url, options: .atomic)
    }

    /// Note un conflit « cible déjà présente » (fichier déplacé au lieu d'être installé).
    public func registerConflict(documentId: String) {
        do {
            lock.lock()
            defer { lock.unlock() }
            try bumpTally(documentId: documentId) { $0.conflicts += 1 }
        } catch {
            // Compte perdu : les données mises de côté restent sur le disque, seuls les chiffres manquent.
        }
    }

    /// Lit et retire le compteur pas encore rapporté du document. Le retrait suit la lecture :
    /// un rapport interrompu rejoue la consommation, sans présenter deux fois les mêmes chiffres.
    public func consumeTally(documentId: String) -> Tally {
        let url = tallyURL(documentId: documentId)
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let tally = try? JSONDecoder().decode(Tally.self, from: data), tally.version == 1 else {
            return Tally(conflicts: 0, corrections: 0)
        }
        try? FileManager.default.removeItem(at: url)
        return Tally(conflicts: tally.conflicts, corrections: tally.corrections)
    }
}
