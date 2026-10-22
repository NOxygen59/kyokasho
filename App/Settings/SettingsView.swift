// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false
    @ObservedObject private var downloads = ModelDownloads.shared
    @ObservedObject private var morphology = MorphologyService.shared
    @EnvironmentObject private var themes: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence et lecture") {
                    NavigationLink { ThemePickerView() } label: {
                        row("paintpalette", "Thème", tint: Atelier.Tint.annotate, detail: themes.theme.name)
                    }
                    NavigationLink { ReadingSettingsView() } label: {
                        row("book", "Pages et gestes", tint: Atelier.Tint.read)
                    }
                    NavigationLink { AnnotationSettingsView() } label: {
                        row("pencil.tip", "Apple Pencil et annotations", tint: Atelier.Tint.annotate)
                    }
                }
                Section {
                    NavigationLink { DictionaryManagerView() } label: {
                        row("character.book.closed.ja", "Dictionnaires", tint: Atelier.Tint.japanese)
                    }
                    NavigationLink { OCRSettingsView() } label: {
                        row("text.viewfinder", "Lecture des scans (OCR)", tint: Atelier.Tint.japanese,
                            detail: model.readerDefaults.ocrEngine.label)
                    }
                    NavigationLink { Form { TranslationSettingsSection() }.navigationTitle("Traduction") } label: {
                        row("character.bubble", "Traduction (DeepL)", tint: Atelier.Tint.ai)
                    }
                } header: {
                    Text("Japonais")
                } footer: {
                    Text("Dictionnaires : fiches au toucher. Lecture des scans : quel moteur lit le texte des pages photo, relecture, mise en forme. Traduction : DeepL (en ligne, seulement quand tu le demandes).")
                }
                Section {
                    NavigationLink { ModelsView() } label: {
                        row("shippingbox", "Modèles d'IA et outils", tint: Atelier.Tint.ai,
                            detail: "\(downloads.installed.count + (morphology.state == .ready ? 1 : 0)) installé(s)")
                    }
                } header: {
                    Text("Téléchargements")
                } footer: {
                    Text("Ce que fait chaque modèle (OCR, furigana, IA, mise en forme, netteté), ce qui est conseillé et où le régler.")
                }
                Section("Cartes") {
                    NavigationLink { ReviewSettingsView() } label: {
                        row("rectangle.stack", "Révisions et export Anki", tint: Atelier.Tint.japanese)
                    }
                }
                Section {
                    Toggle(isOn: $monitorEnabled) {
                        row("gauge.with.dots.needle.33percent", "Moniteur de ressources", tint: Atelier.Tint.read)
                    }
                } header: {
                    Text("Outils")
                } footer: {
                    Text("CPU, mémoire et images par seconde de l'app, dans un panneau flottant ouvert depuis le menu « … » du lecteur.")
                }
                DiagnosticsSection()
                Section("Stockage") {
                    NavigationLink { StorageUsageView() } label: {
                        row("internaldrive", "Place prise par l'app", tint: Atelier.Tint.cloud)
                    }
                }
                Section("Comptes") {
                    NavigationLink { DriveAccountView() } label: {
                        row("externaldrive.badge.icloud", "Google Drive", tint: Atelier.Tint.cloud)
                    }
                }
                Section {
                    NavigationLink { AboutView() } label: { row("info.circle", "À propos", tint: Atelier.textSecondary) }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func row(_ icon: String, _ title: String, tint: Color, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 30, height: 30).background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
            if let detail {
                Spacer()
                Text(detail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Réglages → Lecture : réglages par défaut du lecteur.
struct ReadingSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form { ReaderSettingsSections(settings: $model.readerDefaults) }
            .navigationTitle("Pages et gestes")
    }
}

/// Réglages → Apple Pencil et annotations.
struct AnnotationSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("pencil.lookupOption") private var pencilOption = false

    var body: some View {
        Form {
            Section {
                Toggle("Dessiner aussi au doigt", isOn: $model.drawWithFinger)
            } footer: {
                Text("Désactivé : seul l'Apple Pencil dessine, le doigt fait défiler. Le PDF original n'est jamais modifié.")
            }
            Section {
                Toggle("Bouton « Pencil → dictionnaire »", isOn: $pencilOption)
            } footer: {
                Text("Ajoute un bouton ✎ dans la barre d'outils du lecteur. Allumé, toucher un mot avec le Pencil ouvre sa fiche dans le dictionnaire (le doigt et la souris gardent leur rôle).")
            }
        }
        .navigationTitle("Apple Pencil")
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
        Section {
            Toggle("Double tap pour zoomer", isOn: $settings.doubleTapZoom)
            Toggle("Masquer les barres en tournant les pages", isOn: $settings.hideBarsOnScroll)
        } header: {
            Text("Gestes")
        } footer: {
            Text("Tourner les pages : glisser au doigt, ou avec un clavier / une souris, les flèches sur les bords et les touches ← →. Un tap montre ou cache les barres.")
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
                    Text("Ces choix valent pour ce document seulement (les autres gardent les leurs). « Par défaut » suit les réglages généraux.")
                }
                Section("Pages") {
                    OptionalPicker("Fond", value: $override.background, defaultValue: d.background, options: [
                        (.black, "Noir"), (.darkGray, "Gris foncé"), (.gray, "Gris"), (.white, "Blanc"), (.sepia, "Sépia")])
                    OptionalBool("Rogner les marges", value: $override.autoCrop, defaultValue: d.autoCrop)
                    OptionalBool("Couper les doubles pages", value: $override.splitWidePages, defaultValue: d.splitWidePages)
                }
                Section("Gestes") {
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
            // Enregistré pour ce document seulement, et seulement s'il a vraiment changé
            // (pas à l'ouverture de la feuille).
            .onChange(of: override) { new in
                if new != reader.document.settingsOverride { reader.setDocumentOverride(new) }
            }
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
        case .ndlocr: return "NDLOCR-Lite"
        case .ppocr5: return "PP-OCRv5"
        case .glmocr: return "GLM-OCR (IA)"
        }
    }
}

struct OCRSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("study.layoutEngine") private var layoutEngineRaw = LayoutDetector.Engine.geometry.rawValue
    @AppStorage(ReaderController.aiRereadKey) private var aiReread = true
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
                Text("Auto : texte intégré au PDF quand il existe (exact et instantané). Sinon NDLOCR-Lite s'il est installé (livres japonais, vertical), puis PP-OCRv5, puis Apple Vision. Remplaçable par document. Un moteur choisi mais pas téléchargé renvoie une erreur.")
            }
            Section {
                NavigationLink { ModelsView() } label: { Label("Modèles d'IA et outils (à quoi sert chacun)", systemImage: "shippingbox") }
            }
            Section {
                Toggle("Relire les lignes douteuses avec GLM-OCR", isOn: $aiReread)
            } header: {
                Text("Relecture")
            } footer: {
                Text("Chaque page lue est relue avec ton dictionnaire : les caractères qui se ressemblent (未/末, 土/士, ロ/口…) sont corrigés quand ça forme un vrai mot, le reste est souligné en orange. Si GLM-OCR est installé, seules les lignes encore douteuses lui sont envoyées, en fond (rien ne part en ligne).")
            }
            Section {
                LayoutEnginePicker(selection: $layoutEngineRaw)
            } header: {
                Text("Mise en page du texte extrait")
            } footer: {
                Text("PP-DocLayout et DocLayout-YOLO repèrent titres, colonnes et tableaux ; « Géométrie » marche sans modèle. Même choix que dans le panneau d'étude.")
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
        .navigationTitle("Lecture des scans (OCR)")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        cache = (try? model.database.ocrCacheStats()) ?? (0, 0)
    }
}

struct AboutView: View {
    @ObservedObject private var update = AppUpdate.shared
    @Environment(\.openURL) private var openURL

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                if let latest = update.available {
                    Button { openURL(latest.page) } label: {
                        Label("Télécharger la version \(latest.version)", systemImage: "arrow.down.app")
                    }
                } else {
                    Button { Task { await update.check() } } label: {
                        switch update.state {
                        case .checking: Label("Vérification…", systemImage: "hourglass")
                        case .upToDate: Label("À jour — vérifier encore", systemImage: "checkmark.circle")
                        case .failed: Label("Pas de réponse — réessayer", systemImage: "exclamationmark.triangle")
                        case .idle: Label("Vérifier les mises à jour", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(update.state == .checking)
                }
                Text("Lecteur personnel de cours et de manuels. Usage strictement personnel, non distribué.")
                    .foregroundStyle(.secondary)
            }
            GitHubUpdateSection()
            Section("Bibliothèques utilisées") {
                credit("GRDB.swift", "Gwendal Roué", "MIT", "https://github.com/groue/GRDB.swift")
                credit("ZIPFoundation", "Thomas Zoechling", "MIT", "https://github.com/weichsel/ZIPFoundation")
                credit("Yomitan (déconjugaison, texte japonais)", "yomidevs", "GPL-3.0", "https://github.com/yomidevs/yomitan")
                credit("swift-fsrs (calcul des révisions)", "Ben Smiley", "MIT", "https://github.com/open-spaced-repetition/swift-fsrs")
            }
            Section("IA locale (MLX)") {
                credit("MLX / mlx-swift-lm (fork iOS 16)", "Apple · NOxygen59", "MIT", "https://github.com/NOxygen59/mlx-swift-lm")
                credit("swift-transformers (tokenizers)", "Hugging Face", "Apache-2.0", "https://github.com/huggingface/swift-transformers")
                credit("OvisOCR2 (modèle téléchargé)", "ATH-MaaS · conversion MLX tokimoa", "Apache-2.0", "https://huggingface.co/ATH-MaaS/OvisOCR2")
            }
            Section("Analyseur japonais") {
                credit("MeCab", "Taku Kudo · NTT", "BSD", "https://github.com/taku910/mecab")
                credit("UniDic (dictionnaire téléchargé)", "UniDic Consortium", "BSD", "https://clrd.ninjal.ac.jp/unidic/")
                credit("unidic-lite", "Paul McCann", "MIT", "https://github.com/polm/unidic-lite")
            }
            Section("OCR") {
                credit("ONNX Runtime", "Microsoft", "MIT", "https://github.com/microsoft/onnxruntime-swift-package-manager")
                credit("PP-OCRv5 (modèles téléchargés)", "PaddlePaddle · RapidAI", "Apache-2.0", "https://github.com/PaddlePaddle/PaddleOCR")
                credit("NDLOCR-Lite (modèles téléchargés)", "国立国会図書館 (National Diet Library)", "CC-BY-4.0", "https://github.com/ndl-lab/ndlocr-lite")
                credit("PP-DocLayout v3 (mise en page, modèle téléchargé)", "PaddlePaddle · conversion RapidAI", "Apache-2.0", "https://github.com/RapidAI/RapidLayout")
                credit("DocLayout-YOLO (mise en page de MinerU, modèle téléchargé)", "OpenDataLab · conversion RapidAI", "AGPL-3.0", "https://github.com/opendatalab/DocLayout-YOLO")
                credit("DE-GAN (netteté des scans, modèle téléchargé)", "M. A. Souibgui, Y. Kessentini", "GPL-3.0", "https://github.com/dali92002/DE-GAN")
                credit("GLM-OCR (modèle téléchargé)", "Zhipu AI · conversion mlx-community", "MIT", "https://huggingface.co/zai-org/GLM-OCR")
                credit("MLX Swift, mlx-swift-lm (GLM-OCR porté)", "ml-explore (Apple)", "MIT", "https://github.com/ml-explore/mlx-swift-lm")
                credit("swift-transformers (tokenizer)", "Hugging Face", "Apache-2.0", "https://github.com/huggingface/swift-transformers")
            }
            Section("Format de fichier") {
                credit("genanki (format .apkg d'Anki, aucun code copié)", "Kerrick Staley", "MIT", "https://github.com/kerrickstaley/genanki")
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
    @AppStorage(DefinitionTranslations.autoKey) private var autoDefinitions = false

    var body: some View {
        Section {
            if deepl.hasKey {
                LabeledContent("Clé DeepL", value: deepl.maskedKey ?? "")
                Toggle("Traduire tout seul les définitions anglaises", isOn: $autoDefinitions)
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
            Text("Optionnel. Le texte de la page part chez DeepL seulement quand tu touches « Traduire » (panneau d'étude ou dictionnaire), ou si tu actives la traduction automatique des définitions anglaises (la définition anglaise part alors à chaque mot recherché pas encore traduit). La clé reste dans le Trousseau de l'iPad. Offre gratuite : 500 000 caractères par mois.")
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

/// Tous les modèles à télécharger (OCR, netteté des scans), avec leurs liens.
// FDR-V7 : une page par IA locale (état, mémoire, décharger, réglages, journal) + chat Qwen3-VL (chargé à l'ouverture, déchargé en quittant).
struct ModelsView: View {
    var body: some View {
        Form {
            Section {
                Text("Rien n'est obligatoire : l'app marche sans aucun modèle. Pour un livre japonais scanné, le duo conseillé est **NDLOCR-Lite** (lire le texte) + **MeCab** (furigana justes). Le reste ajoute des options.")
                    .font(.footnote)
            } footer: {
                Text("Tout reste sur l'iPad (Application Support), hors de l'app. Le téléchargement reprend s'il est coupé ; chaque fichier est vérifié (empreinte SHA-256). Supprimer un modèle ne perd pas les pages déjà lues.")
            }
            OCRModelsSection(group: .ocr)
            MorphologySection()
            OCRModelsSection(group: .ai)
            OCRModelsSection(group: .layout)
            OCRModelsSection(group: .sharpen)
        }
            .navigationTitle("Modèles d'IA et outils")
    }
}
