// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Ce qu'un document permet, d'après son format et jamais d'après sa catégorie : celle-ci reste un simple classement,
/// modifiable. Une archive CBZ se limite à la lecture visuelle : bibliothèque, couverture, progression et navigation.
public struct DocumentCapabilities: Equatable, Sendable {
    /// OCR, zones de texte, furigana, dictionnaire au toucher, recherche dans le texte.
    public var textAnalysis: Bool
    /// IA, traduction, chat, analyse du document, panneau d'étude et cartes.
    public var study: Bool
    /// Chat avec l'IA. Coupé sur les mangas (décision de NOxygen59, 05/11/2026) : seule exception où l'espace décide. L'OCR,
    /// le dictionnaire et le panneau d'étude d'un manga PDF restent là.
    public var chat: Bool
    /// Dessin, surlignage et notes.
    public var annotations: Bool
    /// Ajout, retrait, rotation et coupe de pages, numérotation.
    public var pageEditing: Bool
    /// Export : il rendrait le PDF de lecture, pas l'archive d'origine.
    public var export: Bool
    /// Choix libre du classement sur la carte.
    public var editableShelf: Bool

    public init(document: LibraryDocument) {
        let full = !document.isComicArchive
        textAnalysis = full
        study = full
        chat = full && !document.isInMangaSpace
        annotations = full
        pageEditing = full
        export = full
        editableShelf = full
    }
}

extension LibraryDocument {
    public var capabilities: DocumentCapabilities { DocumentCapabilities(document: self) }

    /// Espace où le document apparaît. N'enlève aucune fonction à un PDF : seul le format décide des capacités.
    public var isInMangaSpace: Bool { isComicArchive || settingsOverride.mangaSpace == true }

    /// Issu d'un `.cbz`. Le nom d'origine ne change jamais et existe depuis toujours : une version plus ancienne de l'app
    /// relit ce document comme un PDF ordinaire, sans valeur inconnue qui ferait échouer toute la bibliothèque.
    public var isComicArchive: Bool {
        (originalFileName as NSString).pathExtension.lowercased() == ComicBookArchive.fileExtension
    }
}
