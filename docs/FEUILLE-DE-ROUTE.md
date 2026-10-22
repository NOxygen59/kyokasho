# Feuille de route Kyōkasho — à lire en entier au début de chaque chat

> Ce fichier + `docs/IA-LOCALE.md` (avant de toucher à l'IA) suffisent. Ne relis pas le code « pour voir » :
> `grep -rn 'FDR-V3' App Packages` donne les endroits exacts d'une étape. Une session = les retours de l'utilisateur,
> sinon l'étape suivante du § 7 ; puis commit + push (+ release **si demandée**), puis résumé simple.
> **État au 22/10/2026 : v0.8.7 publiée (build 26)** (V2, V12, V4, V13, V1 non vérifiés sur l'iPad). L'IA locale (OvisOCR2, analyse, vérification) **marche sur
> l'iPad** (confirmé par l'utilisateur). Le reste marqué « non vérifié » peut être faux sur l'appareil.

## 1. Prompt à coller dans le nouveau chat

```
Projet Kyōkasho (~/Projets-iPad/kyokasho). Lis docs/FEUILLE-DE-ROUTE.md (et docs/IA-LOCALE.md si l'étape touche
l'IA) puis `git log -5 --oneline`. Fais mes retours s'il y en a, sinon l'étape suivante non cochée du § 7.
Économise les tokens (§ 4). Pas de simulateur, pas d'iPad sans ma permission.
```

## 2. Règles de l'utilisateur (obligatoires)

- **Français, court, simple** (l'utilisateur ne code pas) : dire *ce qui change pour lui* et *pourquoi*. Le plugin
  « caveman » ne remplace **pas** cette règle.
- **Jamais** demander ni taper un mot de passe, une clé API ou un jeton.
- Suppression de ses fichiers : `trash`, jamais `rm`. **Ne jamais supprimer un dépôt GitHub.**
- Commits en français, finis par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (adapter le modèle).
- **Simulateur interdit** sauf « tu peux tester ». iPad (ios-mcp, souvent déconnecté) : demander + dire pourquoi.
- Usage perso, jamais distribué. Dépôt **privé** `NOxygen59/kyokasho`, bundle `fr.noxygen59.kyokasho`.
  **iOS 16.0** minimum (iPad Pro 12.9" M1 8 Go, iOS 16.6.1, TrollStore + jailbreak Dopamine). App **paysage**.
- **Rétroportage iOS 16** : combler ce qui manque par du code **équivalent**, jamais retirer la fonction ni couper un
  contrôle du compilateur (voir `docs/IA-LOCALE.md`). Forks MLX : `NOxygen59/mlx-swift`, `NOxygen59/mlx-swift-lm`
  (branche `ipad-ios16`, publics comme ses autres forks).
- Dépôt **public** `NOxygen59/kyokasho-models` (`~/Projets-iPad/kyokasho-modeles`) : **seulement** DE-GAN
  (release `degan-v1` + GPL) et `latest.json`. Jamais le code ni le `.tipa`.
- Chaque fichier : `// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`. Code GPL → seulement
  `YomitanKit`. Code copié → garder son copyright (`MeCabC` BSD). Toute dépendance / modèle →
  `THIRD_PARTY_NOTICES.md` + `AboutView` (`App/Settings/SettingsView.swift`, fonction `credit`).
- **Jamais** de PDF, dictionnaire, modèle ni donnée tierce dans le dépôt. Modèles = téléchargés à la demande.
- En ligne seulement : DeepL (option), téléchargements demandés (audio, modèles), navigateur à côté, avis de mise à
  jour (`latest.json` 1×/lancement) + API GitHub des releases du dépôt privé si GitHub est connecté.
- Télécharger sur le Mac : dire quoi / d'où / taille et **demander** (sauf OvisOCR2 et Qwen3-VL : autorisés le
  22/10 pour tester). Le PDF d'essai de l'utilisateur : `~/Downloads/INTERIOR COORDINATOR HANDBOOK HAWE.pdf`
  (manuel japonais de design d'intérieur, 24 p.) — utile pour tester, **jamais** dans le dépôt.
- Release **seulement quand l'utilisateur la demande**. Il numérote lui-même (0.8.5.1, 0.8.6…).

## 3. Déboguer avec l'utilisateur

- **Mode diagnostic** (Réglages → Outils → Diagnostic, `App/Settings/Diagnostics.swift`) : il active, refait le
  geste, « Partager le journal » (ou Fichiers → Kyōkasho → Diagnostics/journal.txt). Erreurs toujours notées, MLX
  compris (avant l'arrêt). Ajouter `Diagnostics.log / measure / error` sur tout nouveau chemin lourd.
- Rapport `.ips` : `dwarfdump --uuid build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM` doit = `slice_uuid`, puis
  `atos -arch arm64 -o <dSYM>/Contents/Resources/DWARF/Kyokasho -l <base> <adresses>` (base = `usedImages` Kyokasho).
  Attention : `build_ipa.sh` écrase l'archive → symboliser **avant** de reconstruire.

## 4. Économiser les tokens (méthode qui marche)

- Gros fichier : `grep -n` puis `sed -n 'A,Bp'`. Jamais `ReaderController.swift` (2100 l.) en entier.
- Modifier : `python3 - <<'EOF' … assert s.count(a)==1 … EOF` (attention aux `"""` collés à un `"` : préférer
  des chaînes `'…'` Python quand le texte Swift contient des guillemets).
- Fichier ajouté dans `App/` → `xcodegen generate -q` avant de compiler.
- Sorties filtrées :
  - tests : `cd Packages/KyokashoKit && swift test 2>&1 | grep -E ': error|error:|with [1-9][0-9]* failure' | head -5`
  - app : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E ' error:|BUILD' | sort -u | head -20`
  - `.tipa` : `./build_ipa.sh 2>&1 | grep -E 'OK|error' | tail -2` → `dist/Kyokasho-<version>.tipa`
- Visuel : rendu d'essai sur Mac (script Swift dans le scratchpad, `Read` d'un PNG ≤ 900 px). Ex. la mise en page IA
  a été vérifiée ainsi (WKWebView `takeSnapshot`).
- Gros chantier : `caveman:cavecrew-investigator` pour localiser, puis **toujours** `caveman:cavecrew-reviewer` sur
  le diff avant commit (il trouve de vrais bugs à chaque fois ; vérifier ses 🔴 avant de corriger).
- **Balises `FDR-…`** : chaque endroit à modifier pour une étape non faite porte `// FDR-<étape> : <quoi>`.
  Étape finie → retirer ses balises (`grep -rn 'FDR-X'` vide) et cocher ici. Étape planifiée → poser ses balises.

## 5. Release (si demandée)

1. `project.yml` : `MARKETING_VERSION` (celle que l'utilisateur dit) et `CURRENT_PROJECT_VERSION` +1.
2. `docs/releases/vX.Y.Z.md` (Installation / Modifications / Vérifié – non vérifié), ligne en haut du tableau
   « Versions » du README, ligne « État » en tête de ce fichier.
3. `xcodegen generate -q && ./build_ipa.sh`, puis `git add -A && git commit -m "Version X.Y.Z (…)" && git tag vX.Y.Z
   && git push origin HEAD --tags` et `gh release create vX.Y.Z dist/Kyokasho-X.Y.Z.tipa --title "Kyōkasho X.Y.Z — …"
   --notes-file docs/releases/vX.Y.Z.md`.
4. `~/Projets-iPad/kyokasho-modeles/latest.json` (`version`, `build`, `page`, `notes`), commit + push, contrôle :
   `gh api repos/NOxygen59/kyokasho-models/contents/latest.json --jq .content | base64 -d | grep version`.
5. Envoyer le `.tipa` à l'utilisateur (`SendUserFile`).

## 6. Ce qui existe (fait, et comment)

> « ✅ Mac » = vérifié par test ou image d'essai. « ✅ iPad » = confirmé par l'utilisateur.

**Lecteur** (`App/Reader/ReaderController.swift`, `ReaderScreen.swift`)
- Document construit hors du fil principal : `rebuild → build → install` ; pages `TonedPage`
  (`TonedPageProvider.classForPage` ; `copy()` perd les propriétés Swift → `pageKey` / `originalBox` recopiés).
  Fond de page (`PageTone`), nettoyage des scans (`ScanSharpening` + `PageCleaner`, caches mémoire 8 + disque
  `Caches/Sharpened`), redessin sans reconstruire `ReaderPDFView.redrawVisiblePages()`.
- Pages : `turnTarget` (double page), flèches. Menu « … » : Affichage (fond, furigana + couleur, nettoyage, zones OCR),
  Cette page, notes, nouvelle note flottante, quota DeepL, moniteur, réglages du document.
- Dictionnaire au toucher / survol / Pencil : `lookup(at:fromHover:)` : d'abord l'OCR « réel » de la page
  (`realOCR`, avant la couche texte cachée des PDF photo), sinon texte du PDF (≥ 8 caractères) ; **mot entier**
  (`wordStart(in:at:)`, découpage du dictionnaire) ; repère OCR ↔ page par `PageFrame` (rotations ✅ Mac).
- Notes flottantes `NoteWindow` (PKCanvasView + UITextView, redimensionnable) + ancres `NoteAnchorAnnotation`
  (`PageComment.anchor*`, migration `v4-note-canvas-anchor`), `goToAnchor` (surlignage 1,5 s).
- Barre d'outils flottante `FloatingToolbar` (verticale / horizontale / rétractée, position en `@AppStorage`) :
  **modèle à réutiliser pour V1**.
- Moniteur de ressources `ResourceMonitor` (CPU / RAM / FPS, Swift Charts).
- Page vers IA (`AIPageSheet`, double page : p. X / p. Y / les deux).

**OCR** (`OCRKit`, `ONNXOCRKit`, `GLMOCRKit`)
- `OCRService` (actor) : cache SQLite par page et moteur (`OCRPage.currentVersion` = 5) ; `resolve` (auto : texte PDF
  sinon NDLOCR → PP-OCRv5 → Vision) ; **post-traitement** `OCRProofreader` (dictionnaire, confusions 未/末…) →
  `OCRLine.doubt` ; `store` (corrections).
- NDLOCR + passe PP-OCRv5 pour mesurer les caractères (`CharacterAlignment`).
- Relecture IA des lignes douteuses : `ReaderController.rereadDoubtful` (GLM-OCR), option `ocr.aiReread`.
- Correction à la main : appui long sur une ligne en mode Brut → `correctOCRLine` (`edited` = jamais retouchée).

**Panneau d'étude** (`App/Study/StudyPanel.swift`) — onglets Texte / Mots / Notes / Repères
- Texte : recherche (kanji / kana / romaji, `PageTextSearch`), moteur OCR en icône, « Mis en forme » (`OCRLayout`,
  géométrie ou PP-DocLayout / DocLayout-YOLO), « Brut » (doutes soulignés), **✨ Mise en page IA** (`AILayoutView` :
  Markdown d'OvisOCR2 → `AILayout.blocks` → HTML du thème, furigana, dictionnaire, figures découpées en vignettes ;
  **日本語 / Français** avec traduction Qwen3-VL hors ligne), ふりがな (`FuriganaTextView`, WKWebView `<ruby>`),
  traduction DeepL.
- Vérifier la double page (OvisOCR2) : menu du moteur → `VerifySheet`.

**Japonais**
- Dictionnaires Yomitan (`DictionaryKit`, `YomitanKit`), popup `LookupPopup` (+ traduction FR des définitions
  anglaises par DeepL dans la fiche, 👍 / 👎 / ✏️ gardés).
- **MeCab + UniDic-lite** (`MorphologyService`, Réglages → Modèles groupe 2) → `Furigana.analyzer` : lectures selon
  le contexte, page et panneau.
- Furigana sur la page : `FuriganaLayer` (taille ≥ 32 % du caractère, jamais de chevauchement : `layout` + `spread`).

**Bibliothèque** (`App/Library`)
- Import, renommer, page 1, **Fusionner des PDF** (`PDFMergeView`, Outils), **Analyser le document entier**
  (`DocumentAnalysisSheet` / `DocumentAnalysisService` : vote OCR + IA, fiabilité, choix conseillés, traduction de
  tout le document ; rapport `Application Support/Analysis/<id>.json` + `Analysis/<id>/*.md`).

**IA locale** : voir `docs/IA-LOCALE.md` (forks MLX iOS 16, lecteurs, mesures, tests).

**Réglages** (`App/Settings`) : Apparence et lecture ; Japonais (dictionnaires, lecture des scans, DeepL) ;
**Modèles d'IA et outils** rangés par usage (`ModelsView` : 1 lire, 2 furigana, 3 relire / vérifier / traduire,
4 mise en forme, 5 nettoyage ; « Recommandé » / « Optionnel ») ; Cartes ; Outils (moniteur, **diagnostic**) ;
Comptes (Drive) ; À propos (+ **connexion GitHub** device flow → mise à jour par TrollStore `UpdateInstaller`).

## 7. Étapes à faire — demande du 22/10 (14 points), dans cet ordre conseillé

> Ordre proposé : d'abord ce qui évite les plantages et la RAM (V2, V12, V4, V13), puis l'interface (V1, V6),
> puis les fonctions (V3, V5, V8, V10, V11, V14, V7), et le nettoyage (V9) en dernier.

### [x] V2 — IA : RAM au plus bas quand on ne s'en sert pas
- **Fait (22/10, non vérifié sur iPad)** : `GLMModel.using(directory:)` compte les lectures en cours, vide
  `MLX.GPU` après chaque lecture et libère le modèle après 45 s sans lecture (`idleDelay`, 2 min jugé trop long) ; `SessionCache` (ONNX)
  se vide après 30 s sans usage. MeCab gardé (mmap). Reste : mesurer au moniteur sur l'iPad.
- Constat : `GLMModel` garde le dernier modèle MLX **chargé** jusqu'à la fin de l'app ; `SessionCache` (ONNX) garde
  les sessions NDLOCR / PP-OCR / mise en page ; `MLX.GPU` garde un cache (256 Mo max).
- Faire : (1) `GLMModel` : minuteur d'inactivité (ex. 90 s sans lecture → `unload()`), compteur d'utilisations en
  cours (ne jamais décharger pendant une lecture) ; (2) `SessionCache` : `clear()` + décharge après inactivité et sur
  avertissement mémoire (`UIApplication.didReceiveMemoryWarningNotification` déjà écouté dans `KyokashoApp`) ;
  (3) `MLX.GPU.clearCache()` après chaque lecture longue ; (4) jamais de chargement anticipé (vérifier
  `loadIfInstalled` de MeCab : `mmap`, coût faible, garder). Mesurer avec le moniteur avant / après.
- Balises `FDR-V2`.

### [x] V12 — Retour à la bibliothèque = IA déchargées
- **Fait (22/10, non vérifié sur iPad)** : `RootView.releaseAI()` (`App/KyokashoApp.swift`) quand le lecteur se
  ferme (`openDocumentId` → nil ; `LibraryView.onAppear` ne se relance pas après un `fullScreenCover`) ou que l'app
  passe en arrière-plan ; rien si une analyse tourne ; MLX via `GLMOCREngine.unloadIfIdle()` (jamais pendant une
  lecture). Le chat V7 devra charger / décharger lui-même.
- `LibraryView.onAppear` (et `scenePhase` → arrière-plan) : `GLMOCREngine.unload()` (tous modèles MLX),
  `SessionCache.clear()`, `MLX.GPU.clearCache()`. Exception : le chat des Réglages (V7) charge son modèle à
  l'ouverture de l'écran et le décharge à la fermeture. Ne pas interrompre une analyse en cours (V4) : si
  `DocumentAnalysisService.progress != nil`, ne rien décharger. Balises `FDR-V12`.

### [x] V4 — Une tâche IA continue quand on change de page ou de vue ; arrêt seulement par bouton (double confirmation)
- **Fait (22/10, non vérifié sur iPad)** : `App/Reader/AITaskCenter.swift` (`AITaskCenter` + pastille
  `AITaskPill` sur le lecteur et la bibliothèque, « Arrêter » → 2 alertes). Passent par lui : relecture GLM
  (clé `reread|doc|page|version`, nouvelle version = l'ancienne remplacée), vérification Ovis (continue lecteur fermé,
  Markdown gardé ; propositions perdues si le lecteur est fermé), mise en page IA et traduction (`AILayoutView`).
  Texte partiel après arrêt jamais gardé (`Task.checkCancellation`). Lecteur rafraîchi à la fin d'une tâche
  (`AITaskCenter.finished` → `reloadOCRAfterAITask`). L'analyse du document reste dans `DocumentAnalysisService`.
- Aujourd'hui annulées en changeant de page : `ReaderController.ocrPage didSet` (`rereadTask?.cancel()` quand
  `ocrPage == nil`), `focus(_:)`, `pageChanged`, `close()` (relecture, vérification), `ensureOCR` (file vidée).
- Faire : un **gestionnaire de tâches IA** unique (`AITaskCenter`, `@MainActor ObservableObject`) qui possède les
  `Task` (relecture GLM, vérification Ovis, mise en page IA, traduction, analyse, scan du document V3), avec nom,
  page, progression ; les vues ne font qu'**afficher** ; résultat écrit dans le cache même si la page n'est plus
  affichée. Petit indicateur (pastille flottante) « IA : … » ; bouton « Arrêter » → alerte → 2e confirmation.
  `close()` du lecteur ne doit plus annuler ces tâches (seulement la file `ensureOCR` d'affichage).
- Balises `FDR-V4`.

### [x] V13 — Panneau de droite : ne pas revenir en haut quand on bouge dans la même page
- **Fait (22/10, non vérifié sur iPad)** : `pageChanged` → `schedulePageSettled(samePageKeeps: true)` ; si la page
  courante n'a pas changé (`settledSource`) et que la page de travail est encore visible, `pageSettled(keepFocus:)`
  ne republie ni `ocrPage`, ni `focusSource`, ni `pageHasPDFText`. Position de défilement par page : pas faite
  (changer de page remonte en haut, voulu).
- Cause probable : glisser change `currentSourcePage` / `focusSource` ou republie `ocrPage` (même contenu) →
  `StudyTextTab` refait ses `.task(id:)` / reconstruit `FuriganaTextView` (WKWebView rechargée) → défilement à 0.
- Faire : ne mettre à jour `focusSource` / `ocrPage` que si la **page de travail** change vraiment (comparer avant
  d'assigner) ; `RubyWebView.updateUIView` ne recharge déjà que si le HTML change → vérifier que `html` est stable ;
  garder la position de défilement par page (`ScrollViewReader` + id du bloc, ou `scrollView.contentOffset` gardé
  dans le coordinateur). Le panneau ne bouge **que** si l'utilisateur interagit avec lui ou change de page.
- Balises `FDR-V13`.

### [x] V1 — Panneau de droite détachable (style fenêtre : réduire, plein écran, redimensionner)
- **Fait (22/10, non vérifié sur iPad)** : `App/Reader/DetachedPanel.swift` (`StudyPanelMode` docked / floating /
  full / minimized en `@AppStorage`, `StudyWindowButtons` dans l'en-tête de `StudyPanel`, `DetachedPanel` : poignée
  du haut, coin, plein écran, pastille « Étude »). `ReaderScreen.docked` : la colonne de droite n'existe que pour le
  navigateur ou le panneau ancré. Passer d'ancré à détaché reconstruit le panneau (onglet gardé, défilement non).
- Aujourd'hui : `StudyPanel` collé à droite dans `ReaderScreen` (`side == .study`).
- Faire : conteneur `DetachedPanel` sur le modèle de `FloatingToolbar` / `NoteWindow` (déjà : glisser par l'en-tête,
  coin de redimensionnement, `@AppStorage` x/y/w/h) avec 3 boutons d'en-tête : **réduire** (pastille), **ancrer à
  droite** (comportement actuel), **plein écran** ; état persistant. Garder l'ouverture d'office en paysage.
- Balises `FDR-V1`.

### [ ] V6 — Thèmes (fonds personnalisés, innover)
- `App/Design/Themes.swift` (`Theme`, `ThemeManager`, `ThemePickerView`) + `Atelier.swift` (couleurs).
- Idées : fonds dessinés en SwiftUI (pas d'image tierce) : papier washi (bruit), grille d'architecte (lignes fines,
  thème du manuel), plan d'intérieur discret, dégradé « lumière du soir », mode encre (noir et or), sakura discret ;
  aperçu en direct ; le thème colore aussi le HTML (panneau, dictionnaire, cartes : voir backlog B4).
- Balises `FDR-V6`.

### [ ] V3 — Furigana refaits sur le texte de l'IA, document scanné à l'import
- (a) **Scan obligatoire** : à l'import d'un PDF (`AppModel.importFiles`) et à l'ouverture d'un document, lancer
  (via V4) la lecture IA (OvisOCR2) des pages **pas encore lues** seulement ; petite fenêtre avec barre de
  pourcentage + « Voir le détail » (journal en direct : page, durée, erreurs — réutiliser `Diagnostics.measure`).
- (b) **Furigana d'après le texte de l'IA** : texte = Markdown d'OvisOCR2 (fiable) ; positions = boîtes de
  caractères de l'OCR habituel (NDLOCR/PP). Aligner les deux (`OCRReferenceDiff.align` donne déjà la lecture IA de
  chaque ligne OCR ; puis `CharacterAlignment` pour caractère ↔ boîte) → lectures MeCab sur le texte IA, posées
  sur les boîtes OCR alignées. Centrer chaque lecture sur le **groupe de kanji** (pas sur le mot entier),
  `FuriganaLayer.marks(from:frame:)` + `layout`. Vérifier par une image d'essai Mac sur le manuel.
- Balises `FDR-V3`.

### [ ] V5 — Revérifier les « caractères douteux » à chaque nouvel OCR de la page
- `runOCR(force:)` / « Relancer » / nouvelle lecture IA → relancer `OCRProofreader` et rafraîchir `doubtRow`
  (aujourd'hui seulement à la 1re lecture : `postProcess` sur calcul neuf, `refineOCR` si `proofread != true`).
- Balises `FDR-V5`.

### [ ] V8 — Exporter un document depuis la bibliothèque (plusieurs formats, style GoodNotes)
- Menu d'appui long `LibraryView.menu(for:)` → « Exporter… » : PDF d'origine ; **PDF annoté** (surlignages, dessins
  `InkOverlay`, notes / ancres aplaties : rendre chaque page dans un `UIGraphicsPDFRenderer`) ; **texte / Markdown**
  (OCR, mise en page IA, traduction FR si présente, notes) ; **images PNG** par page (zip) ; cartes `.apkg` (existe).
  Choix des pages ; `ShareLink` / `UIDocumentPickerViewController(forExporting:)`.
- Balises `FDR-V8`.

### [ ] V10 — Réglages : graphique de la place prise par l'app
- Tailles : Documents (PDF), modèles (`ModelStore.root` par modèle + `unidic`), analyses (`Analysis`), base SQLite
  (OCR, notes, cartes), caches (`Caches/*`, vignettes, nettoyage), temporaires. Barre empilée Swift Charts + légende,
  calcul hors du fil principal (`FileManager.enumerator` + `totalFileAllocatedSize`). Balises `FDR-V10`.

### [ ] V11 — Effacer le cache (sans rien perdre d'important)
- Effacer seulement : `Caches/` (vignettes régénérables, `Sharpened`, `Update`), `tmp`, données WebKit, cache
  `LayoutRegionsCache`, `MLX.GPU.clearCache()`. **Garder** : PDF, base (notes, OCR, cartes), `Analysis`, modèles,
  UniDic, réglages. Confirmation + taille libérée affichée. Balises `FDR-V11`.

### [ ] V14 — Ajouter un PDF à un document existant (suite du manuel), avec ordre
- Menu du document → « Ajouter des pages… » : liste réordonnable [document actuel] + nouveaux PDF (réutiliser
  `PDFMergeView`). Fusion dans un nouveau fichier puis **remplacement** du PDF du document (même id).
- **Délicat** : tout ce qui est rangé par numéro de page doit être renuméroté si des pages sont insérées **avant** :
  tables `ocrResult`, `highlight`, `inkDrawing`, `bookmark`, `pageComment`, `pageTransform` (colonne `pageIndex`),
  fichiers `Analysis/<id>/<lecteur>-<page>.md` et `fr-<page>.md`, rapport JSON, caches `Sharpened`. Faire une table
  de correspondance ancienne → nouvelle page, appliquer en une transaction GRDB, puis `document.pageCount`.
  Ajout **à la fin** = aucun renumérotage (cas le plus courant : proposer d'office).
- Balises `FDR-V14`.

### [ ] V7 — Réglages : une page par IA locale (+ chat pour celles qui discutent)
- Une page par modèle (OvisOCR2, GLM-OCR, Qwen3-VL-4B, MeCab, NDLOCR…) : description, taille, état chargé / non,
  mémoire, dernier usage, bouton « Décharger », réglages propres (longueur de lecture, résolution, option
  « ajouter à l'analyse ») et **journal** des dernières tâches (via `Diagnostics`).
- **Chat** pour Qwen3-VL-4B (seul vrai modèle de conversation ; OvisOCR2 / GLM-OCR = OCR seulement) : `ChatSession`
  de mlx-swift-lm ou `UserInput(chat:)` avec historique, réponses en flux, historique gardé (JSON par session),
  modèle chargé à l'ouverture, **déchargé en quittant** l'écran (V12). Uniquement dans les Réglages.
- Balises `FDR-V7`.

### [ ] V9 — Désencombrer le code (en dernier)
- Chercher les types / fichiers inutilisés (`grep` du nom de chaque `struct` / `func` hors de son fichier), ex. à
  vérifier : `BenchView` (banc d'essai OCR), `TextPageSheet`, anciennes options (`LayoutEngineMenu`…), copies
  devenues inutiles. Découper `ReaderController.swift` (2100 l.) en extensions par thème (OCR, notes, IA, gestes,
  dictionnaire) **sans changer le comportement**. Profiler (moniteur) : rendus SwiftUI en trop, `@Published` trop
  larges. Toujours `cavecrew-reviewer` après. Balises `FDR-V9` (fichiers à regarder).

## 8. Backlog (plus ancien, après le § 7)

- [ ] **S — Lexique du domaine** (design d'intérieur) modifiable : mots connus pour `OCRProofreader` /
  `DocumentAnalysisService.preferred` **et** glossaire de traduction (aujourd'hui `Qwen3VLReader.defaultGlossary`,
  ≈ 50 termes). Balises `FDR-S`.
- [ ] **N — Furigana « vérifiés »** : MeCab et dictionnaire d'accord, sinon doute signalé (à fondre dans V3).
- [ ] **K — Grammaire** : conception `docs/GRAMMAIRE.md` ; coder seulement après accord.
- [ ] **B1 — Gestes / zoom** (retour du 21/10, cause pas trouvée) : demander lesquels. Pistes (`configureGestures`,
  `applyDisplaySettings`) : modes non continus, `singleTap.require(toFail: doubleTap)`, survol, glisser, `fitToPage`
  à chaque changement de taille. Balises `FDR-1`.
- [ ] **B3 — Furigana vertical**, furigana imprimés à sauter, texte vertical du panneau (`writing-mode`). `FDR-3`.
- [ ] **B4 — Thème dans le dictionnaire et les cartes** (`GlossaryRenderer`, `CardHTML` : palette non enregistrée).
  `FDR-4` (à fondre dans V6).
- [ ] **B5 — Mise en page** : tableaux (SLANet), texte vertical (PP-DocLayout `vertical_text`). `FDR-5`.
- [ ] **B6 — Performance** : `Translator.segment` mémo, recherche FTS5, rotation vImage, révisions hors fil
  principal, passe PP à la demande, `PageCleaner` 2000 px. `FDR-6.x` (à fondre dans V9).
- [ ] **B7 — GLM-OCR plus rapide** (3-5 lignes par image). `FDR-7`.
- Écarté : Mac Catalyst (mis de côté le 22/10, ne pas proposer), Qwen3-VL-8B (5,8 Go, trop pour 8 Go).

## 9. Carte du code

- `project.yml` (XcodeGen ; versions ; paquets `KyokashoKit`, `GLMOCRKit`), `packaging/entitlements-trollstore.plist`
  (mémoire augmentée + adressage étendu + trousseau), `build_ipa.sh`.
- `Packages/KyokashoKit` (`swift test`, macOS 14+) : `ReaderCore` (modèles, `AppDatabase` GRDB, réglages,
  `Furigana` + `analyzer`), `OCRKit` (`OCRModels`, `OCRService`, `ModelStore` = catalogue des modèles,
  `OCRProofreader`, `OCRReferenceDiff`, `DocumentAnalysis`, `AILayout`, `OCRLayout`, `PageCleaner`, `NeuralOCR`),
  `ONNXOCRKit` (NDLOCR, PP-OCRv5, `SessionCache`, DE-GAN, `LayoutDetector`), `DictionaryKit`, `YomitanKit` (GPL),
  `ReviewKit` (FSRS), `MeCabC` + `MorphologyKit` (MeCab, `UniDic.extract`).
- `Packages/GLMOCRKit` (MLX) : `GLMOCREngine` (+ `GLMModel`), `OvisOCR2.swift` (`PageVLMReader`, `OvisOCR2Reader`,
  `Qwen3VLReader` + `translate` + glossaire), `Tokenizers+MLX.swift`, tests `OvisOCR2Tests` (vraies pages).
- `App/` : `KyokashoApp` (lancement : `Diagnostics.start`, mise à jour, MeCab), `AppModel` (import, post-traitement
  OCR) ; `Reader/` (`ReaderController`, `ReaderScreen`, `FuriganaLayer`, `NoteWindow`, `ResourceMonitor`,
  `FloatingToolbar`, `InkOverlay`, `ReaderSheets`) ; `Study/` (`StudyPanel`, `FuriganaText`, `AILayoutView`,
  `VerifySheet`, `PageTextSearch`, `DeepL`) ; `Library/` (`LibraryView`, `PDFMergeView`, `DocumentAnalysisService`,
  `DocumentAnalysisSheet`) ; `Dictionary/` (`MorphologyService`, `DefinitionTranslation`, popup) ; `Settings/`
  (`SettingsView`, `OCRModelsView`, `Diagnostics`, `GitHubUpdate`, `AppUpdate`) ; `Design/` (`Atelier`, `Themes`).
- Données sur l'iPad : `Application Support/` (base, `Kyokasho/Models/<id>`, `unidic`, `Analysis`),
  `Documents/Diagnostics/journal.txt`, `Caches/` (vignettes, `Sharpened`, `Update`).

## 10. Pièges déjà rencontrés

- Noms pris : `Document` → `LibraryDocument` ; éviter `Card`, `ReviewLog`, `Rating`.
- GRDB : écrire dans une `Task.detached` ; `didInsert` pour l'id ; nouvelle colonne = migration (`v4-…` dernière).
- PDFKit : pas d'`exchangePage` ; `autoScales` cassé → `fitToPage` ; pas sûr entre fils → `PDFPool` ;
  `characterIndex(at:)` ne compte pas les fins de ligne ; `goToNextPage` n'avance que d'une page ; dessin après
  `context.concatenate(transform(for: box))` ; toute conversion OCR ↔ page par `PageFrame` ; PDF photo : couche texte
  vide ou mauvaise → `hasTextLayer` et `realOCR`.
- SwiftUI iOS 16 : `.task(id:)` doit changer pour **tout** changement ; ne pas publier un `@Published` pendant
  `body` (cache non publié + compteur `revision`, cf. `DocumentAnalysisService`) ; menu d'appui long puis feuille :
  attendre ~0,35 s.
- `Task.detached` ignore l'annulation du parent ; un acteur qui `await` peut être réentré (cf. `GLMModel.loading`).
- MLX / iOS 16 : voir `docs/IA-LOCALE.md` (bfloat, Metal 3.0, `remove_addrspace_t`, `reassociate`, `std::format`,
  libc++ — **jamais** `_LIBCPP_DISABLE_AVAILABILITY`), épingle `Package.resolved` à mettre à jour.
- Python dans Bash : `"""…"""` suivi d'un `"` casse la chaîne → `'…'`.
- Le paysage n'a jamais été vérifié par Claude (simulateur sans fenêtre).

## 11. Idées / plus tard

PP-OCRv6, médias vers AnkiMobile, synchro des cartes par Drive, statistiques, redressement des photos de pages,
super-résolution des scans flous.
