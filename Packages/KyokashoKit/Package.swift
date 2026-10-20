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
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Code original (MIT) : modèles, base, import, réglages, logique pure.
        .target(
            name: "ReaderCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Code original (MIT) : moteurs OCR, boîtes de caractères, cache, banc d'essai.
        .target(name: "OCRKit", dependencies: ["ReaderCore"]),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
        .testTarget(name: "OCRKitTests", dependencies: ["OCRKit"]),
    ]
)
