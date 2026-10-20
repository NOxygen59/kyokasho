// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ReaderCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TranslationSettingsSection()
                ReaderSettingsSections(settings: $model.readerDefaults)
                Section {
                    Toggle("Dessiner aussi au doigt", isOn: $model.drawWithFinger)
                } header: {
                    Text("Annotations")
                } footer: {
                    Text("Désactivé : seul l'Apple Pencil dessine, le doigt fait défiler. Le PDF original n'est jamais modifié.")
                }
                Section {
                    NavigationLink("Moteur, texte et banc d'essai") { OCRSettingsView() }
                } header: {
                    Text("OCR")
                } footer: {
                    Text("Moteur par défaut : \(model.readerDefaults.ocrEngine.label).")
                }
                Section("Google Drive") {
                    NavigationLink("Compte Google Drive") { DriveAccountView() }
                }
                Section {
                    NavigationLink("À propos") { AboutView() }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

/// Sections communes : réglages globaux du lecteur (valeurs par défaut).
struct ReaderSettingsSections: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        Section("Lecture") {
            Picker("Pages", selection: $settings.layout) {
                Text("Page simple").tag(ReaderSettings.PageLayout.single)
                Text("Double page").tag(ReaderSettings.PageLayout.double)
            }
            Picker("Défilement", selection: $settings.scrollMode) {
                Text("Paginé").tag(ReaderSettings.ScrollMode.paginated)
                Text("Continu").tag(ReaderSettings.ScrollMode.continuous)
            }
            Picker("Sens de lecture", selection: $settings.direction) {
                Text("Gauche → droite").tag(ReaderSettings.Direction.leftToRight)
                Text("Droite → gauche").tag(ReaderSettings.Direction.rightToLeft)
            }
            Toggle("Première page seule (double page)", isOn: $settings.firstPageAlone)
            Picker("Transition", selection: $settings.transition) {
                Text("Glissement").tag(ReaderSettings.Transition.slide)
                Text("Aucune").tag(ReaderSettings.Transition.none)
            }
        }
        Section {
            Picker("Fond", selection: $settings.background) {
                Text("Noir").tag(ReaderSettings.Background.black)
                Text("Gris foncé").tag(ReaderSettings.Background.darkGray)
                Text("Gris").tag(ReaderSettings.Background.gray)
                Text("Blanc").tag(ReaderSettings.Background.white)
                Text("Sépia").tag(ReaderSettings.Background.sepia)
            }
            Toggle("Rogner les marges blanches", isOn: $settings.autoCrop)
            Toggle("Couper les doubles pages scannées", isOn: $settings.splitWidePages)
            Stepper("Préchargement : \(settings.preloadCount) page(s)", value: $settings.preloadCount, in: 0...10)
        } header: {
            Text("Pages")
        } footer: {
            Text("Le glissement n'existe qu'en page simple paginée. Le préchargement prépare les aperçus des pages voisines ; PDFKit gère lui-même le rendu des pages affichées. Pivoter ou couper une seule page : menu ⋯ du lecteur.")
        }
        Section("Gestes") {
            Toggle("Zones de tap (précédent / suivant)", isOn: $settings.tapZonesEnabled)
            Toggle("Inverser les zones de tap", isOn: $settings.invertTapZones).disabled(!settings.tapZonesEnabled)
            Toggle("Double tap pour zoomer", isOn: $settings.doubleTapZoom)
            Toggle("Masquer les barres en tournant les pages", isOn: $settings.hideBarsOnScroll)
        }
    }
}

/// Réglages propres à un document : chaque ligne peut garder la valeur par défaut.
struct DocumentSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var reader: ReaderController
    @Environment(\.dismiss) private var dismiss
    @State private var override = ReaderSettingsOverride()

    var body: some View {
        let d = model.readerDefaults
        NavigationStack {
            Form {
                Section {
                    OptionalPicker("Pages", value: $override.layout, defaultValue: d.layout, options: [
                        (.single, "Page simple"), (.double, "Double page")])
                    OptionalPicker("Défilement", value: $override.scrollMode, defaultValue: d.scrollMode, options: [
                        (.paginated, "Paginé"), (.continuous, "Continu")])
                    OptionalPicker("Sens de lecture", value: $override.direction, defaultValue: d.direction, options: [
                        (.leftToRight, "Gauche → droite"), (.rightToLeft, "Droite → gauche")])
                    OptionalBool("Première page seule", value: $override.firstPageAlone, defaultValue: d.firstPageAlone)
                    OptionalPicker("Transition", value: $override.transition, defaultValue: d.transition, options: [
                        (.slide, "Glissement"), (.none, "Aucune")])
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("« Par défaut » suit les réglages généraux.")
                }
                Section("Pages") {
                    OptionalPicker("Fond", value: $override.background, defaultValue: d.background, options: [
                        (.black, "Noir"), (.darkGray, "Gris foncé"), (.gray, "Gris"), (.white, "Blanc"), (.sepia, "Sépia")])
                    OptionalBool("Rogner les marges", value: $override.autoCrop, defaultValue: d.autoCrop)
                    OptionalBool("Couper les doubles pages", value: $override.splitWidePages, defaultValue: d.splitWidePages)
                }
                Section("Gestes") {
                    OptionalBool("Zones de tap", value: $override.tapZonesEnabled, defaultValue: d.tapZonesEnabled)
                    OptionalBool("Inverser les zones", value: $override.invertTapZones, defaultValue: d.invertTapZones)
                    OptionalBool("Double tap zoom", value: $override.doubleTapZoom, defaultValue: d.doubleTapZoom)
                    OptionalBool("Masquer les barres", value: $override.hideBarsOnScroll, defaultValue: d.hideBarsOnScroll)
                }
                Section("OCR") {
                    OptionalPicker("Moteur", value: $override.ocrEngine, defaultValue: d.ocrEngine,
                                   options: OCREngineChoice.allCases.map { ($0, $0.label) })
                }
                Section {
                    Button("Tout remettre par défaut", role: .destructive) { override = ReaderSettingsOverride() }
                        .disabled(override.isEmpty)
                }
            }
            .navigationTitle("Ce document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .onAppear { override = reader.document.settingsOverride }
            .onChange(of: override) { reader.setDocumentOverride($0) }
        }
    }
}

struct OptionalPicker<T: Hashable>: View {
    let title: String
    @Binding var value: T?
    let defaultValue: T
    let options: [(T, String)]

    init(_ title: String, value: Binding<T?>, defaultValue: T, options: [(T, String)]) {
        self.title = title
        _value = value
        self.defaultValue = defaultValue
        self.options = options
    }

    var body: some View {
        let defaultLabel = options.first { $0.0 == defaultValue }?.1 ?? "—"
        Picker(title, selection: $value) {
            Text("Par défaut (\(defaultLabel))").tag(T?.none)
            ForEach(options.indices, id: \.self) { i in
                Text(options[i].1).tag(T?.some(options[i].0))
            }
        }
    }
}

struct OptionalBool: View {
    let title: String
    @Binding var value: Bool?
    let defaultValue: Bool

    init(_ title: String, value: Binding<Bool?>, defaultValue: Bool) {
        self.title = title
        _value = value
        self.defaultValue = defaultValue
    }

    var body: some View {
        OptionalPicker(title, value: $value, defaultValue: defaultValue, options: [(true, "Oui"), (false, "Non")])
    }
}

extension OCREngineChoice {
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .pdfText: return "Texte du PDF"
        case .vision: return "Apple Vision"
        }
    }
}

struct OCRSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var cache: (bytes: Int, pages: Int) = (0, 0)

    var body: some View {
        Form {
            Section {
                Picker("Moteur par défaut", selection: $model.readerDefaults.ocrEngine) {
                    ForEach(OCREngineChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("OCR automatique de la page lue", isOn: $model.appSettings.ocrAutoCurrentPage)
                Toggle("Afficher les zones reconnues", isOn: $model.appSettings.showOCRBoxes)
            } header: {
                Text("Moteur")
            } footer: {
                Text("Auto : texte intégré au PDF quand il existe (exact et instantané), sinon Apple Vision (japonais). Remplaçable par document. Vision ne lit pas encore le japonais vertical : NDLOCR-Lite arrive en V5.")
            }
            Section("Lecteur de texte") {
                Picker("Style", selection: $model.appSettings.textReader.style) {
                    Text("Défilement").tag(TextReaderSettings.Style.scroll)
                    Text("Pages").tag(TextReaderSettings.Style.pages)
                }
                Picker("Police", selection: $model.appSettings.textReader.font) {
                    Text("Gothique").tag(TextReaderSettings.Font.gothic)
                    Text("Mincho").tag(TextReaderSettings.Font.mincho)
                    Text("Système").tag(TextReaderSettings.Font.system)
                }
                Stepper("Taille : \(Int(model.appSettings.textReader.fontSize))", value: $model.appSettings.textReader.fontSize, in: 12...48, step: 1)
                VStack(alignment: .leading) {
                    Text("Interligne")
                    Slider(value: $model.appSettings.textReader.lineSpacing, in: 0...2)
                }
                VStack(alignment: .leading) {
                    Text("Marges horizontales : \(Int(model.appSettings.textReader.horizontalMargin)) pt")
                    Slider(value: $model.appSettings.textReader.horizontalMargin, in: 0...200, step: 4)
                }
                OCRTextView(text: "照明計画を考える。\n空間の印象は光で大きく変わります。", settings: model.appSettings.textReader)
                    .frame(height: 140)
            }
            Section {
                LabeledContent("Pages en cache", value: "\(cache.pages)")
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: Int64(cache.bytes), countStyle: .file))
                Button("Vider le cache OCR", role: .destructive) {
                    try? model.database.clearOCRCache()
                    refresh()
                }
            } header: {
                Text("Cache")
            } footer: {
                Text("Chaque page n'est lue qu'une fois par moteur ; changer de moteur n'efface pas les autres résultats.")
            }
            Section {
                NavigationLink("Banc d'essai") { BenchView() }
            } footer: {
                Text("Images + texte de référence : taux d'erreur de caractères et temps de chaque moteur.")
            }
        }
        .navigationTitle("OCR")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        cache = (try? model.database.ocrCacheStats()) ?? (0, 0)
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Text("Lecteur personnel de cours et de manuels. Usage strictement personnel, non distribué.")
                    .foregroundStyle(.secondary)
            }
            Section("Bibliothèques utilisées") {
                credit("GRDB.swift", "Gwendal Roué", "MIT", "https://github.com/groue/GRDB.swift")
            }
            Section("Inspirations (comportement)") {
                credit("Aidoku", "Aidoku", "GPL-3.0", "https://github.com/Aidoku/Aidoku")
                credit("Yomitan", "yomidevs", "GPL-3.0", "https://github.com/yomidevs/yomitan")
            }
        }
        .navigationTitle("À propos")
    }

    private func credit(_ name: String, _ author: String, _ license: String, _ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Link(name, destination: URL(string: url)!).font(.body.bold())
            Text("\(author) — licence \(license)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Clé DeepL (Trousseau) et quota du mois.
struct TranslationSettingsSection: View {
    @ObservedObject private var deepl = DeepLService.shared
    @State private var key = ""
    @State private var usage: String?

    var body: some View {
        Section {
            if deepl.hasKey {
                LabeledContent("Clé DeepL", value: deepl.maskedKey ?? "")
                if let usage { LabeledContent("Ce mois-ci", value: usage) }
                Button("Retirer la clé", role: .destructive) { deepl.setKey(nil); usage = nil }
            } else {
                SecureField("Clé API DeepL", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer") { deepl.setKey(key); key = ""; refresh() }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Créer une clé gratuite (DeepL API Free)", destination: URL(string: "https://www.deepl.com/pro-api")!)
            }
        } header: {
            Text("Traduction")
        } footer: {
            Text("Optionnel. Le texte de la page part chez DeepL seulement quand tu touches « Traduire » (panneau d'étude). La clé reste dans le Trousseau de l'iPad. Offre gratuite : 500 000 caractères par mois.")
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard deepl.hasKey else { return }
        Task {
            if let u = try? await deepl.usage() {
                usage = "\(u.used.formatted()) / \(u.limit.formatted()) caractères"
            }
        }
    }
}
