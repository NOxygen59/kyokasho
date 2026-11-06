// swift-tools-version: 5.10
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PackageDescription

// Moteur OCR IA (GLM-OCR) sur MLX. Paquet à part : MLX est lourd à compiler et n'est pas
// nécessaire aux tests de KyokashoKit. MLX récent rétroporté sur iOS 16 : forks NOxygen59/mlx-swift et
// NOxygen59/mlx-swift-lm, branche ipad-ios16 (voir leur IPAD-IOS16.md). GLM-OCR et Qwen3.5 y sont en amont.
let package = Package(
    name: "GLMOCRKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [.library(name: "GLMOCRKit", targets: ["GLMOCRKit"])],
    dependencies: [
        .package(path: "../KyokashoKit"),
        .package(url: "https://github.com/NOxygen59/mlx-swift-lm", branch: "ipad-ios16"),
        // Tokenizers (iOS 16) : mlx-swift-lm 3.x ne charge plus les tokenizers lui-même.
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
    ],
    targets: [
        .target(name: "GLMOCRKit", dependencies: [
            .product(name: "OCRKit", package: "KyokashoKit"),
            .product(name: "ONNXOCRKit", package: "KyokashoKit"),
            // MLX sur iOS et sur Mac Catalyst à puce Apple (version Mac M5) : l'app Mac est construite en arm64 seulement
            // (project.yml). MLX exige une puce Apple ; MacUnavailable.swift reste le repli si MLX n'est pas compilé.
            .product(name: "MLXVLM", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .macCatalyst])),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .macCatalyst])),
            .product(name: "Tokenizers", package: "swift-transformers", condition: .when(platforms: [.iOS, .macCatalyst])),
        ]),
        .testTarget(name: "GLMOCRKitTests", dependencies: ["GLMOCRKit"]),
    ]
)
