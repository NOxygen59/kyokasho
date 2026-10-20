// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence") {
                    Picker("Thème", selection: $model.appSettings.theme) {
                        Text("Sombre").tag(AppTheme.dark)
                        Text("Clair").tag(AppTheme.light)
                        Text("Système").tag(AppTheme.system)
                    }
                }
                ReaderSettingsSections(settings: $model.readerDefaults)
                Section {
                    Toggle("Dessiner aussi au doigt", isOn: $model.drawWithFinger)
                } header: {
                    Text("Annotations")
                } footer: {
                    Text("Désactivé : seul l'Apple Pencil dessine, le doigt fait défiler. Le PDF original n'est jamais modifié.")
                }
                Section {
                    NavigationLink("Moteur et options") { OCRSettingsPlaceholder() }
                } header: {
                    Text("OCR")
                } footer: {
                    Text("Arrive en V2 : Apple Vision (japonais), cache par page, comparaison des moteurs.")
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

struct OCRSettingsPlaceholder: View {
    var body: some View {
        Form {
            Section {
                Text("Rien à régler pour l'instant.").foregroundStyle(.secondary)
            } footer: {
                Text("Prévu en V2 : choix du moteur (Auto / Apple Vision), remplaçable par document, comparaison et banc d'essai.")
            }
        }
        .navigationTitle("OCR")
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
