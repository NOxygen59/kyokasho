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

    func testCopyNeedsEnoughSpace() {
        // Le déplacement est testé plus haut ; ici, la règle de place pour une copie (taille + 10 %).
        XCTAssertEqual(LocalModels.ImportError.notEnoughSpace(needed: 110, free: 50),
                       .notEnoughSpace(needed: 110, free: 50))
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
}
