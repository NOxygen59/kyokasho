// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Les liens et la recherche partagent le même catalogue : aucun outil ne disparaît dans les sous-pages.
enum SettingsArea: String, Identifiable {
    case general, reading, aiText, japaneseReview, data, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "Général"
        case .reading: return "Lecture"
        case .aiText: return "IA et texte des pages"
        case .japaneseReview: return "Japonais et révision"
        case .data: return "Données"
        case .help: return "Aide"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "Apparence, icône, visite et nouveautés"
        case .reading: return "Pages, gestes, fenêtre OCR et Apple Pencil"
        case .aiText: return "Modèles, reconnaissance OCR et traduction"
        case .japaneseReview: return "Dictionnaires, lexique et cartes de révision"
        case .data: return "Sauvegarde, stockage et Google Drive"
        case .help: return "Diagnostic, version, mises à jour et crédits"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .reading: return "book"
        case .aiText: return "text.viewfinder"
        case .japaneseReview: return "character.book.closed.ja"
        case .data: return "externaldrive"
        case .help: return "questionmark.circle"
        }
    }
    var tint: Color {
        switch self {
        case .general: return Atelier.Tint.annotate
        case .reading: return Atelier.Tint.read
        case .aiText: return Atelier.Tint.ai
        case .japaneseReview: return Atelier.Tint.japanese
        case .data: return Atelier.Tint.cloud
        case .help: return Atelier.Tint.annotate
        }
    }
    var routes: [SettingsRoute] {
        switch self {
        case .general: return [.theme, .appIcon, .intro]
        case .reading: return [.reading, .panel, .pencil]
        case .aiText: return [.models, .ocr, .translation]
        case .japaneseReview: return [.dictionaries, .lexicon, .cards]
        case .data: return [.backup, .storage, .drive]
        case .help: return [.diagnostics, .about]
        }
    }
}

enum SettingsRoute: String, Identifiable, CaseIterable {
    case theme, appIcon, intro, reading, panel, pencil, models, ocr, translation, dictionaries, lexicon, cards, backup, storage, drive, diagnostics, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .theme: return "Thèmes et couleurs"
        case .appIcon: return "Icône de l'app"
        case .intro: return "Visite guidée et nouveautés"
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
        case .backup: return "Sauvegarde"
        case .drive: return "Google Drive"
        case .diagnostics: return "Aide au diagnostic"
        case .about: return "À propos et mises à jour"
        }
    }
    var subtitle: String {
        switch self {
        case .theme: return "Choisir l'ambiance et les motifs de fond"
        case .appIcon: return "Choisir l'apparence de Kyōkasho sur l'écran d'accueil"
        case .intro: return "Revoir la visite, les nouveautés et l'historique"
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
        case .backup: return "Sauvegarder toute la bibliothèque dans un dossier de Fichiers"
        case .drive: return "Connecter ton compte pour retrouver tes fichiers"
        case .diagnostics: return "Journal d'erreurs et suivi de la mémoire"
        case .about: return "Version de l'app, GitHub et crédits"
        }
    }
    var keywords: String {
        switch self {
        case .theme: return "apparence couleur sombre motifs fond"
        case .appIcon: return "apparence icone logo accueil ivoire bleu nuit jade anthracite"
        case .intro: return "visite guidee nouveautes versions historique découvrir"
        case .reading: return "double page portrait paysage marges rognage navigation défilement préchargement aperçus miniatures"
        case .panel: return "panneau étude fixe ancré flottant détacher texte OCR zoom"
        case .pencil: return "stylet doigt dessin encre notes"
        case .dictionaries: return "Yomitan vocabulaire kanji fiches"
        case .lexicon: return "glossaire domaine mots personnels"
        case .ocr: return "OCR moteur scans Vision NDLOCR PP-OCR Ovis lecture IA automatique cache police interligne furigana"
        case .translation: return "DeepL français traduction internet"
        case .models: return "IA locale modèles OvisOCR Qwen GLM MeCab UniDic téléchargement chat furigana nettoyage netteté"
        case .cards: return "Anki révisions cartes FSRS export"
        case .storage: return "cache place disque mémoire fichiers"
        case .backup: return "sauvegarde restauration copie dossier fichiers icloud drive"
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
        case .appIcon: return "app.dashed"
        case .intro: return "sparkles"
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
        case .backup: return "externaldrive.badge.checkmark"
        case .drive: return "externaldrive.badge.icloud"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }
    var tint: Color {
        switch self {
        case .theme, .appIcon, .intro, .pencil: return Atelier.Tint.annotate
        case .reading, .panel, .diagnostics: return Atelier.Tint.read
        case .dictionaries, .lexicon, .ocr, .cards: return Atelier.Tint.japanese
        case .translation, .models: return Atelier.Tint.ai
        case .storage, .backup, .drive, .about: return Atelier.Tint.cloud
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
            Image(systemName: icon).font(Atelier.font(18, weight: .medium))
                .foregroundStyle(tint).frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Atelier.corner(12)))
            VStack(alignment: .leading, spacing: 5) {
                Text(ui: title).font(.headline).foregroundStyle(Atelier.textPrimary)
                Text(ui: subtitle).font(.subheadline).foregroundStyle(Atelier.textSecondary)
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
        case .appIcon: AppIconSettingsView()
        case .intro: IntroSettingsView()
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
        case .backup: BackupSettingsView()
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
    @AppStorage(StudyPanelMotion.stableGesturesKey) private var stablePanelGestures = true

    var body: some View {
        Form {
            Section {
                Picker("Position", selection: $mode) {
                    Text("Fixe à droite").tag(StudyPanelMode.docked)
                    Text("Fenêtre déplaçable").tag(StudyPanelMode.floating)
                    Text("Plein écran").tag(StudyPanelMode.full)
                }
            } header: { Text("Fenêtre texte OCR") } footer: {
                Text("À droite en paysage, elle dispose de sa propre colonne. En portrait, la fenêtre apparaît par-dessus la page. Tu peux aussi changer sa position depuis les boutons de son en-tête.")
            }
            Section {
                Toggle("Animer les changements de fenêtre", isOn: $animateTransitions)
                Toggle("Stabiliser les gestes du panneau flottant", isOn: $stablePanelGestures)
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
    @AppStorage(ResourceMonitor.shownKey) private var monitorShown = false

    var body: some View {
        Form {
            Section {
                Text("Un problème d'affichage ou de lecture ? Active le journal, refais l'action, puis partage-le pour qu'on puisse comprendre ce qui se passe.")
                    .font(.subheadline).foregroundStyle(Atelier.textSecondary)
            }
            DiagnosticsSection()
            Section {
                Toggle("Afficher le suivi des ressources", isOn: $monitorEnabled)
                    .onChange(of: monitorEnabled) { if $0 { monitorShown = true } }
            } header: { Text("Outil avancé") } footer: {
                Text("Suivi du processeur, de la mémoire et de la fluidité, fixé en bas à gauche, dans la bibliothèque comme dans le lecteur. × le masque ; menu « … » du lecteur pour le réafficher. Utile pour observer un ralentissement.")
            }
        }.navigationTitle("Aide au diagnostic")
    }
}
