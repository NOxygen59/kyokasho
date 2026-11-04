<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Chaîne OCR → zones → furigana → affichage (#46, RET-031)

Comment une page de manuel devient des lectures en kana posées au-dessus des kanji. Complète
[ARCHITECTURE-LECTURE.md](ARCHITECTURE-LECTURE.md) (qui produit quoi) et [OCR.md](OCR.md) (moteurs). Les
noms de fichiers et de fonctions sont ceux du code ; ce document décrit le pourquoi et l'ordre, pas chaque ligne.

## 1. Vue d'ensemble

```
PDF de la page ──┬── texte intégré (PDF numérique) ─────────────────────────────┐
                 │                                                               │
                 └── scan : moteur OCR (Vision, NDLOCR, PP-OCRv5…) ─► OCRPage ───┤
                         lignes + boîte par caractère (repère normalisé)         │
                                                                                 ▼
             texte fiable d'OvisOCR2 (si la page a été lue) ──► alignement ─► texte + boîtes
                                                                                 │
                       lectures : MeCab/UniDic ► dictionnaire Yomitan ► analyseur du système
                                                                                 │
                                         FuriganaLayer.Mark (rectangle, kana, sens, taille max)
                                                                                 │
                                layout + spread (taille, pas de chevauchement) ─► dessin sur la page
```

Activé par l'option « Furigana » du lecteur (`FuriganaLayer.enabled`). Éteinte, rien n'est calculé.

## 2. Étape 1 : le texte et sa position

Deux sources, jamais mélangées pour une même page :

| Page | Source | Code |
|---|---|---|
| PDF numérique (texte intégré) | caractères et leurs boîtes donnés par PDFKit | `FuriganaLayer.marks(from: PDFPage)`, lancé par `ReaderController.scheduleFurigana` pour les pages visibles |
| Scan | résultat OCR `OCRPage` du cache SQLite `ocrResult` : lignes, texte, une boîte par caractère | `FuriganaLayer.marks(from: OCRPage, …)`, lancé par `ReaderController.showOCR` |

- Quand l'option est allumée, les pages visibles sans OCR sont lues automatiquement (`ReaderController+OCR.swift`), comme avec « OCR automatique ».
- Un résultat `pdfText` est ignoré par `showOCR` : la couche texte du PDF passe par `scheduleFurigana`. Si un scanner a ajouté une couche texte, un moteur OCR choisi explicitement garde la main sur les boîtes du scan.
- **Une boîte par caractère est obligatoire.** Sans elle, une lecture tomberait sur les mauvais caractères : la ligne est alors sautée.

Les boîtes OCR sont normalisées (0…1). `PageFrame` les ramène dans le repère de la page (`cropBox`), rotation intrinsèque du PDF comprise.

## 3. Étape 2 : corriger le texte avec OvisOCR2 (zones)

Un OCR classique se trompe sur des kanji, et une lecture calculée sur un kanji faux est fausse. Si OvisOCR2 a déjà lu la page (scan à l'import, « Vérifier », mise en page IA), son Markdown sert de référence :

1. `DocumentAITextStore.read(…, reader: ovisocr2, page:)` donne le texte d'OvisOCR2, normalisé (voir ARCHITECTURE-LECTURE, règles 3 et 4).
2. `OCRReferenceDiff.alignedLines` cherche, pour chaque ligne OCR, le passage d'OvisOCR2 qui lui ressemble (similarité ≥ 0,5).
3. Une ligne alignée prend **le texte d'OvisOCR2** et garde **les boîtes de l'OCR** : le texte vient de l'IA, la position est mesurée sur l'image. Un caractère que l'IA ajoute n'a pas de boîte : sa lecture se pose sur les caractères voisins du même mot qui en ont une.
4. Une ligne non alignée garde le texte de l'OCR.

OvisOCR2 ne fournit pas de positions. C'est pourquoi l'OCR classique reste nécessaire même quand l'IA a lu la page.

## 4. Étape 3 : les lectures

Pour chaque ligne contenant au moins un kanji, dans cet ordre de préférence :

1. **MeCab + UniDic** (si installé, `MorphologyService` affecte `Furigana.analyzer`) : découpe en mots et lecture selon le contexte. Le plus juste.
2. **Dictionnaire Yomitan installé** (`TextFurigana.rubies` avec les segments de `Translator.segment`) : lecture du dictionnaire reportée sur le mot du texte (読む【よむ】 → 読んだ), si les groupes de kanji correspondent (`dictionaryRubies`). C'est le même choix que dans le panneau OCR.
3. **Analyseur du système** (`CFStringTokenizer`, hors ligne) : transcription latine convertie en hiragana. Quelques erreurs connues sont corrigées en dur (`Furigana.corrections` : 日本, 日本語, 日本人).

Seuls les groupes de kanji reçoivent une lecture : 食べ物 → 食[た] べ 物[もの].

Filtres contre les fausses lectures :
- un caractère seul dans une légende verticale (ou empilé avec d'autres caractères isolés) ne reçoit rien, car le dictionnaire lui donnerait une lecture de prénom sans rapport ;
- le sens vertical est détecté par le moteur, par la forme des boîtes mesurées ou par celle de la ligne.

## 5. Étape 4 : placement

`FuriganaLayer.Mark` = rectangle des kanji, kana, horizontal ou vertical, taille maximale.

- **Place libre** (`room`) : espace au-dessus du mot (à droite en vertical) jusqu'à la ligne voisine la plus proche ; mesurée depuis la ligne entière ; 60 % du caractère sans voisine. La taille maximale vaut 85 % de cette place.
- **Taille** (`layout`) : 45 % du caractère, réduite par la place libre, jamais sous 32 %.
- **Pas de chevauchement** (`spread`) : sur une même ligne, les bandes qui se touchent sont regroupées et posées sur la moyenne de leurs positions. Elles bougent le moins possible.

## 6. Étape 5 : affichage

- Les marques calculées sont gardées en mémoire par page (`FuriganaLayer.set` / `marks(for:)`, clé `ScanSharpening.key(documentId:page:)`). Le calcul tourne hors du fil principal, en priorité basse.
- `pageFuriganaTasks` annule le calcul remplacé ; `Translator.segment` mémorise le mot retenu à chaque position (vidé par `invalidate()`) et ne charge pas les fréquences.
- `FuriganaLayer.PreparedPage` : mise en place et lignes Core Text calculées une fois à la publication ; chaque morceau dessiné ne pose que ses lectures. Une empreinte évite de recalculer une page aux mêmes données, et les résultats de fond partagent un seul redessin (`requestRedraw`).
- `furiganaGeneration` : si plusieurs calculs sont lancés pour la même page, seul le dernier est gardé.
- Le dessin a lieu avec celui de la page (`PageTone` appelle `FuriganaLayer.draw`) : kana sur une bande couleur papier, lisibles sur une trame ou un dessin. Couleur au choix dans le menu « … » → Affichage (`FuriganaLayer.Tint`).
- Une nouvelle lecture IA de la page relance le calcul (`refreshFurigana(afterAIRead:)`), une correction OCR aussi (`cacheUpdated`, voir ARCHITECTURE-LECTURE).
- La mémoire est vidée quand les pages du document changent (`PageShift` : `FuriganaLayer.clearMemory()`).

Dans le panneau d'étude, le texte extrait avec furigana (`FuriganaText`) utilise les mêmes lectures (étape 3), mais affichées en HTML et non dessinées sur la page.

## 7. Limites connues et pistes

- Les furigana **déjà imprimés** dans le manuel ne sont pas détectés : des lectures peuvent s'ajouter par-dessus (piste FDR-3 dans `FuriganaLayer.swift`).
- Les lectures de l'analyseur du système sont parfois fausses, en particulier pour les noms propres et les lectures rares. MeCab corrige la plupart des cas.
- Une ligne OCR sans boîte par caractère n'a pas de furigana.
- Pour diagnostiquer une page : mode diagnostic allumé. Le journal note, zone `furigana`, le moteur, le nombre de lignes, la longueur du texte OvisOCR2 utilisé et le nombre de lectures posées.
