// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Réglages du lecteur. Les valeurs globales servent de défaut ; chaque document peut en
/// remplacer une partie (`ReaderSettingsOverride`).
public struct ReaderSettings: Codable, Equatable, Sendable {
    public enum PageLayout: String, Codable, CaseIterable, Sendable { case single, double }
    public enum ScrollMode: String, Codable, CaseIterable, Sendable { case paginated, continuous }
    public enum Direction: String, Codable, CaseIterable, Sendable { case leftToRight, rightToLeft }
    public enum Transition: String, Codable, CaseIterable, Sendable { case slide, none }
    public enum Background: String, Codable, CaseIterable, Sendable { case black, darkGray, gray, white, sepia }

    public var layout: PageLayout = .single
    public var scrollMode: ScrollMode = .paginated
    public var direction: Direction = .leftToRight
    /// En double page, la première page est affichée seule (couverture).
    public var firstPageAlone: Bool = true
    /// Rognage automatique des marges blanches.
    public var autoCrop: Bool = false
    /// Coupe en deux les pages plus larges que hautes (scans de double page).
    public var splitWidePages: Bool = false
    public var background: Background = .darkGray
    public var transition: Transition = .slide
    /// Nombre de pages préparées à l'avance de chaque côté (0…10).
    public var preloadCount: Int = 2
    public var tapZonesEnabled: Bool = true
    public var invertTapZones: Bool = false
    public var doubleTapZoom: Bool = true
    public var hideBarsOnScroll: Bool = true

    public init() {}

    public static let `default` = ReaderSettings()

    // Décodage tolérant : une clé absente (ancienne version) prend sa valeur par défaut.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings.default
        layout = try c.decodeIfPresent(PageLayout.self, forKey: .layout) ?? d.layout
        scrollMode = try c.decodeIfPresent(ScrollMode.self, forKey: .scrollMode) ?? d.scrollMode
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? d.direction
        firstPageAlone = try c.decodeIfPresent(Bool.self, forKey: .firstPageAlone) ?? d.firstPageAlone
        autoCrop = try c.decodeIfPresent(Bool.self, forKey: .autoCrop) ?? d.autoCrop
        splitWidePages = try c.decodeIfPresent(Bool.self, forKey: .splitWidePages) ?? d.splitWidePages
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? d.background
        transition = try c.decodeIfPresent(Transition.self, forKey: .transition) ?? d.transition
        preloadCount = min(10, max(0, try c.decodeIfPresent(Int.self, forKey: .preloadCount) ?? d.preloadCount))
        tapZonesEnabled = try c.decodeIfPresent(Bool.self, forKey: .tapZonesEnabled) ?? d.tapZonesEnabled
        invertTapZones = try c.decodeIfPresent(Bool.self, forKey: .invertTapZones) ?? d.invertTapZones
        doubleTapZoom = try c.decodeIfPresent(Bool.self, forKey: .doubleTapZoom) ?? d.doubleTapZoom
        hideBarsOnScroll = try c.decodeIfPresent(Bool.self, forKey: .hideBarsOnScroll) ?? d.hideBarsOnScroll
    }

    public func applying(_ override: ReaderSettingsOverride) -> ReaderSettings {
        var s = self
        if let v = override.layout { s.layout = v }
        if let v = override.scrollMode { s.scrollMode = v }
        if let v = override.direction { s.direction = v }
        if let v = override.firstPageAlone { s.firstPageAlone = v }
        if let v = override.autoCrop { s.autoCrop = v }
        if let v = override.splitWidePages { s.splitWidePages = v }
        if let v = override.background { s.background = v }
        if let v = override.transition { s.transition = v }
        if let v = override.preloadCount { s.preloadCount = min(10, max(0, v)) }
        if let v = override.tapZonesEnabled { s.tapZonesEnabled = v }
        if let v = override.invertTapZones { s.invertTapZones = v }
        if let v = override.doubleTapZoom { s.doubleTapZoom = v }
        if let v = override.hideBarsOnScroll { s.hideBarsOnScroll = v }
        return s
    }
}

/// Réglages propres à un document : `nil` = valeur globale.
public struct ReaderSettingsOverride: Codable, Equatable, Sendable {
    public var layout: ReaderSettings.PageLayout?
    public var scrollMode: ReaderSettings.ScrollMode?
    public var direction: ReaderSettings.Direction?
    public var firstPageAlone: Bool?
    public var autoCrop: Bool?
    public var splitWidePages: Bool?
    public var background: ReaderSettings.Background?
    public var transition: ReaderSettings.Transition?
    public var preloadCount: Int?
    public var tapZonesEnabled: Bool?
    public var invertTapZones: Bool?
    public var doubleTapZoom: Bool?
    public var hideBarsOnScroll: Bool?

    public init() {}

    public var isEmpty: Bool { self == ReaderSettingsOverride() }
}

/// Thème de l'interface.
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case dark, light, system
}

/// Réglages généraux de l'app (hors lecteur).
public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme = .dark
    /// Moteur OCR (préparé pour la V2).
    public var ocrEngine: String = "auto"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
        ocrEngine = try c.decodeIfPresent(String.self, forKey: .ocrEngine) ?? "auto"
    }
}
