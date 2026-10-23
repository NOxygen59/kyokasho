// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Les liens et la recherche partagent le même catalogue : aucun outil ne disparaît dans les sous-pages.
enum SettingsArea: String, Identifiable {
    case reading, japanese, files, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reading: return "Lecture et apparence"
        case .japanese: return "Japonais et traduction"
        case .files: return "Fichiers et comptes"
        case .help: return "Aide et informations"
        }
    }
    var subtitle: String {
        switch self {
        case .reading: return "Thèmes, double page, fenêtre OCR et Pencil"
        case .japanese: return "Comprendre les mots et le texte de tes livres"
        case .files: return "Place disponible et connexion à Google Drive"
        case .help: return "Résoudre un problème et vérifier les mises à jour"
        }
    }
    var icon: String {
        switch self {
        case .reading: return "book"
        case .japanese: return "character.book.closed.ja"
        case .files: return "folder"
        case .help: return "questionmark.circle"
        }
    }
    var tint: Color {
        switch self {
        case .reading: return Atelier.Tint.read
        case .japanese: return Atelier.Tint.japanese
        case .files: return Atelier.Tint.cloud
        case .help: return Atelier.Tint.annotate
        }
    }
    var routes: [SettingsRoute] {
        switch self {
        case .reading: return [.theme, .reading, .panel, .pencil]
        case .japanese: return [.dictionaries, .lexicon, .ocr, .translation]
        case .files: return [.storage, .drive]
        case .help: return [.diagnostics, .about]
        }
    }
}

enum SettingsRoute: String, Identifiable, CaseIterable {
    case theme, reading, panel, pencil, dictionaries, lexicon, ocr, translation, models, cards, storage, drive, diagnostics, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .theme: return "Thèmes et couleurs"
        case .reading: return "Pages et gestes"
        case .panel: return "Fenêtre texte OCR"
        case .pencil: return "Apple Pencil et annotations"
        case .dictionaries: return "Dictionnaires"
        case .lexicon: return "Lexique personnel"
        case .ocr: return "Reconnaître le texte des pages"
        case .translation: return "Traduction en ligne"
        case .models: return "IA et outils hors ligne"
        case .cards: return "Cartes de révision"
        case .storage: return "Espace de stockage"
        case .drive: return "Google Drive"
        case .diagnostics: return "Aide au diagnostic"
        case .about: return "À propos et mises à jour"
        }
    }
    var subtitle: String {
        switch self {
        case .theme: return "Choisir l'ambiance et les motifs de fond"
        case .reading: return "Une ou deux pages, sens de lecture et zoom"
        case .panel: return "Choisir sa position et conserver le zoom du livre"
        case .pencil: return "Dessiner, surligner ou chercher un mot avec le Pencil"
        case .dictionaries: return "Ajouter les dictionnaires des fiches de mots"
        case .lexicon: return "Tes termes, leurs lectures et leurs sens"
        case .ocr: return "Lecture automatique des scans et présentation du texte"
        case .translation: return "Configurer DeepL pour les traductions à la demande"
        case .models: return "Voir les outils conseillés et gérer leurs téléchargements"
        case .cards: return "Rythme de révision, modèles de cartes et export Anki"
        case .storage: return "Voir ce qui prend de la place et nettoyer les caches"
        case .drive: return "Connecter ton compte pour retrouver tes fichiers"
        case .diagnostics: return "Journal d'erreurs et suivi de la mémoire"
        case .about: return "Version de l'app, GitHub et crédits"
        }
    }
    var keywords: String {
        switch self {
        case .theme: return "apparence couleur sombre motifs fond"
        case .reading: return "double page portrait paysage marges rognage navigation défilement préchargement aperçus miniatures"
        case .panel: return "panneau étude fixe ancré flottant détacher texte OCR zoom"
        case .pencil: return "stylet doigt dessin encre notes"
        case .dictionaries: return "Yomitan vocabulaire kanji fiches"
        case .lexicon: return "glossaire domaine mots personnels"
        case .ocr: return "OCR moteur scans Vision NDLOCR PP-OCR cache police interligne furigana"
        case .translation: return "DeepL français traduction internet"
        case .models: return "IA locale modèles OvisOCR Qwen GLM MeCab UniDic téléchargement chat furigana nettoyage netteté"
        case .cards: return "Anki révisions cartes FSRS export"
        case .storage: return "cache place disque mémoire fichiers"
        case .drive: return "Google Drive compte connexion import"
        case .diagnostics: return "diagnostic bugs journal erreurs moniteur CPU RAM FPS performance"
        case .about: return "GitHub compte connexion version mise à jour installation crédits licences"
        }
    }
    func matches(_ query: String) -> Bool {
        let searchable = title + " " + subtitle + " " + keywords
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            searchable.localizedStandardContains(String($0))
        }
    }

    var icon: String {
        switch self {
        case .theme: return "paintpalette"
        case .reading: return "book"
        case .panel: return "sidebar.trailing"
        case .pencil: return "pencil.tip"
        case .dictionaries: return "character.book.closed.ja"
        case .lexicon: return "text.book.closed"
        case .ocr: return "text.viewfinder"
        case .translation: return "character.bubble"
        case .models: return "shippingbox"
        case .cards: return "rectangle.stack"
        case .storage: return "internaldrive"
        case .drive: return "externaldrive.badge.icloud"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }
    var tint: Color {
        switch self {
        case .theme, .pencil: return Atelier.Tint.annotate
        case .reading, .panel, .diagnostics: return Atelier.Tint.read
        case .dictionaries, .lexicon, .ocr, .cards: return Atelier.Tint.japanese
        case .translation, .models: return Atelier.Tint.ai
        case .storage, .drive, .about: return Atelier.Tint.cloud
        }
    }
}

struct SettingsEntryRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint).frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(Atelier.textPrimary)
                Text(subtitle).font(.subheadline).foregroundStyle(Atelier.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 7)
    }
}

struct SettingsAreaView: View {
    let area: SettingsArea
    var body: some View {
        Form {
            Section {
                ForEach(area.routes) { route in SettingsRouteLink(route: route) }
            } footer: { Text(area.subtitle) }
        }
        .scrollContentBackground(.hidden)
        .background(Atelier.canvas)
        .navigationTitle(area.title)
    }
}

struct SettingsRouteLink: View {
    let route: SettingsRoute

    var body: some View {
        NavigationLink { destination } label: {
            SettingsEntryRow(icon: route.icon, title: route.title, subtitle: route.subtitle, tint: route.tint)
        }
        .listRowBackground(Atelier.surface)
    }

    @ViewBuilder private var destination: some View {
        switch route {
        case .theme: ThemePickerView()
        case .reading: ReadingSettingsView()
        case .panel: StudyPanelSettingsView()
        case .pencil: AnnotationSettingsView()
        case .dictionaries: DictionaryManagerView()
        case .lexicon: DomainLexiconView()
        case .ocr: OCRSettingsView()
        case .translation: Form { TranslationSettingsSection() }.navigationTitle("Traduction en ligne")
        case .models: ModelsView()
        case .cards: ReviewSettingsView()
        case .storage: StorageUsageView()
        case .drive: DriveAccountView()
        case .diagnostics: ReaderHelpSettingsView()
        case .about: AboutView()
        }
    }
}

struct StudyPanelSettingsView: View {
    @AppStorage(StudyPanelMode.storageKey) private var mode = StudyPanelMode.docked
    @AppStorage(StudyPanelMode.restoreKey) private var restore = StudyPanelMode.docked
    @AppStorage(ReaderPDFView.preserveViewportKey) private var preserveViewport = true
    @AppStorage(StudyPanelMotion.storageKey) private var animateTransitions = true

    var body: some View {
        Form {
            Section {
                Picker("Position", selection: $mode) {
                    Text("Fixe à droite").tag(StudyPanelMode.docked)
                    Text("Fenêtre déplaçable").tag(StudyPanelMode.floating)
                    Text("Plein écran").tag(StudyPanelMode.full)
                    Text("Réduite en pastille").tag(StudyPanelMode.minimized)
                }
            } header: { Text("Fenêtre texte OCR") } footer: {
                Text("À droite en paysage, elle dispose de sa propre colonne. En portrait, la fenêtre apparaît par-dessus la page. Tu peux aussi changer sa position depuis les boutons de son en-tête.")
            }
            Section {
                Toggle("Animer les changements de fenêtre", isOn: $animateTransitions)
                Toggle("Conserver le zoom et la position du livre", isOn: $preserveViewport)
            } footer: {
                Text("En changeant la position de la fenêtre ou en la fermant, une page zoomée conserve son grossissement et son point de lecture. Une page affichée entière s'ajuste à la place disponible. Désactive cette option pour retrouver le recalage précédent. Les transitions peuvent être coupées séparément et respectent « Réduire les animations » dans les réglages de l'iPad.")
            }
        }
        .navigationTitle("Fenêtre texte OCR")
        .onChange(of: mode) { if $0 != .minimized { restore = $0 } }
    }
}

struct ReaderHelpSettingsView: View {
    @AppStorage(ResourceMonitor.enabledKey) private var monitorEnabled = false

    var body: some View {
        Form {
            Section {
                Text("Un problème d'affichage ou de lecture ? Active le journal, refais l'action, puis partage-le pour qu'on puisse comprendre ce qui se passe.")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            }
            DiagnosticsSection()
            Section {
                Toggle("Afficher le suivi des ressources", isOn: $monitorEnabled)
            } header: { Text("Outil avancé") } footer: {
                Text("Ajoute au menu « … » du lecteur un suivi du processeur, de la mémoire et de la fluidité. Utile pour observer un ralentissement.")
            }
        }.navigationTitle("Aide au diagnostic")
    }
}
