// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import XCTest
@testable import OCRKit

/// PLAN-MODLOC-001, E2 (DEC-05 = A, avenant AV-MODLOC-01) : import d'un dossier MLX, vérifié avant, tout ou rien,
/// jamais de dossier de NOxygen59 perdu. Petits faux modèles (quelques octets), aucun poids réel.
final class LocalModelsTests: XCTestCase {
    private var root: URL!
    private var models: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("modloc-\(UUID().uuidString)", isDirectory: true)
        models = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// Faux modèle : `type` dans config.json, fichiers obligatoires, poids en un fichier ou en parties.
    private func fakeModel(_ name: String = "Mon modèle 4B", type: String = "qwen3_5", skip: String? = nil,
                           shards: [String]? = nil) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"model_type": "\#(type)"}"#.write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        for file in LocalModels.requiredFiles where file != "config.json" && file != skip {
            try "{}".write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        if skip != "chat_template.jinja" {
            try "{{ messages }}".write(to: folder.appendingPathComponent("chat_template.jinja"), atomically: true, encoding: .utf8)
        }
        if let shards {
            let map = Dictionary(uniqueKeysWithValues: shards.map { ("w.\($0)", $0) })
            let index = try JSONSerialization.data(withJSONObject: ["weight_map": map])
            try index.write(to: folder.appendingPathComponent("model.safetensors.index.json"))
            for shard in shards.dropLast() { try Data(repeating: 1, count: 100).write(to: folder.appendingPathComponent(shard)) }
        } else if skip != "model.safetensors" {
            try Data(repeating: 1, count: 1_000).write(to: folder.appendingPathComponent("model.safetensors"))
        }
        return folder
    }

    func testCompleteFolderIsMovedAndListed() throws {
        let folder = try fakeModel()
        let (info, method) = try LocalModels.install(folder, into: models)
        XCTAssertEqual(method, .moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "déplacé, pas copié : pas de double place")
        XCTAssertEqual(info.id, "local-mon-modele-4b")
        XCTAssertEqual(LocalModels.installed(in: models).map(\.id), [info.id])
        let spec = LocalModels.spec(info, in: models)
        XCTAssertTrue(ModelStore(root: models).isInstalled(spec))
        XCTAssertTrue(spec.files.contains { $0.name == "model.safetensors" })
        XCTAssertTrue(LocalModels.isLocal(spec.id))
        // E3 : la liste gardée en mémoire suit l'import puis la suppression.
        let store = ModelStore(root: models)
        XCTAssertEqual(LocalModels.specs(store: store).map(\.id), [info.id])
        XCTAssertEqual(LocalModels.name(info.id, store: store), "Mon modèle 4B")
        XCTAssertTrue(ModelSpec.isQwen35Family(info.id))
        try LocalModels.delete(info.id, in: models)
        XCTAssertTrue(LocalModels.specs(store: store).isEmpty)
    }

    func testInvalidFoldersAreRefusedBeforeAnyMove() throws {
        XCTAssertThrowsError(try LocalModels.install(try fakeModel("A", type: "llama"), into: models)) {
            XCTAssertEqual($0 as? LocalModels.ImportError, .unsupported("llama"))
        }
        let missing = try fakeModel("B", skip: "tokenizer.json")
        XCTAssertThrowsError(try LocalModels.install(missing, into: models)) {
            XCTAssertEqual($0 as? LocalModels.ImportError, .missing(["tokenizer.json"]))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.path), "refusé avant : le dossier reste où il était")
        XCTAssertThrowsError(try LocalModels.install(try fakeModel("C", shards: ["p1.safetensors", "p2.safetensors"]), into: models)) {
            XCTAssertEqual($0 as? LocalModels.ImportError, .missing(["p2.safetensors"]))
        }
        XCTAssertThrowsError(try LocalModels.validate(root.appendingPathComponent("rien")))
        XCTAssertTrue(LocalModels.installed(in: models).isEmpty)
    }

    func testSameNameIsNeverOverwritten() throws {
        try LocalModels.install(try fakeModel("Doublon"), into: models)
        let second = try fakeModel("Doublon")
        XCTAssertThrowsError(try LocalModels.install(second, into: models)) {
            XCTAssertEqual($0 as? LocalModels.ImportError, .alreadyInstalled("Doublon"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testLeftoversFromAKilledImportAreCleanedOrRecoveredNeverLost() throws {
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        // Copie interrompue : effacée (l'original n'avait pas bougé).
        let copying = models.appendingPathComponent(".import-copie", isDirectory: true)
        try FileManager.default.createDirectory(at: copying.appendingPathComponent("local-x"), withIntermediateDirectories: true)
        try Data().write(to: copying.appendingPathComponent(".copie"))
        // Déplacement interrompu : le dossier de NOxygen59 est rendu visible, jamais effacé.
        let moving = models.appendingPathComponent(".import-deplacement", isDirectory: true)
        try FileManager.default.createDirectory(at: moving.appendingPathComponent("local-y"), withIntermediateDirectories: true)
        try Data("poids".utf8).write(to: moving.appendingPathComponent("local-y/model.safetensors"))
        let recovered = LocalModels.removeLeftovers(in: models)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copying.path))
        XCTAssertEqual(recovered.map(\.lastPathComponent), ["Modèle-récupéré-local-y"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered[0].appendingPathComponent("model.safetensors").path))
        XCTAssertTrue(LocalModels.installed(in: models).isEmpty, "rien d'incomplet n'apparaît comme modèle")
    }

    func testDeleteOnlyTouchesImportedModels() throws {
        let (info, _) = try LocalModels.install(try fakeModel(), into: models)
        try FileManager.default.createDirectory(at: models.appendingPathComponent("qwen35chat4b"), withIntermediateDirectories: true)
        try LocalModels.delete("qwen35chat4b", in: models)
        XCTAssertTrue(FileManager.default.fileExists(atPath: models.appendingPathComponent("qwen35chat4b").path))
        try LocalModels.delete(info.id, in: models)
        XCTAssertTrue(LocalModels.installed(in: models).isEmpty)
    }

    /// Revue R2 E2 (C6, C11) : déplacement refusé (dossier parent en lecture seule) → copie, seulement si la place
    /// suffit ; place inconnue → rien n'est lancé ; l'original reste toujours en place.
    func testCopyWhenMoveIsRefusedChecksTheSpace() throws {
        let parent = root.appendingPathComponent("lecture-seule", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let folder = parent.appendingPathComponent("Copie")
        try FileManager.default.moveItem(at: try fakeModel("Copie"), to: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        XCTAssertThrowsError(try LocalModels.install(folder, into: models, available: { 10 })) {
            guard case .notEnoughSpace = $0 as? LocalModels.ImportError else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(LocalModels.installed(in: models).isEmpty)
        let (_, method) = try LocalModels.install(folder, into: models, available: { 1 << 40 })
        XCTAssertEqual(method, .copied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path), "original intact")
        XCTAssertEqual(LocalModels.installed(in: models).count, 1)
        XCTAssertFalse(((try? FileManager.default.contentsOfDirectory(atPath: models.path)) ?? []).contains { $0.hasPrefix(".import-") },
                       "aucune préparation laissée")
    }

    /// Revue R2 E2 (C3, C5, C7, C14) : poids vides refusés, noms japonais distincts, local.json et liens refusés.
    func testWeightsNamesAndSpecialFiles() throws {
        let empty = try fakeModel("Vide")
        try Data().write(to: empty.appendingPathComponent("model.safetensors"))
        XCTAssertThrowsError(try LocalModels.validate(empty)) {
            guard case .badWeights = $0 as? LocalModels.ImportError else { return XCTFail("\($0)") }
        }
        XCTAssertNotEqual(LocalModels.id(for: "模型A"), LocalModels.id(for: "模型B"))
        XCTAssertEqual(LocalModels.id(for: "Qwen3.5-4B"), "local-qwen3.5-4b", "nom ASCII : identifiant lisible, sans empreinte")
        let info = try fakeModel("Info")
        try "{}".write(to: info.appendingPathComponent("local.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LocalModels.validate(info)) { XCTAssertEqual($0 as? LocalModels.ImportError, .alreadyHasInfo) }
        let linked = try fakeModel("Lien")
        try FileManager.default.removeItem(at: linked.appendingPathComponent("model.safetensors"))
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("model.safetensors"),
                                                   withDestinationURL: empty.appendingPathComponent("config.json"))
        XCTAssertThrowsError(try LocalModels.validate(linked)) {
            XCTAssertEqual($0 as? LocalModels.ImportError, .symbolicLink("model.safetensors"))
        }
    }

    /// Essai manuel sur un vrai modèle converti (`KYOKASHO_LOCAL_MODEL_DIR`) : vérification seule, rien n'est déplacé.
    func testRealConvertedModelPassesValidation() throws {
        guard let path = ProcessInfo.processInfo.environment["KYOKASHO_LOCAL_MODEL_DIR"] else {
            throw XCTSkip("KYOKASHO_LOCAL_MODEL_DIR absent")
        }
        let candidate = try LocalModels.validate(URL(fileURLWithPath: path, isDirectory: true))
        XCTAssertEqual(candidate.modelType, "qwen3_5")
        XCTAssertGreaterThan(candidate.size, 1_000_000_000)
    }

    /// Essai du 13/11/2026 : le convertisseur écrit « Qwen3_5Tokenizer », inconnu de l'app ; l'import le remplace par
    /// « TokenizersBackend » (comme le Qwen3.5 officiel) dans la copie installée et garde l'original à côté.
    func testUnknownQwen35TokenizerNameIsNormalizedAndBackedUp() throws {
        let folder = try fakeModel("Tok")
        try #"{"tokenizer_class": "Qwen3_5Tokenizer", "x": 1}"#.write(to: folder.appendingPathComponent("tokenizer_config.json"),
                                                                     atomically: true, encoding: .utf8)
        let (info, _) = try LocalModels.install(folder, into: models)
        let installed = models.appendingPathComponent(info.id)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: installed.appendingPathComponent("tokenizer_config.json"))) as? [String: Any]
        XCTAssertEqual(config?["tokenizer_class"] as? String, "TokenizersBackend")
        XCTAssertEqual(config?["x"] as? Int, 1, "le reste du fichier est gardé")
        let original = try String(contentsOf: installed.appendingPathComponent("tokenizer_config.original.json"), encoding: .utf8)
        XCTAssertTrue(original.contains("Qwen3_5Tokenizer"))
        XCTAssertNil(try LocalModels.normalizeTokenizer(in: installed), "déjà normalisé : rien à refaire")
    }
}
