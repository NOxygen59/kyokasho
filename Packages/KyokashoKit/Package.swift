// swift-tools-version: 5.10
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PackageDescription

let package = Package(
    name: "KyokashoKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
        .library(name: "OCRKit", targets: ["OCRKit"]),
        .library(name: "DictionaryKit", targets: ["DictionaryKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
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
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "YomitanKitTests", dependencies: ["YomitanKit"]),
        .testTarget(name: "DictionaryKitTests", dependencies: ["DictionaryKit"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"]),
    ]
)
