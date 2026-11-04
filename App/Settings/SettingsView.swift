// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ONNXOCRKit
import ReaderCore
import SwiftUI

/// Accueil centré sur les usages ; la recherche donne accès directement à chaque réglage.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [SettingsRoute] {
        SettingsRoute.allCases.filter { $0.isAvailable && $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Ton espace de lecture").font(.title2.weight(.semibold)).foregroundStyle(Atelier.textPrimary)
                            Text("Personnalise l'app selon ce que tu veux faire. Les réglages d'un livre restent accessibles depuis son menu « … ».")
                                .font(.subheadline).foregroundStyle(Atelier.textSecondary)
                        }.padding(.vertical, 8)
                            .listRowBackground(Atelier.surface)
                    }
                    Section("Personnaliser") {
                        area(.general)
                        area(.reading)
                    }
                    Section("Comprendre et apprendre") {
                        area(.aiText)
                        area(.japaneseReview)
                    }
                    Section("Gérer") {
                        area(.data)
                        area(.help)
                    }
                } else {
                    Section("Résultats") {
                        if matches.isEmpty {
                            Text("Aucun réglage trouvé. Essaie « zoom », « traduction » ou « stockage ».")
                                .foregroundStyle(Atelier.textSecondary)
                        }
                        ForEach(matches) { route in SettingsRouteLink(route: route) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Atelier.canvas)
            .searchable(text: $query, prompt: String(localized: "Chercher un réglage"))
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }
    }

    private func area(_ area: SettingsArea) -> some View {
        NavigationLink { SettingsAreaView(area: area) } label: {
            SettingsEntryRow(icon: area.icon, title: area.title, subtitle: area.subtitle, tint: area.tint)
        }
        .listRowBackground(Atelier.surface)
    }
}

/// Réglages → Lecture : réglages par défaut du lecteur.
struct ReadingSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("Ces choix s'appliquent par défaut à tes livres. Un livre peut garder ses propres réglages depuis le menu « … » du lecteur.")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            }
            ReaderSettingsSections(settings: $model.readerDefaults)
            Section {
                NavigationLink("Options avancées") {
                    Form {
                        Section {
                            Stepper("Pages voisines : \(model.readerDefaults.preloadCount)", value: $model.readerDefaults.preloadCount, in: 0...10)
                        } header: { Text("Précharger les aperçus") } footer: {
                            Text("Prépare les miniatures voisines. Une valeur plus faible réduit le travail en arrière-plan ; 0 désactive ce préchargement.")
                        }
                    }.navigationTitle("Options de lecture")
                }
            }
        }
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
    @AppStorage("reader.trackpadScrollPassThrough") private var trackpadScrollPassThrough = true

    var body: some View {
        Section {
            Picker("Pages", selection: $settings.layout) {
                Text("Automatique selon l'orientation").tag(ReaderSettings.PageLayout.auto)
                Text("Page simple").tag(ReaderSettings.PageLayout.single)
                Text("Double page").tag(ReaderSettings.PageLayout.double)
            }
            Picker("Défilement", selection: $settings.scrollMode) {
                Text("Page par page").tag(ReaderSettings.ScrollMode.paginated)
                Text("Continu").tag(ReaderSettings.ScrollMode.continuous)
            }
            Picker("Sens de lecture", selection: $settings.direction) {
                Text("Gauche → droite").tag(ReaderSettings.Direction.leftToRight)
                Text("Droite → gauche").tag(ReaderSettings.Direction.rightToLeft)
            }
            Toggle("Couverture seule avant les doubles pages", isOn: $settings.firstPageAlone)
                .disabled(settings.layout == .single)
            Picker("Transition", selection: $settings.transition) {
                Text("Glissement").tag(ReaderSettings.Transition.slide)
                Text("Aucune").tag(ReaderSettings.Transition.none)
            }
        } header: {
            Text("Disposition et navigation")
        } footer: {
            Text("Automatique : une page en portrait, deux en paysage. « Droite → gauche » suit l'ordre des livres japonais. La transition par glissement est disponible en page simple, page par page.")
        }
        Section {
            Picker("Fond autour des pages", selection: $settings.background) {
                Text("Noir").tag(ReaderSettings.Background.black)
                Text("Gris foncé").tag(ReaderSettings.Background.darkGray)
                Text("Gris").tag(ReaderSettings.Background.gray)
                Text("Blanc").tag(ReaderSettings.Background.white)
                Text("Sépia").tag(ReaderSettings.Background.sepia)
            }
            Toggle("Rogner les marges blanches", isOn: $settings.autoCrop)
            Toggle("Couper les doubles pages scannées", isOn: $settings.splitWidePages)
        } header: {
            Text("Pages")
        } footer: {
            Text("Le rognage cache les marges blanches ; la découpe sépare les scans contenant deux pages. Pivoter ou découper une seule page : menu « … » du livre. Le PDF d'origine reste intact.")
        }
        Section {
            Toggle("Double tap pour zoomer", isOn: $settings.doubleTapZoom)
            Toggle("Masquer les barres en tournant les pages", isOn: $settings.hideBarsOnScroll)
            Toggle("Laisser le trackpad déplacer la page", isOn: $trackpadScrollPassThrough)
        } header: {
            Text("Gestes")
        } footer: {
            Text("Le trackpad déplace la page avec deux doigts ; le glissement au doigt tourne les pages. Désactive cette option si les gestes du lecteur te convenaient mieux. Un tap montre ou cache les barres.")
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
                    // Repère de l'accueil (RET-039, #54) : requête ciblée, la copie du lecteur suit pour ne pas
                    // réécrire l'ancienne valeur en enregistrant les autres réglages.
                    Picker("Catégorie", selection: Binding(get: { reader.document.category }, set: { category in
                        reader.document.category = category
                        model.setCategory(reader.document.id, category)
                    })) {
                        Text("Non classé").tag(DocumentCategory?.none)
                        ForEach(DocumentCategory.allCases, id: \.self) { Text($0.title).tag(DocumentCategory?.some($0)) }
                    }
                }
                Section {
                    OptionalPicker(String(localized: "Pages"), value: $override.layout, defaultValue: d.layout, options: [
                        (.auto, String(localized: "Automatique selon l'orientation")), (.single, String(localized: "Page simple")), (.double, String(localized: "Double page"))])
                    OptionalPicker(String(localized: "Défilement"), value: $override.scrollMode, defaultValue: d.scrollMode, options: [
                        (.paginated, String(localized: "Paginé")), (.continuous, String(localized: "Continu"))])
                    OptionalPicker(String(localized: "Sens de lecture"), value: $override.direction, defaultValue: d.direction, options: [
                        (.leftToRight, String(localized: "Gauche → droite")), (.rightToLeft, String(localized: "Droite → gauche"))])
                    OptionalBool(String(localized: "Première page seule"), value: $override.firstPageAlone, defaultValue: d.firstPageAlone)
                    OptionalPicker(String(localized: "Transition"), value: $override.transition, defaultValue: d.transition, options: [
                        (.slide, String(localized: "Glissement")), (.none, String(localized: "Aucune"))])
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("Ces choix valent pour ce document seulement (les autres gardent les leurs). « Par défaut » suit les réglages généraux.")
                }
                Section("Pages") {
                    OptionalPicker(String(localized: "Fond"), value: $override.background, defaultValue: d.background, options: [
                        (.black, String(localized: "Noir")), (.darkGray, String(localized: "Gris foncé")), (.gray, String(localized: "Gris")), (.white, String(localized: "Blanc")), (.sepia, String(localized: "Sépia"))])
                    OptionalBool(String(localized: "Rogner les marges"), value: $override.autoCrop, defaultValue: d.autoCrop)
                    OptionalBool(String(localized: "Couper les doubles pages"), value: $override.splitWidePages, defaultValue: d.splitWidePages)
                }
                Section("Gestes") {
                    OptionalBool(String(localized: "Double tap zoom"), value: $override.doubleTapZoom, defaultValue: d.doubleTapZoom)
                    OptionalBool(String(localized: "Masquer les barres"), value: $override.hideBarsOnScroll, defaultValue: d.hideBarsOnScroll)
                }
                Section("OCR") {
                    OptionalPicker(String(localized: "Moteur"), value: $override.ocrEngine, defaultValue: d.ocrEngine,
                                   options: OCREngineChoice.selectable.map { ($0, $0.label) })
                }
                Section {
                    Button("Revenir aux réglages généraux", role: .destructive) { override = ReaderSettingsOverride() }
                        .disabled(override.isEmpty)
                } footer: {
                    Text("Réinitialise les choix de lecture et le moteur OCR propres à ce livre.")
                }
                Section {
                    DocumentLanguagePicker(documentId: reader.document.id)
                } header: {
                    Text("Langue du document")
                } footer: {
                    Text("Guide les prochaines lectures OvisOCR2 et corrige les confusions d'écriture connues. Les pages déjà enregistrées ne sont pas rescannées ; rouvre le livre pour actualiser leur affichage.")
                }
                PageAdditionHistorySection(documentId: reader.document.id)
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
        OptionalPicker(title, value: $value, defaultValue: defaultValue, options: [(true, String(localized: "Oui")), (false, String(localized: "Non"))])
    }
}

extension OCREngineChoice {
    var label: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .pdfText: return String(localized: "Texte du PDF")
        case .vision: return String(localized: "Apple Vision")
        case .ndlocr: return "NDLOCR-Lite"
        case .ppocr5: return "PP-OCRv5"
        case .glmocr: return String(localized: "GLM-OCR (IA)")
        }
    }
}

struct OCRSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(DocumentScan.autoKey) private var autoScan = true

    var body: some View {
        Form {
            Section {
                Toggle("Précharger le texte de la page affichée", isOn: $model.appSettings.ocrAutoCurrentPage)
                Toggle("Montrer les zones de texte sur la page", isOn: $model.appSettings.showOCRBoxes)
            } header: { Text("Reconnaître le texte") } footer: {
                Text("L'OCR avec positions sert à sélectionner les mots sur la page. Les furigana peuvent aussi déclencher cette lecture, même si le préchargement est désactivé. Le traitement reste hors ligne.")
            }
            Section {
                Toggle("Lire les nouvelles pages avec OvisOCR2", isOn: $autoScan)
            } header: { Text("Lecture IA du document") } footer: {
                Text("À l'import et à l'ouverture, OvisOCR2 lit les pages non encore enregistrées, si le modèle est installé. Ce texte sert au panneau, aux furigana et au chat ; les pages déjà lues ne sont pas relancées.")
            }
            Section {
                NavigationLink { OCRTextAppearanceSettingsView() } label: {
                    Label("Police, taille et présentation du texte", systemImage: "textformat.size")
                }
                NavigationLink { ModelsView() } label: {
                    Label("Ajouter des outils de lecture hors ligne", systemImage: "arrow.down.circle")
                }
            }
            Section {
                NavigationLink { OCRAdvancedSettingsView() } label: {
                    Label("Options OCR avancées", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Choix du moteur, vérification des caractères, mise en page et textes enregistrés. Tu peux garder les valeurs actuelles pour commencer.")
            }
        }.navigationTitle("Texte des pages")
    }
}

struct OCRTextAppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
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
        }.navigationTitle("Présentation du texte")
    }
}

struct OCRAdvancedSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @AppStorage("study.layoutEngine") private var layoutEngineRaw = LayoutDetector.Engine.geometry.rawValue
    @AppStorage(ReaderController.aiRereadKey) private var aiReread = true
    @State private var confirmClear = false
    @State private var cacheError: String?
    @State private var cache: (bytes: Int, results: Int) = (0, 0)

    var body: some View {
        Form {
            Section {
                Picker("Moteur par défaut", selection: $model.readerDefaults.ocrEngine) {
                    ForEach(OCREngineChoice.selectable, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Moteur")
            } footer: {
                Text("Auto : texte intégré au PDF quand il existe (exact et instantané). Sinon NDLOCR-Lite s'il est installé (livres japonais, vertical), puis PP-OCRv5, puis Apple Vision. Remplaçable par document. Un moteur choisi mais pas téléchargé renvoie une erreur.")
            }
            if localAIAvailable {
                Section {
                    Toggle("Relire les lignes douteuses avec GLM-OCR", isOn: $aiReread)
                } header: {
                    Text("Relecture")
                } footer: {
                    Text("Chaque page lue est relue avec ton dictionnaire : les caractères qui se ressemblent (未/末, 土/士, ロ/口…) sont corrigés quand ça forme un vrai mot, le reste est souligné en orange. Si GLM-OCR est installé, seules les lignes encore douteuses lui sont envoyées, en fond (rien ne part en ligne).")
                }
            }
            Section {
                LayoutEnginePicker(selection: $layoutEngineRaw)
            } header: {
                Text("Mise en page du texte extrait")
            } footer: {
                Text("PP-DocLayout et DocLayout-YOLO repèrent titres, colonnes et tableaux ; « Géométrie » marche sans modèle. Même choix que dans le panneau d'étude.")
            }
            Section {
                LabeledContent("Résultats OCR en cache", value: "\(cache.results)")
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: Int64(cache.bytes), countStyle: .file))
                Button("Effacer le cache OCR avec positions…", role: .destructive) { confirmClear = true }
                    .disabled(analysis.progress != nil)
            } header: {
                Text("Cache")
            } footer: {
                Text("Efface les résultats des moteurs OCR et leurs corrections manuelles ; la fiabilité du document devra être recalculée. Les lectures OvisOCR2, leurs traductions, les PDF, notes et cartes restent conservés.")
            }
            Section {
                NavigationLink("Banc d'essai") { BenchView() }
            } footer: {
                Text("Images + texte de référence : taux d'erreur de caractères et temps de chaque moteur.")
            }
        }
        .navigationTitle("Options OCR avancées")
        .onAppear(perform: refresh)
        .confirmationDialog("Effacer le cache OCR et remettre les analyses à refaire ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer ce cache OCR", role: .destructive) {
                guard analysis.progress == nil else { return }
                do {
                    try model.database.clearOCRCache()
                    analysis.invalidateReports(for: model.documents.map(\.id))
                    refresh()
                }
                catch { cacheError = error.localizedDescription }
            }
            Button("Annuler", role: .cancel) {}
        }
        .alert("Cache OCR", isPresented: Binding(get: { cacheError != nil }, set: { if !$0 { cacheError = nil } })) {
            Button("OK") { cacheError = nil }
        } message: { Text(cacheError ?? "") }
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
                credit(String(localized: "Yomitan (déconjugaison, texte japonais)"), "yomidevs", "GPL-3.0", "https://github.com/yomidevs/yomitan")
                credit(String(localized: "swift-fsrs (calcul des révisions)"), "Ben Smiley", "MIT", "https://github.com/open-spaced-repetition/swift-fsrs")
            }
            Section("IA locale (MLX)") {
                credit(String(localized: "MLX / mlx-swift-lm (fork iOS 16)"), "Apple · NOxygen59", "MIT", "https://github.com/NOxygen59/mlx-swift-lm")
                credit(String(localized: "swift-transformers (tokenizers)"), "Hugging Face", "Apache-2.0", "https://github.com/huggingface/swift-transformers")
                credit(String(localized: "OvisOCR2 (modèle téléchargé)"), "ATH-MaaS · conversion MLX tokimoa", "Apache-2.0", "https://huggingface.co/ATH-MaaS/OvisOCR2")
                credit(String(localized: "Qwen3.5-4B (chat, modèle téléchargé)"), "Alibaba Qwen · conversion mlx-community", "Apache-2.0", "https://huggingface.co/Qwen/Qwen3.5-4B")
            }
            Section("Analyseur japonais") {
                credit("MeCab", "Taku Kudo · NTT", "BSD", "https://github.com/taku910/mecab")
                credit(String(localized: "UniDic (dictionnaire téléchargé)"), "UniDic Consortium", "BSD", "https://clrd.ninjal.ac.jp/unidic/")
                credit("unidic-lite", "Paul McCann", "MIT", "https://github.com/polm/unidic-lite")
            }
            Section("OCR") {
                credit(String(localized: "ONNX Runtime"), "Microsoft", "MIT", "https://github.com/microsoft/onnxruntime-swift-package-manager")
                credit(String(localized: "PP-OCRv5 (modèles téléchargés)"), "PaddlePaddle · RapidAI", "Apache-2.0", "https://github.com/PaddlePaddle/PaddleOCR")
                credit(String(localized: "NDLOCR-Lite (modèles téléchargés)"), "国立国会図書館 (National Diet Library)", "CC-BY-4.0", "https://github.com/ndl-lab/ndlocr-lite")
                credit(String(localized: "PP-DocLayout v3 (mise en page, modèle téléchargé)"), "PaddlePaddle · conversion RapidAI", "Apache-2.0", "https://github.com/RapidAI/RapidLayout")
                credit(String(localized: "DocLayout-YOLO (mise en page de MinerU, modèle téléchargé)"), "OpenDataLab · conversion RapidAI", "AGPL-3.0", "https://github.com/opendatalab/DocLayout-YOLO")
                credit(String(localized: "DE-GAN (netteté des scans, modèle téléchargé)"), "M. A. Souibgui, Y. Kessentini", "GPL-3.0", "https://github.com/dali92002/DE-GAN")
                credit(String(localized: "GLM-OCR (modèle téléchargé)"), "Zhipu AI · conversion mlx-community", "MIT", "https://huggingface.co/zai-org/GLM-OCR")
                credit(String(localized: "MLX Swift, mlx-swift-lm (GLM-OCR porté)"), "ml-explore (Apple)", "MIT", "https://github.com/ml-explore/mlx-swift-lm")
                credit(String(localized: "swift-transformers (tokenizer)"), "Hugging Face", "Apache-2.0", "https://github.com/huggingface/swift-transformers")
            }
            Section("Format de fichier") {
                credit(String(localized: "genanki (format .apkg d'Anki, aucun code copié)"), "Kerrick Staley", "MIT", "https://github.com/kerrickstaley/genanki")
            }
            Section("Inspirations (comportement)") {
                credit(String(localized: "Aidoku"), String(localized: "Aidoku"), "GPL-3.0", "https://github.com/Aidoku/Aidoku")
                credit(String(localized: "Yomitan"), "yomidevs", "GPL-3.0", "https://github.com/yomidevs/yomitan")
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
                usage = String(localized: "\(u.used.formatted()) / \(u.limit.formatted()) caractères")
            }
        }
    }
}

/// Tous les modèles à télécharger (OCR, netteté des scans), avec leurs liens.
struct ModelsView: View {
    @AppStorage(AITaskPill.visibleKey) private var showAIBadges = true
    @AppStorage(LocalServerVLM.enabledKey) private var localVLM = false
    @AppStorage(LocalServerVLM.urlKey) private var localVLMURL = LocalServerVLM.defaultURL

    var body: some View {
        Form {
            if !localAIAvailable {
                // Version Mac (#55) : MLX absent ; OvisOCR2 (le même modèle, en GGUF) par un serveur llama.cpp local.
                Section {
                    Text("Sur ce Mac, le chat et les gros modèles d'IA sont désactivés. NDLOCR-Lite et PP-OCRv5 se téléchargent ci-dessous. OvisOCR2 marche par un serveur llama.cpp lancé sur ce Mac (même modèle que sur l'iPad, converti en GGUF). L'OCR Apple Vision, les dictionnaires, les cartes et l'import de paquets .kyokasho marchent toujours.")
                        .font(.footnote)
                    Toggle("OvisOCR2 par serveur local", isOn: $localVLM)
                    TextField("Adresse du serveur", text: $localVLMURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(!localVLM)
                } header: {
                    Text("Version Mac")
                } footer: {
                    Text("Dans Terminal : brew install llama.cpp, puis llama-server -hf bartowski/ATH-MaaS_OvisOCR2-GGUF:Q4_K_M --port 8080 (environ 600 Mo téléchargés une fois). Seule une adresse de ce Mac est acceptée : rien ne part sur Internet. Lent sur un processeur Intel : compte une à plusieurs minutes par page.")
                }
            }
            Section {
                Text("Rien n'est obligatoire : l'app marche sans aucun modèle. Pour un livre japonais scanné, le duo conseillé est **NDLOCR-Lite** (lire le texte) + **MeCab** (furigana justes). Le reste ajoute des options.")
                    .font(.footnote)
            } footer: {
                Text("Tout reste sur l'iPad (Application Support), hors de l'app. Le téléchargement reprend s'il est coupé ; chaque fichier est vérifié (empreinte SHA-256). Supprimer un modèle ne perd pas les pages déjà lues.")
            }
            Section {
                Toggle("Afficher l'activité des IA", isOn: $showAIBadges)
            } footer: {
                Text("De petites pastilles indiquent ce que fait chaque IA. Elles deviennent plus discrètes quand un modèle reste simplement chargé en mémoire.")
            }
            Section {
                ForEach([ModelSpec.ovisocr2, .qwen3vl4b, .qwen35chat4b, .glmocr, .ndlocr, .ppocr5].filter(\.runsOnThisDevice)) { spec in
                    NavigationLink { AIModelDetailView(spec: spec) } label: { Text(spec.title) }
                }
            } header: {
                Text("Chaque IA")
            } footer: {
                Text("État, mémoire, « Décharger », réglages propres et dernières tâches. Qwen3-VL et Qwen3.5 : conversation.")
            }
            if localAIAvailable {
                Section {
                    NavigationLink { AIChatSettingsView() } label: {
                        Label("Consignes et paramètres du chat", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Pour chaque modèle de chat : consigne générale, préréglages (résumer, expliquer les formules, professeur de japonais, traduction mot à mot), température, longueur…")
                }
            }
            OCRModelsSection(group: .ocr)
            MorphologySection()
            if localAIAvailable { OCRModelsSection(group: .ai) }
            OCRModelsSection(group: .layout)
            OCRModelsSection(group: .sharpen)
        }
            .navigationTitle("Modèles d'IA et outils")
    }
}

extension OCREngineChoice {
    /// Moteurs proposés : GLM-OCR demande MLX, absent de la version Mac Intel (#55).
    static var selectable: [OCREngineChoice] {
        allCases.filter { localAIAvailable || $0 != .glmocr }
    }
}
