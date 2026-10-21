// swift-tools-version: 5.10
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import PackageDescription

// Moteur OCR IA (GLM-OCR) sur MLX. Paquet à part : MLX est lourd à compiler et n'est pas
// nécessaire aux tests de KyokashoKit. mlx-swift-lm 2.29.3 = dernière version pour iOS 16.
let package = Package(
    name: "GLMOCRKit",
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [.library(name: "GLMOCRKit", targets: ["GLMOCRKit"])],
    dependencies: [
        .package(path: "../KyokashoKit"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.29.3"),
    ],
    targets: [
        .target(name: "GLMOCRKit", dependencies: [
            .product(name: "OCRKit", package: "KyokashoKit"),
            .product(name: "ONNXOCRKit", package: "KyokashoKit"),
            .product(name: "MLXVLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        ]),
    ]
)
