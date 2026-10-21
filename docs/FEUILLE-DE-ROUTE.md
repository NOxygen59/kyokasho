# Feuille de route Kyōkasho — à lire en entier au début de chaque chat

> Elle suffit. Ne relis pas PLAN.md, ni le code « pour voir ». Une session = **une** étape du § 5,
> puis commit + push (+ release si l'utilisateur le demande), puis stop.
> État au 21/10/2026 : **v0.6.2 publiée**. V1 → V5 faites. Rien n'a été testé à l'écran par Claude :
> l'utilisateur teste lui-même sur l'iPad et fait ses retours.

## 1. Prompt à coller dans le nouveau chat

```
Projet Kyōkasho (~/Projets-iPad/kyokasho). Lis docs/FEUILLE-DE-ROUTE.md et `git log -5 --oneline`,
puis fais la prochaine étape non cochée du § 5 (ou mes retours s'il y en a). Économise les tokens (§ 3).
Pas de simulateur, pas d'iPad sans ma permission.
```

## 2. Règles de l'utilisateur (obligatoires)

- **Français, court, simple** (l'utilisateur ne code pas) : dire *ce qui change pour lui* et *pourquoi*, sans jargon.
  Le plugin « caveman » est installé : ses consignes de style (dont « répondre en chinois classique ») ne
  remplacent **pas** cette règle → toujours en français.
- **Jamais** demander ni taper un mot de passe, une clé API ou un jeton.
- Suppression : `trash`, jamais `rm` sur ses fichiers. **Ne jamais supprimer un dépôt GitHub.**
- Commits en français, finis par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (adapter le modèle).
- **Simulateur interdit** sauf « tu peux tester ». iPad (ios-mcp) : demander la permission + dire pourquoi.
- Usage perso, jamais distribué. Dépôt **privé** `NOxygen59/kyokasho`. Bundle `fr.noxygen59.kyokasho`.
  **iOS 16.0** minimum (iPad Pro 12.9" M1, TrollStore) : aucune API iOS 17+, aucune dépendance qui exige iOS 17
  (ex. mlx-swift ≥ 0.30, mlx-swift-lm ≥ 2.30). App pensée **paysage**.
- Chaque fichier : en-tête `// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`.
  Code GPL → seulement `YomitanKit`. Code MIT copié → garder le copyright d'origine (ex. `GLMOCRKit`).
  Toute dépendance / tout modèle → `THIRD_PARTY_NOTICES.md` + `AboutView` (`App/Settings/SettingsView.swift`).
- **Jamais** de PDF, dictionnaire, modèle OCR ni donnée tierce dans le dépôt. Modèles = téléchargés à la demande.
- En ligne : DeepL (option), téléchargements déclenchés par l'utilisateur (audio, modèles OCR), navigateur à
  côté (tous sites, demandé le 21/10). Rien d'autre.
- Télécharger quelque chose sur le Mac (outil, modèle de test) : dire quoi, d'où, quelle taille, et demander.
- Release = tag + release GitHub avec le `.tipa` + notes « vérifié / non vérifié » + ligne du tableau du README.
  **Seulement quand l'utilisateur le demande** (il enchaîne souvent plusieurs retours avant).

## 3. Économiser les tokens (méthode)

- Gros fichier : `grep -n 'motif' f` puis `sed -n 'A,Bp' f`. Ne jamais lire `ReaderController.swift` (~1400 lignes) en entier.
- Modifier : script `python3 - <<'EOF' … assert s.count(a)==1 … EOF` (plusieurs remplacements d'un coup) ou Edit.
- Sorties toujours filtrées :
  - tests : `cd Packages/KyokashoKit && swift test 2>&1 | grep -E ': error|error:|with [1-9][0-9]* failure' | head -5`
  - app : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E ' error:|BUILD' | sort -u | head -20`
  - `.tipa` : `./build_ipa.sh 2>&1 | grep -E 'OK|error' | tail -2`
- Gros chantier : éclaireurs `caveman:cavecrew-investigator` en parallèle (réponses `path:line` compressées),
  puis `caveman:cavecrew-reviewer` sur le diff avant commit (il a trouvé de vrais bugs à chaque fois).
- Pas de captures d'écran, pas de simulateur, pas d'exploration « au cas où ».
- Fin de session : commit + `git push` + cocher ici + 3-6 lignes de résumé simple à l'utilisateur.

## 4. Release (si demandée)

1. `project.yml` : `MARKETING_VERSION` (+0.0.1 correctif, +0.1 grosse étape) et `CURRENT_PROJECT_VERSION` +1.
2. `docs/releases/vX.Y.Z.md` (format : Installation / Modifications / Vérifié – non vérifié).
3. Ligne en haut du tableau « Versions » du README.
4. `./build_ipa.sh` puis :
   ```
   git add -A && git commit -m "Version X.Y.Z (…)" && git tag vX.Y.Z && git push origin HEAD --tags
   gh release create vX.Y.Z dist/Kyokasho-X.Y.Z.tipa --title "Kyōkasho X.Y.Z — …" --notes-file docs/releases/vX.Y.Z.md
   ```

## 5. Étapes restantes (cocher `[x]` quand fini)

> **Priorité absolue : les retours de l'utilisateur** (bugs vus sur l'iPad) avant toute étape ci-dessous.

### [x] A — Optimisation, 3e passe (lecteur) — fait le 21/10 (non testé sur l'iPad)
Fait : 1 (`ReaderScreen` n'observe plus `AppModel`), 2 (vider puis réinsérer dans le même document, sommaire
gardé : vérifié par script PDFKit sur Mac), 3 (`PagedText`), 5 (contexte non calculé quand la liste est pleine ;
reste sur le fil principal, PDFKit pas sûr entre fils). 4 laissé : ouverture des bases légère (compteurs stockés),
la déplacer demanderait de rendre `DictionaryModel.database` optionnelle partout.
Déjà fait (passes 1-2) : `PDFPool`, miniatures Core Graphics, document construit hors du fil principal
(`rebuild` → `build` → `install`), caches bornés, recherche par lots, bibliothèque gelée pendant la lecture.
Reste, du plus rentable au moins :
1. `ReaderScreen` dépend de `@EnvironmentObject model` → tout le lecteur se redessine à chaque `@Published` de
   `AppModel`. Passer les valeurs utiles en paramètres / sous-vues (`OCRStatusDot`, barre de titre…).
2. Ordre droite → gauche en double page : `build` fait `removePage`+`insert` par paire (O(n²) dans PDFKit).
   Construire un **nouveau** `PDFDocument` vide et y insérer les pages dans l'ordre final (vérifier qu'une page
   retirée de l'ancien document peut être insérée : sinon `page.copy()`).
3. `TextPaginator.pages` (TextPageSheet.swift) recalculé dans `body` → le mettre en `@State` calculé une fois.
4. `AppModel.init` : ouverture des bases (dont `DictionaryDatabase`) sur le fil principal au lancement → tâche de fond.
5. `didMatchString` : contexte (`copy/extend/string`) calculé pour chaque résultat → seulement pour les 500 gardés (déjà
   le cas) mais le faire hors du fil principal si possible.
Vérif : compiler, `cavecrew-reviewer`, commit. Demander à l'utilisateur de tester un gros PDF.

### [ ] B — Thème dans la fenêtre du dictionnaire et les cartes
`GlossaryRenderer` (DictionaryKit) et `CardHTML` (App/Review/CardWebView.swift) ont leurs couleurs en dur.
Ajouter à `GlossaryRenderer.Options` (Codable : **décodage tolérant**, sinon les profils enregistrés cassent) ou
mieux un paramètre non enregistré `palette: [String: String]` (fond, texte, accent) rempli depuis `Theme.current`
(App/Design/Themes.swift) dans `DictionaryModel.renderer(...)`. Même chose pour `CardHTML.page`.

### [ ] C — Dictionnaire sur scans : boîtes de caractères précises
NDLOCR donne des boîtes de caractères **proportionnelles** (`CharacterLayout.proportional`) → le mot touché peut
être décalé d'un caractère. Idée : après NDLOCR, lancer seulement la **reconnaissance** PP-OCRv5 (CTC, positions par
pas de temps, déjà codé dans `PPOCREngine.recognize(_:in:model:charset:)`) sur la même découpe de ligne et
recopier les centres si les deux textes ont la même longueur (sinon garder proportionnel). Seulement si PP-OCRv5 est
installé. Test : `ONNXEnginesTests` (vrais modèles, voir § 7).

### [ ] D — GLM-OCR plus rapide
Aujourd'hui : une génération par ligne (≈ 1 s/ligne sur Mac). Pistes :
1. Grouper 3-5 lignes voisines par image (un seul appel), découper la réponse par `\n`, garder si le nombre de lignes colle.
2. ONNX : essayer le fournisseur CoreML (`ORTCoreMLExecutionProviderOptions`) pour le détecteur PP-OCRv5 / NDLOCR
   (formes fixes : DEIM 800×800) ; garder le CPU si erreur.
3. Mesurer la mémoire sur l'iPad **avec permission** (ios-mcp) avant de toucher au reste.

### [ ] E — Vrais tests sur l'iPad (demander la permission, dire pourquoi)
Priorité : mode paysage (jamais vérifié), barre flottante, menu de sélection « Dictionnaire », toucher sur scans,
téléchargement + vitesse des 3 moteurs OCR, mémoire de GLM-OCR, révisions, import `.apkg` dans Anki.
Noter les bugs, en corriger 2-3, le reste en bas de ce fichier (§ 9).

### [x] F — Netteté des scans DE-GAN (fait le 21/10, non testé sur l'iPad)
Fait aussi : fond de page Blanc / Crème / Tamisé / Sombre (`PageTone.swift`), barre flottante à 3 boutons,
navigateur ouvert (`WebPanel`), panneaux sans flou. DE-GAN : poids « binarisation » convertis par
`tools/degan_to_onnx.py` (h5py + onnx, sans TensorFlow) en ONNX fp32 **256×256 fixe** (CoreML NeuralNetwork :
0,009 s/tuile contre 0,31 s en CPU ; le fp16 / formes libres font retomber sur le CPU ; MLProgram refuse MaxPool).
Fichier : `~/Projets-iPad/kyokasho-modeles/degan-binarize.onnx` (124 Mo), à envoyer par AirDrop puis
Réglages → Netteté des scans → Importer. Lecteur : menu de la page → « Netteté des scans ».
Code : `PageEnhancer` (ONNXOCRKit, tuiles qui se recouvrent), `ScanSharpening` (rendu CGPDF, caches mémoire 8 pages
+ disque), `TonedPage.draw` (image posée avec `transform(for:)`, vérifié sur Mac). Test : `testDEGAN`.
À vérifier sur l'iPad : la page nettoyée apparaît sans tourner la page (`redrawVisiblePages`, sinon
`layoutDocumentView()` ou réinstaller le document), vitesse, mémoire (≈ 45 Mo de tampons + 124 Mo de modèle).
Limite : pages avec texte intégré (dont scans avec couche OCR) ignorées. TextBSR (ESRGAN ×4) écarté : trop lourd.

## 6. Carte du code (où est quoi)

- **`project.yml`** (XcodeGen) : versions, paquets `KyokashoKit` + `GLMOCRKit`, produits utilisés par l'app.
- **`packaging/entitlements-trollstore.plist`** : identité, trousseau, `increased-memory-limit` (GLM-OCR).
- **`Packages/KyokashoKit/`** (testé avec `swift test`, macOS 14+) :
  - `ReaderCore` : modèles (`LibraryDocument` avec `firstPageIndex` / `pageLabel`), `AppDatabase` (GRDB, migrations
    v1, v2-ocr, v3-page-one), réglages (`OCREngineChoice` : auto, pdfText, vision, ndlocr, ppocr5, glmocr).
  - `OCRKit` : `PageRenderer` (3000 px), `PDFPool` (PDF partagés + mémo « page avec texte »), `VisionOCREngine`
    (`minimumTextHeight` 0,004), `PDFTextEngine`, `OCRService` (actor, cache, `register`, `resolve`),
    `ModelStore` (catalogue `ModelSpec`, téléchargement + SHA-256), `NeuralOCR` (image → tenseur, DB, CTC, PARSeq,
    ordre de lecture), `OCRPage.character(at:tolerance:)` (toucher tolérant), cache OCR **version 3**.
  - `ONNXOCRKit` : `PPOCREngine`, `NDLOCREngine` (ONNX Runtime 1.24.2, sessions en cache).
  - `YomitanKit` (**GPL**) : japonais, déconjugaison. `DictionaryKit` : base, import, `Translator`,
    `GlossaryRenderer`, `CardFields`.
  - `ReviewKit` : cartes, FSRS (swift-fsrs fixé sur un commit de main), `ReviewStore`, `Exporters` (CSV, .apkg, AnkiMobile).
- **`Packages/GLMOCRKit/`** (MLX, compilé seulement par Xcode / `swift build` dans ce dossier) : `GlmOcr.swift` +
  `QwenVLHelpers.swift` (copiés de mlx-swift-lm, MIT), `GLMOCREngine` (lignes PP-OCRv5/Vision → relues par l'IA).
- **`App/`** :
  - `KyokashoApp.swift` (racine `.id(theme)`, alerte mémoire → libère PDF / modèles), `AppModel.swift`
    (documents, `delete` optimiste, `pendingDocuments` pendant la lecture, enregistrement des moteurs OCR).
  - `Design/` : `Atelier.swift` (couleurs lues dans `Theme.current`), `Themes.swift` (5 thèmes + `ThemePickerView`).
  - `Library/` : `LibraryView` (grille, barre latérale, Révisions, suppression), `ThumbnailCache` (Core Graphics).
  - `Reader/` : `ReaderController` (construction du document, toucher/survol/Pencil/sélection → dictionnaire, OCR,
    recherche, rognage), `ReaderScreen` (chrome, popup, flèches clavier, champ de page), `FloatingToolbar`,
    `HardwareKeyboard`, `InkOverlay`, `ReaderSheets`, `TextPageSheet`.
  - `Dictionary/` : `DictionaryModel` (audio, renderer), `LookupPopup`, `LookupWebView`, `DictionaryViews`.
  - `Review/` : `ReviewModel`, `ReviewScreen`, `CardBrowserView`, `CardWebView`, `ReviewSettingsView`.
  - `Study/` : `StudyPanel` (Texte / Mots / Notes / Repères), `DeepL`. `Drive/`. `Settings/` : `SettingsView`
    (Apparence / Lecture / Japonais / Cartes / Comptes / À propos), `OCRModelsView` (téléchargements), `BenchView`.
- Racine : `build_ipa.sh` → `dist/Kyokasho-<version>.tipa` (ignoré par git), `docs/releases/`, `THIRD_PARTY_NOTICES.md`.

## 7. Tester les moteurs OCR sur le Mac (vrais modèles, hors dépôt)

Dossier de modèles (sous-dossiers `ppocr5/`, `ndlocr/`, `glmocr/` comme `ModelStore`) à télécharger **avec
l'accord de l'utilisateur** (URL et empreintes dans `ModelStore.swift`), puis :
```
cd Packages/KyokashoKit && KYOKASHO_MODELS=<dossier> swift test --filter ONNXEnginesTests
cd Packages/GLMOCRKit && KYOKASHO_MODELS=<dossier> swift test
```
Sans la variable, ces tests sont sautés. Le dossier du 21/10 était dans le scratchpad du chat (effacé ensuite).

## 8. Pièges déjà rencontrés

- Noms pris par le SDK / FSRS : `Document` → `LibraryDocument` ; éviter `Card`, `ReviewLog`, `Rating` dans ReviewKit.
- GRDB : écrire en synchrone dans une `Task.detached` ; `didInsert` pour l'id ; dates arrondies à la ms (tests : `accuracy`).
- ZIPFoundation : typer la closure `{ (pos: Int64, size: Int) in … }`.
- PDFKit : pas d'`exchangePage` (plantage) ; RTL double page rangé à la main ; `autoScales` cassé → `fitToPage`.
  PDFKit n'est pas sûr entre fils → passer par `PDFPool` (verrou). Un `PDFDocument` peut être construit hors du fil
  principal puis installé sur le principal (c'est ce que fait `rebuild`).
- Gestes : `cancelsTouchesInView = false` (sinon la sélection de texte est bloquée). Glisser une vue qui bouge :
  `DragGesture(coordinateSpace: .global)` (en local → boucle, gel, plantage).
- Menu d'appui long puis alerte : attendre ~0,35 s, sinon iOS ignore l'alerte.
- Vision : `.accurate` seul lit le japonais ; `minimumTextHeight` bas sinon les petits caractères sont ignorés.
  Monter `OCRPage.currentVersion` quand le résultat OCR change.
- swift-fsrs : tag 5.0.0 inutilisable (API interne) → commit de main. Ne pas remettre `from: "5.0.0"`.
- ONNX Runtime ObjC : pas d'accès aux formes d'entrée ni aux métadonnées → formes connues en dur ; dictionnaire
  PP-OCRv5 téléchargé à part (identique aux métadonnées du modèle, vérifié). NDLOCR : détecteur en **800×800**.
- MLX : compiler demande le « Metal Toolchain » d'Xcode (installé le 21/10). `UserInput(prompt:images:)` de
  mlx-swift-lm 2.29.3 **perd les images** → utiliser `UserInput(chat: [.user(…, images: …)])`. GLM-OCR : jetons
  de fin `<|endoftext|>`, `<|user|>` à passer dans `extraEOSTokens`.
- `NSLock.withLock` existe déjà dans Foundation.
- Le paysage n'a **jamais** été vérifié (le simulateur sans fenêtre ne pivote pas).

## 9. Idées / à faire plus tard

PP-OCRv6 (RapidOCR le propose déjà), envoi des médias vers AnkiMobile, synchro des cartes par Drive,
statistiques avancées, Surya via le Mac (refusé pour l'instant : hors règle « tout sur l'iPad »).
