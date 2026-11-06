// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

public enum LibrarySpace: String, CaseIterable, Hashable, Sendable {
    case study, manga

    public static let storageKey = "library.space"

    public var paletteKey: String { "appearance.ipadLibrary.palette." + rawValue }

    public init(document: LibraryDocument) {
        self = document.isInMangaSpace ? .manga : .study
    }

    public static func paletteID(_ id: String?, available: Set<String>) -> String? {
        guard let id, available.contains(id) else { return nil }
        return id
    }

    public static func effectivePaletteID(general: String, overrides: [Self: String],
                                          library: Self, document: Self?, available: Set<String>,
                                          enabled: Bool) -> String {
        guard enabled else { return general }
        return paletteID(overrides[document ?? library], available: available) ?? general
    }
}
