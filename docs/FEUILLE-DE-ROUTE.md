# Feuille de route Kyōkasho — à lire en entier au début de chaque chat

> Ce fichier suffit. Ne relis pas PLAN.md, ni le code « pour voir ». Une session = les retours de l'utilisateur,
> sinon **une** étape du § 6 ; puis commit + push (+ release si demandée), puis stop.
> État au 21/10/2026 : **v0.8.2 publiée** (build 15). Rien n'a été testé à l'écran par Claude : l'utilisateur teste
> sur son iPad et fait ses retours. Tout ce qui est marqué « non vérifié » peut être faux sur l'appareil.

## 1. Prompt à coller dans le nouveau chat

```
Projet Kyōkasho (~/Projets-iPad/kyokasho). Lis docs/FEUILLE-DE-ROUTE.md et `git log -5 --oneline`,
puis fais mes retours s'il y en a, sinon la prochaine étape non cochée du § 6. Économise les tokens (§ 3).
Pas de simulateur, pas d'iPad sans ma permission.
```

## 2. Règles de l'utilisateur (obligatoires)

- **Français, court, simple** (l'utilisateur ne code pas) : dire *ce qui change pour lui* et *pourquoi*, sans jargon.
  Le plugin « caveman » est installé : son style ne remplace **pas** cette règle → toujours en français, phrases claires.
- **Jamais** demander ni taper un mot de passe, une clé API ou un jeton.
- Suppression : `trash`, jamais `rm` sur ses fichiers. **Ne jamais supprimer un dépôt GitHub.**
- Commits en français, finis par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (adapter le modèle).
- **Simulateur interdit** sauf « tu peux tester ». iPad (ios-mcp, souvent déconnecté) : demander + dire pourquoi.
- Usage perso, jamais distribué. Dépôt **privé** `NOxygen59/kyokasho`. Bundle `fr.noxygen59.kyokasho`.
  **iOS 16.0** minimum (iPad Pro 12.9" M1, TrollStore) : aucune API iOS 17+, aucune dépendance qui l'exige
  (ex. mlx-swift ≥ 0.30, mlx-swift-lm ≥ 2.30). App pensée **paysage**.
- Dépôt **public** `NOxygen59/kyokasho-models` (dossier local `~/Projets-iPad/kyokasho-modeles`) : **seulement**
  le modèle DE-GAN (release `degan-v1` + licence GPL jointe) et `latest.json`. **Jamais** le code ni le `.tipa`
  (choix de l'utilisateur le 21/10).
- Chaque fichier : `// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`. Code GPL → seulement
  `YomitanKit`. Code MIT copié → garder le copyright d'origine (`GLMOCRKit`). Toute dépendance / tout modèle →
  `THIRD_PARTY_NOTICES.md` + `AboutView` (App/Settings/SettingsView.swift, fonction `credit`).
- **Jamais** de PDF, dictionnaire, modèle ni donnée tierce dans le dépôt. Modèles = téléchargés à la demande.
- En ligne : DeepL (option), téléchargements déclenchés par l'utilisateur (audio, modèles), navigateur à côté
  (tous sites), avis de mise à jour (`latest.json`, ≤ 2 fois/jour). Rien d'autre.
- Télécharger quelque chose sur le Mac (outil, modèle de test) : dire quoi, d'où, quelle taille, **demander**.
  Le Mac chauffe sur les gros calculs : rester léger.
- Release **seulement quand l'utilisateur la demande** (il enchaîne souvent plusieurs retours avant).

## 3. Économiser les tokens (méthode qui marche)

- Gros fichier : `grep -n 'motif' f` puis `sed -n 'A,Bp' f`. Ne jamais lire `ReaderController.swift` (~1600 l.) en entier.
- Modifier : `python3 - <<'EOF' … assert s.count(a)==1 … EOF` (plusieurs remplacements d'un coup, échoue si ambigu).
- Fichier ajouté dans `App/` → `xcodegen generate -q` avant de compiler (sinon « cannot find X in scope »).
- Sorties toujours filtrées :
  - tests : `cd Packages/KyokashoKit && swift test 2>&1 | grep -E ': error|error:|with [1-9][0-9]* failure' | head -5`
  - app : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E ' error:|BUILD' | sort -u | head -20`
  - `.tipa` : `./build_ipa.sh 2>&1 | grep -E 'OK|error' | tail -2`
- Vérifier un comportement PDFKit / Core Graphics : petit script Swift dans le scratchpad (`swiftc -O x.swift -o x`,
  le code de haut niveau seulement dans `main.swift`). Ça a trouvé presque tous les vrais bugs de repère.
- Gros chantier : éclaireurs `caveman:cavecrew-investigator` en parallèle, puis **toujours**
  `caveman:cavecrew-reviewer` sur le diff avant commit (il trouve de vrais bugs à chaque fois ; ses 🔴 sont
  parfois faux : vérifier avant de corriger).
- Pas de captures d'écran, pas de simulateur, pas d'exploration « au cas où ». Une image d'essai rendue sur le Mac
  (Read d'un PNG réduit à ≤ 900 px) vaut mieux qu'une longue réflexion pour tout ce qui est visuel.
- Fin de session : commit + `git push` + cocher ici + 3-6 lignes de résumé simple à l'utilisateur.

## 4. Release (si demandée)

1. `project.yml` : `MARKETING_VERSION` (+0.0.1 correctif, +0.1 grosse étape) et `CURRENT_PROJECT_VERSION` +1.
2. `docs/releases/vX.Y.Z.md` (Installation / Modifications / Vérifié – non vérifié).
3. Ligne en haut du tableau « Versions » du README.
4. `./build_ipa.sh`, puis :
   ```
   git add -A && git commit -m "Version X.Y.Z (…)" && git tag vX.Y.Z && git push origin HEAD --tags
   gh release create vX.Y.Z dist/Kyokasho-X.Y.Z.tipa --title "Kyōkasho X.Y.Z — …" --notes-file docs/releases/vX.Y.Z.md
   ```
5. Avis dans l'app : `~/Projets-iPad/kyokasho-modeles/latest.json` → `version`, `build` (= CURRENT_PROJECT_VERSION),
   `page` (URL de la release), `notes` ; commit + `git push` dans ce dossier ; contrôle :
   `gh api repos/NOxygen59/kyokasho-models/contents/latest.json --jq .content | base64 -d | grep version`
   (raw.githubusercontent met quelques minutes à suivre : normal).

## 5. Ce qui existe (fait, et comment)

> « ✅ Mac » = vérifié par test ou image d'essai sur le Mac. Rien n'est vérifié sur l'iPad.

**Bases (V1 → V5, avant le 21/10)** : bibliothèque, lecteur PDFKit, OCR (Vision, PP-OCRv5, NDLOCR-Lite, GLM-OCR),
dictionnaires Yomitan (import, déconjugaison, popup), cartes FSRS + export `.apkg`, notes / surlignages / dessin
PencilKit, Drive, DeepL, thèmes, barre flottante.

**Lecteur**
- Construction du document hors du fil principal : `ReaderController.rebuild → build → install`. `build` range les
  pages (coupe des doubles pages, droite → gauche en double page) puis **vide et remplit le même `PDFDocument`**
  (sommaire gardé, ✅ Mac). Chaque page est une `TonedPage` (délégué `TonedPageProvider.classForPage`, posé avant
  toute lecture de page ; `copy()` garde la classe mais **pas** les propriétés Swift → `pageKey` / `originalBox`
  recopiés à la main).
- `ReaderScreen` n'observe plus `AppModel` (valeurs reçues par `onReceive`).
- Tourner les pages : `turnTarget` (page après la dernière visible / avant la première) en mode paginé, car
  `goToNextPage` de PDFKit n'avance que d'une page (double page bloquée). Continu : `goToNextPage`. Flèches visibles
  avec les barres ou un clavier.
- Fond de page (`PageTone.swift`) : Blanc / Crème / Tamisé / Sombre, par mélange (multiply / difference) dans
  `TonedPage.draw`. Changement → `rebuild`.
- Nettoyage des scans (`ScanSharpening.swift`, menu Affichage) : `Method` off / color / mono / degan.
  `PageCleaner` (OCRKit) : fond du papier estimé en 1/8 (maximum local + maximum large ≈ 1/10 de page × 0,9, puis
  flous, filtres séparables), division canal par canal, courbe douce. ✅ Mac (ombre, jaunissement, dessin gardé,
  ≈ 0,1 s à 1200 px). Image posée dans `TonedPage.draw` avec `transform(for: box)` + clip (✅ Mac : même repère que
  `super.draw`). Caches : mémoire 8 pages + disque `Caches/Sharpened/<doc>-<page>-<méthode>-v2.png`.
  DE-GAN (`PageEnhancer`, ONNXOCRKit) : mauvais sur les photos (entraîné sur de la binarisation de vieux documents).
- Redessin sans reconstruire : `ReaderPDFView.redrawVisiblePages()` (setNeedsDisplay sur les vues seulement).
  **Non vérifié sur iPad** que les pages nettoyées / furigana apparaissent sans tourner la page.
- Menu « … » : Affichage (fond, furigana, nettoyage, zones OCR) / Cette page (pivoter, couper, page 1) /
  « Pagination et réglages de ce document » (`DocumentSettingsSheet`, n'enregistre que si changé, ce document seul).

**Dictionnaire (survol, toucher, Pencil, sélection)** — `ReaderController.lookup(at:fromHover:)`
- PDF avec texte : seulement si ≥ 8 vrais caractères (même règle que `PDFTextEngine.isEnoughText`, mémo dans
  `pageStringCache`) ; `characterIndex(at:)` saute les fins de ligne → `glyphToStringMap` + `stringIndex(near:)`
  (contrôle par position, ✅ Mac 20/20) ; rectangles par `page.selection(for:)`.
- Scans : OCR de la page (cache, sinon `ensureOCR` en fond) ; point → repère OCR par **`PageFrame`** (cadre
  d'origine + rotation intrinsèque /Rotate, ✅ Mac contre le vrai rendu pour 0/90/180/270) ; `OCRPage.character(at:)`.
- Popup : `LookupSession` (HTML gardé tant que rien ne change), `LookupPopup`, audio lu hors du fil principal.

**OCR**
- Moteurs : `OCRService.resolve` (auto : texte du PDF si assez de texte, sinon NDLOCR → PP-OCRv5 → Vision).
  Cache SQLite par page et moteur, **version 5** (`OCRPage.currentVersion`).
- NDLOCR + PP-OCRv5 installé : chaque ligne relue par la reconnaissance PP (CTC) pour **mesurer** la place des
  caractères ; `CharacterAlignment` (distance d'édition, ≥ 60 % identiques, interpolation) recopie les boîtes.
- Texte intégré (`PDFTextEngine.extract`) et rendu OCR (`PageRenderer`) : tous deux dans le repère tourné.
- Conversions d'image Accelerate (vDSP / vImage) dans `NeuralOCR.swift`.
- Double page : `focusSource` (page de travail) / `shownSources` (pages affichées) ; pilules dans le panneau ;
  `ensureOCR` = file unique, vidée au changement de page et à la fermeture.

**Texte extrait (panneau d'étude, onglet Texte)** — `App/Study/StudyPanel.swift`, `FuriganaText.swift`
- Panneau ouvert d'office en paysage (taille réelle de la vue).
- « Mis en forme » / « Brut ». Mise en forme `OCRLayout` (OCRKit) : géométrie seule (union-find de lignes, paragraphes
  par alinéa / ligne courte, titres par taille, tableaux = rangées de cellules courtes) **ou** zones d'un modèle :
  `LayoutDetector` (ONNXOCRKit) PP-DocLayout v3 (classes + ordre de lecture) ou DocLayout-YOLO (MinerU), puis
  `OCRLayout.blocks(_:regions:)` (en-têtes / pieds écartés). ✅ Mac avec les vrais modèles (≈ 1,2 s/page CPU).
  Choix : bouton à côté du sélecteur (`study.layoutEngine`), cache `LayoutRegionsCache`. Copie = Markdown.
- Bouton ふりがな : `FuriganaTextView` (WKWebView, `<ruby>`, hauteur suivie) ; lectures du dictionnaire Yomitan
  (`TextFurigana.dictionaryRubies`, forme de base reportée sur les kanji du mot) sinon `Furigana` ; appui →
  feuille compacte `LookupPopup` (ajout de carte). Texte à chercher calculé en Swift (`data-q`), pas en JS.

**Furigana sur la page** — `App/Reader/FuriganaLayer.swift`, `ReaderCore/Furigana.swift`
- Lectures : `CFStringTokenizer` (romaji → hiragana), alignées sur les groupes de kanji, table `corrections`.
- Positions : texte du PDF (`selection(for:)`) ou OCR (`marks(from:frame:)`). Taille ≤ 45 % du caractère et ≤ place
  libre jusqu'à la ligne voisine (`room`), fond papier, rouge foncé. ✅ Mac en horizontal ; **vertical jamais vérifié**.

**Le reste**
- Navigateur à côté (`WebPanel`) ouvert à tous les sites, raccourcis, liens `_blank` dans la même vue.
- Avis de mise à jour (`AppUpdate.swift`) : bandeau bibliothèque + Réglages → À propos.
- Réglages → Modèles (`ModelsView`) : OCR, mise en page, netteté ; lien du projet + du fichier sous chaque modèle.
- Icône : `tools/make_icon.swift` (教 doré, livre, sceau 書) → `App/Resources/Assets.xcassets/AppIcon.appiconset`.
- Optimisations : panneaux sans flou, ombre sur la forme, export Markdown au partage, recherche de cartes après
  250 ms, progression par %, pas de préchargement en mode économie d'énergie.

## 6. Étapes restantes (cocher `[x]` quand fini) — dans cet ordre

> **Priorité absolue : les retours de l'utilisateur.** Puis de haut en bas.

### [ ] 1 — Gestes / zoom « quasi inexistants ou cassés » (retour du 21/10, cause pas trouvée)
Demander d'abord **lesquels** (pincer, glisser, double-tap, défiler zoomé, barre, boutons) **ou** la permission du
simulateur. Pistes à vérifier dans `ReaderController.configureGestures` / `applyDisplaySettings` / `ReaderPDFView` :
1. Modes `.singlePage` / `.twoUp` **non continus** : PDFKit zoome mal (la page « saute ») ; essayer de garder
   `singlePageContinuous`/`twoUpContinuous` avec `usePageViewController` ou repasser la pagination à notre main.
2. `singleTap.require(toFail: doubleTap)` → chaque tap attend ~0,3 s (impression de « rien ne marche »).
3. Survol (`UIHoverGestureRecognizer`, `hoverLookup` vrai par défaut) : popups qui s'ouvrent au Pencil / trackpad.
4. Glisser (`swipeLeft/Right`, `shouldRecognizeSimultaneouslyWith` → true partout) en conflit avec le défilement.
5. `fitToPage` relancé à chaque changement de taille (panneau d'étude) : remet le zoom à « page entière ».
Test au simulateur (si permis) : `mcp__Claude_Code_iOS_Simulator__control` attach → build → launch, pincer
(`touch2_path`), glisser, double-tap ; 2-3 captures max.

### [ ] 2 — Vraies vérifications sur l'iPad (avec permission ; sinon les demander à l'utilisateur)
Liste « non vérifié » à cocher : paysage + panneau ouvert d'office ; boutons de page en double page ; pilules ;
dictionnaire sur PDF photo (pages tournées) ; furigana page (horizontal **et vertical**) ; nettoyage « Papier
blanc » (apparition sans tourner la page, vitesse à 2000 px) ; furigana du texte extrait + feuille du dictionnaire ;
mise en page PP-DocLayout / DocLayout-YOLO (vitesse, mémoire) ; avis de mise à jour ; navigateur.

### [ ] 3 — Furigana : vertical et finitions
- Vertical : vérifier (image d'essai Mac avec colonnes verticales) que les kana vont à droite de la colonne, de
  haut en bas, et que `room` mesure la colonne de droite. Corriger `FuriganaLayer.draw` si besoin.
- Ne pas poser de furigana sur les kanji déjà accompagnés de furigana imprimés (lignes OCR très fines collées à une
  ligne : les ignorer comme obstacles **et** sauter le mot).
- Option « lectures du dictionnaire » aussi sur la page (comme le panneau : `TextFurigana` avec `DictionaryModel.segment`).
- Panneau : texte vertical affiché en vertical (`writing-mode: vertical-rl` dans `FuriganaTextView.page`) si la
  page est surtout verticale.

### [ ] 4 — B : thème dans la fenêtre du dictionnaire et les cartes
`GlossaryRenderer` (DictionaryKit) et `CardHTML` (App/Review/CardWebView.swift) ont leurs couleurs en dur. Ajouter un
paramètre **non enregistré** `palette` (fond, texte, accent, filet) rempli depuis `Theme.current`
(App/Design/Themes.swift) dans `DictionaryModel.renderer(...)` et `CardHTML.page`. Si on touche
`GlossaryRenderer.Options` (Codable) : décodage tolérant, sinon les profils enregistrés cassent.
`FuriganaTextView.page` lit déjà les couleurs via `UIColor(...).hexString` : même approche.

### [ ] 5 — Mise en page : aller plus loin
- Tableaux : zones « table » découpées seulement par géométrie (`OCRLayout.tables`). Piste : PP-Structure SLANet
  (structure de tableau en ONNX, RapidTable, Apache-2.0) → cellules exactes. Demander le téléchargement.
- Texte vertical japonais : utiliser la classe `vertical_text` de PP-DocLayout pour l'ordre (droite → gauche) et
  pour `OCRLayout.paragraphs`.
- Option : ordre de lecture de PP-DocLayout aussi pour le dictionnaire (phrase de contexte des cartes).
- Docling (layout « heron », RT-DETR) : seulement si une version ONNX existe ; sinon rester sur les deux actuels.

### [ ] 6 — Performance, restes repérés
1. `Translator.segment` : une recherche par caractère non trouvé → mémo des positions déjà vues pendant un appel.
2. `OCRService.search` décode toutes les pages → index texte (FTS5 GRDB) rempli à l'enregistrement de l'OCR.
3. `RGBImage.rotatedCounterClockwise` pixel par pixel → `vImageRotate90_ARGB8888` (passer par RGBA).
4. Révisions : `ReviewScreen.advance` / `answer` en base sur le fil principal → tâche de fond.
5. NDLOCR + passe PP : ≈ double du temps → ne la lancer que si la page est utilisée au toucher, ou en lot.
6. `PageCleaner` à 2000 px : mesurer ; si > 0,3 s, travailler à 1/2 puis remonter, ou passer en vDSP.

### [ ] 7 — D : GLM-OCR plus rapide
Une génération par ligne (≈ 1 s/ligne sur Mac). Grouper 3-5 lignes voisines par image (un appel), découper la réponse
par `\n`, garder si le nombre colle. Mesurer la mémoire sur l'iPad avec permission.

## 7. Carte du code (où est quoi)

- **`project.yml`** (XcodeGen) : versions, paquets `KyokashoKit` + `GLMOCRKit`. `packaging/entitlements-trollstore.plist`.
- **`Packages/KyokashoKit/`** (`swift test`, macOS 14+) :
  - `ReaderCore` : `Models` (`LibraryDocument`), `AppDatabase` (GRDB), `ReaderSettings` (+ `ReaderSettingsOverride`
    par document, `OCREngineChoice`), `ReaderLogic` (`PresentationLayout`), `Furigana`.
  - `OCRKit` : `OCRModels` (`NormBox`, `OCRLine`, `OCRPage` v5, **`PageFrame`**), `OCREngines` (`PageRenderer`,
    `PDFPool`, `VisionOCREngine`, `PDFTextEngine`), `OCRService`, `ModelStore` (catalogue `ModelSpec` : ppocr5,
    ndlocr, glmocr, degan, ppdoclayout, doclayoutyolo ; `homepage`, `mainDownload`), `NeuralOCR` (image, DB, CTC,
    PARSeq, ordre), `CharacterLayout`, `OCRLayout` (blocs, `Region`), `PageCleaner`.
  - `ONNXOCRKit` : `ONNXEngines` (`ONNXModel` avec CoreML optionnel, `SessionCache`, PP-OCRv5, NDLOCR,
    `CharacterAlignment`), `PageEnhancer` (DE-GAN), `LayoutDetector`.
  - `YomitanKit` (**GPL**). `DictionaryKit` : base, import, `Translator` (`segment`), `GlossaryRenderer`.
  - `ReviewKit` : FSRS (swift-fsrs fixé sur un commit), `ReviewStore`, `Exporters`.
- **`Packages/GLMOCRKit/`** (MLX) : GLM-OCR.
- **`App/`** :
  - `KyokashoApp.swift` (racine, bandeau de mise à jour, alerte mémoire), `AppModel.swift`.
  - `Reader/` : `ReaderController` (build, gestes, lookup, OCR, `focusSource`, `ensureOCR`, furigana, nettoyage,
    `ReaderPDFView`), `ReaderScreen` (chrome, menus, flèches), `PageTone` (`TonedPage`), `ScanSharpening`,
    `FuriganaLayer`, `FloatingToolbar`, `InkOverlay` (dessin + zones OCR via `PageFrame`), `ReaderSheets`
    (recherche, sommaire, notes, `WebPanel`), `TextPageSheet`.
  - `Study/` : `StudyPanel` (onglets, pilules, `FormattedOCRText`, `LayoutRegionsCache`), `FuriganaText`
    (`TextFurigana`, `FuriganaTextView`, `RubyWebView`), `DeepL`.
  - `Dictionary/`, `Review/`, `Library/`, `Drive/`, `Design/` (`Atelier`, `Themes`).
  - `Settings/` : `SettingsView` (sections, `DocumentSettingsSheet`, `AboutView`, `ModelsView`), `OCRModelsView`
    (`ModelDownloads`, `OCRModelsSection`), `AppUpdate`, `BenchView`.
- **`tools/`** : `degan_to_onnx.py` (h5 → ONNX, sans TensorFlow), `make_icon.swift`.
- Racine : `build_ipa.sh` → `dist/Kyokasho-<version>.tipa` (ignoré par git), `docs/releases/`, `THIRD_PARTY_NOTICES.md`.

## 8. Tester avec les vrais modèles (Mac, hors dépôt)

Dossier `<M>` avec sous-dossiers comme `ModelStore` (`ppocr5/`, `ndlocr/`, `glmocr/`, `degan/degan-binarize.onnx`,
`ppdoclayout/layout.onnx`, `doclayoutyolo/layout.onnx`), téléchargés **avec accord** (URL + SHA-256 dans
`ModelStore.swift`) :
```
cd Packages/KyokashoKit && KYOKASHO_MODELS=<M> swift test --filter ONNXEnginesTests
cd Packages/GLMOCRKit && KYOKASHO_MODELS=<M> swift test
```
Sans la variable, ces tests sont sautés. Le dossier du 21/10 était dans le scratchpad du chat (effacé ensuite).
Outils Python : venv jetable (`python3 -m venv`, `pip install h5py onnx onnxruntime pillow numpy`), jamais global.

## 9. Pièges déjà rencontrés

- Noms pris : `Document` → `LibraryDocument` ; éviter `Card`, `ReviewLog`, `Rating` dans ReviewKit.
- GRDB : écrire en synchrone dans une `Task.detached` ; `didInsert` pour l'id ; dates à la ms (tests : `accuracy`).
- ZIPFoundation : typer la closure `{ (pos: Int64, size: Int) in … }`.
- PDFKit : pas d'`exchangePage` ; `autoScales` cassé → `fitToPage` ; pas sûr entre fils → `PDFPool` (verrou) ;
  document construit hors du fil principal puis installé sur le principal.
- PDFKit : `characterIndex(at:)` / `characterBounds(at:)` **ne comptent pas les fins de ligne** de `page.string` →
  `glyphToStringMap` / `stringIndex(near:)` ou `selection(for:)`.
- PDFKit : `goToNextPage` n'avance que d'**une** page (double page) → `turnTarget`.
- PDFKit : `draw(with:to:)` reçoit un contexte où `super` applique lui-même origine du cadre + rotation →
  dessiner après `context.concatenate(transform(for: box))`, en coordonnées absolues (✅ Mac).
- Rendu OCR = page **tournée** selon /Rotate : toute conversion OCR ↔ page passe par `PageFrame`. Jamais
  `box.maxY - y` à la main. `CGContext.drawPDFPage` ignore /Rotate (✅ Mac).
- PDF « photo » : couche de texte souvent vide ou faite de blancs → toujours `PDFTextEngine.hasTextLayer`
  (≥ 8 caractères), jamais `string?.isEmpty`.
- `CIDivideBlendMode` = « arrière-plan ÷ image » ; le nettoyage est en calcul direct (`PageCleaner`).
- Gestes : `cancelsTouchesInView = false` ; glisser une vue qui bouge : `DragGesture(coordinateSpace: .global)`.
- Menu d'appui long puis alerte : attendre ~0,35 s.
- Vision : `.accurate` seul lit le japonais ; `minimumTextHeight` bas. Monter `OCRPage.currentVersion` quand le
  résultat OCR change (dernier : 5).
- swift-fsrs : tag 5.0.0 inutilisable → commit de main.
- ONNX Runtime ObjC : pas d'accès aux formes d'entrée → formes en dur. NDLOCR : détecteur 800×800. CoreML EP :
  seulement formes **fixes** et fp32 (DE-GAN 256×256 : 35× plus rapide) ; MLProgram refuse MaxPool sans `pads`.
- MLX : « Metal Toolchain » d'Xcode ; `UserInput(prompt:images:)` perd les images → `UserInput(chat:)`.
- SwiftUI : `@State` d'un objet non observé ne déclenche rien → booléens d'affichage explicites (feuille du
  dictionnaire). `.task(id:)` : la clé doit changer pour **tout** changement (signature complète, ex. `hashValue`).
- `Task.detached` ignore l'annulation de la tâche parente → `withTaskCancellationHandler` + `guard !Task.isCancelled`
  avant d'écrire le résultat.
- Le paysage n'a **jamais** été vérifié (le simulateur sans fenêtre ne pivote pas).

## 10. Idées / plus tard

PP-OCRv6, envoi des médias vers AnkiMobile, synchro des cartes par Drive, statistiques avancées, redressement des
photos de pages (UVDoc, ONNX ?), super-résolution légère des scans flous, Surya via le Mac (refusé : « tout sur l'iPad »).
