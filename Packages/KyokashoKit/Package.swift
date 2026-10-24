// swift-tools-version: 5.10
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PackageDescription

let package = Package(
    name: "KyokashoKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "OCRKit", targets: ["OCRKit"]),
        .library(name: "DictionaryKit", targets: ["DictionaryKit"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
        .library(name: "ONNXOCRKit", targets: ["ONNXOCRKit"]),
        .library(name: "MorphologyKit", targets: ["MorphologyKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
        // Branche main fixée : le tag 5.0.0 garde l API en interne.
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs", revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9"),
    ],
    targets: [
        // Code original (MIT) : modèles, base, import, réglages, logique pure.
        .target(
            name: "ReaderCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Code original (MIT) : moteurs OCR, boîtes de caractères, cache, banc d'essai.
        .target(name: "OCRKit", dependencies: ["ReaderCore"]),
        // Code porté de Yomitan (GPL-3.0-or-later) : déconjugaison, fonctions japonaises.
        .target(name: "YomitanKit", resources: [.copy("Resources/japanese-transforms.json")]),
        // Code original (MIT) : base de dictionnaires, import Yomitan, recherche, rendu HTML.
        .target(name: "DictionaryKit", dependencies: [
            "YomitanKit",
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        // Code original (MIT) : moteurs OCR ONNX (PP-OCRv5, NDLOCR-Lite), modèles téléchargés à part.
        .target(name: "ONNXOCRKit", dependencies: [
            "OCRKit",
            .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
        ]),
        // Code original (MIT) : cartes, modèles, révisions FSRS, médias.
        .target(name: "ReviewKit", dependencies: [
            .product(name: "FSRS", package: "swift-fsrs"),
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ]),
        // MeCab 0.996 (Taku Kudo, licence BSD choisie parmi GPL / LGPL / BSD) : analyseur morphologique.
        .target(
            name: "MeCabC",
            exclude: ["LICENSE-BSD"],
            cxxSettings: [.define("HAVE_CONFIG_H"), .unsafeFlags(["-w"])]
        ),
        // Code original (MIT) : découpage en mots et lectures (MeCab + dictionnaire UniDic téléchargé à part).
        .target(name: "MorphologyKit", dependencies: ["MeCabC"]),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "YomitanKitTests", dependencies: ["YomitanKit"]),
        .testTarget(name: "DictionaryKitTests", dependencies: ["DictionaryKit"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"]),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"]),
        .testTarget(name: "ONNXOCRKitTests", dependencies: ["ONNXOCRKit"]),
        .testTarget(name: "MorphologyKitTests", dependencies: ["MorphologyKit"]),
        .testTarget(name: "BackupIntegrationTests", dependencies: ["ReaderCore", "ReviewKit"]),
    ],
    cxxLanguageStandard: .cxx14
)
