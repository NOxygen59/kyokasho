# Feuille de route Kyōkasho — pour un nouveau chat

> À lire **en entier au début de chaque session**. Elle suffit : ne relis pas PLAN.md en entier,
> ni le code « pour voir ». Une session = **une** étape du § 4, puis commit + push, puis stop.

## 1. Prompt à coller dans le nouveau chat

```
Projet Kyōkasho (~/Projets-iPad/kyokasho). Lis docs/FEUILLE-DE-ROUTE.md et `git log -5 --oneline`,
puis fais la prochaine étape non cochée du § 4. Économise les tokens (règles § 3).
Pas de simulateur, pas d'iPad sans ma permission.
```

## 2. Règles de l'utilisateur (obligatoires)

- Parler **français, court, style « cro-magnon »** (phrases simples, pas de jargon inutile), sans perdre en justesse.
  L'utilisateur ne code pas : expliquer simplement *pourquoi* quand on lui demande quelque chose.
- **Jamais** demander ni taper un mot de passe, une clé API ou un jeton. L'utilisateur les colle lui-même dans l'app.
- Suppression locale : `trash`, jamais `rm` définitif sur ses fichiers. **Ne jamais supprimer un dépôt GitHub.**
- Commits en français, finis par la ligne :
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (adapter le nom du modèle si c'est un autre).
- **Simulateur : interdit** sauf si l'utilisateur dit « tu peux tester ». iPad (ios-mcp) : demander la permission + dire pourquoi.
- Usage perso, jamais distribué. Dépôt **privé** `NOxygen59/kyokasho`. Bundle `fr.noxygen59.kyokasho`.
  **iOS 16.0** minimum : aucune API iOS 17+. iPad Pro 12.9" M1, TrollStore. App pensée **paysage**.
- Chaque fichier commence par l'en-tête SPDX (`// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`).
  Code porté d'un projet GPL → seulement dans `YomitanKit`, avec le copyright d'origine + entrée dans `THIRD_PARTY_NOTICES.md`.
  Toute nouvelle dépendance → entrée dans THIRD_PARTY_NOTICES.md + crédit dans l'écran « À propos » (`App/Settings/SettingsView.swift`, `AboutView`).
- **Jamais** de PDF, de dictionnaire, de modèle OCR ni d'autre donnée tierce dans le dépôt. Jamais décompiler une app fermée.
  Ne pas copier d'assets Apple, Sony, Adobe…
- Seul service en ligne autorisé : DeepL (option) + téléchargements que l'utilisateur déclenche (audio, modèles OCR).
- Releases : chaque version = tag + release GitHub avec le `.tipa` + notes honnêtes « vérifié / non vérifié » + ligne dans le tableau Versions du README.

## 3. Économiser les tokens (méthode)

- Ne pas lire un gros fichier en entier : `grep -n 'motif' fichier` puis `sed -n 'A,Bp' fichier`.
- Modifier avec un script `python3 - <<'EOF' … EOF` (remplacement exact + `assert old in s`) ou l'outil Edit.
- Toujours filtrer les sorties :
  - tests : `cd Packages/KyokashoKit && swift test 2>&1 | grep -E 'error|failed|Executed' | tail -5`
  - app : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | sort -u | head -30`
- Pas de captures d'écran, pas de simulateur, pas d'exploration « au cas où ». Pas de sous-agents.
- Fin de session : commit + `git push` + 3 lignes de résumé à l'utilisateur. Cocher l'étape dans le § 4 de ce fichier.

## 4. Étapes restantes (cocher `[x]` quand fini)

### [x] Session 1 — V4-a : ReviewKit compile + tests
Fichiers déjà écrits mais **jamais compilés** : `Packages/KyokashoKit/Sources/ReviewKit/`
`CardTemplate.swift` (moteur de templates + furigana Anki), `ReviewModels.swift` (Deck, NoteTemplate, StudyCard,
ReviewEntry, MemoryState, Grade, AnkiGUID), `ReviewScheduler.swift` (ReviewSettings + FSRS), `ReviewStore.swift`
(base GRDB `review.sqlite` + dossier Media, file de révision, stats, médias, modèle par défaut « Japonais — mot »).

1. `Package.swift` :
   - dépendance swift-fsrs (MIT, auteur Ben Smiley), **fixée sur le commit `4fbaf20` de main** : le tag 5.0.0 garde l'API en interne ;
   - produit `.library(name: "ReviewKit", targets: ["ReviewKit"])` ;
   - cible `.target(name: "ReviewKit", dependencies: [.product(name: "FSRS", package: "swift-fsrs"), .product(name: "GRDB", package: "GRDB.swift"), .product(name: "ZIPFoundation", package: "ZIPFoundation")])` ;
   - `.testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"])`.
2. Corriger les erreurs de compilation. Rappels sur l'API swift-fsrs 5.0 :
   - `FSRS(parameters: FSRSParameters(requestRetention:maximumInterval:enableFuzz:enableShortTerm:))` ;
   - `try fsrs.next(card:now:grade:)` renvoie `.card` et `.log` ; `try fsrs.repeat(card:now:)` renvoie un aperçu indexable par `Rating` (`[rating]?.card.due`) ;
   - `fsrs.getRetrievability(card:now:).number` ; `Card(...)` a un init public, mais `createEmptyCard` n'est **pas** public ;
   - `Rating` vaut `.manual/.again/.hard/.good/.easy` ; `CardState` raw values 0…3 = nos `MemoryState`.
   GRDB enregistre tout seul `[String: String]` et `[String]` en JSON.
3. `Tests/ReviewKitTests/` :
   - **templates** : `{{X}}`, filtres `furigana/kana/kanji/text`, `#if/else`, `#unless`, `#each` + `@index`, blocs Anki `{{#X}}` et `{{^X}}`, `FrontSide`, erreurs `unclosed`/`unexpectedClose`, `ankiSource` ;
   - **Furigana** : `Furigana.anki` puis `ruby` (aller-retour) ; `AnkiGUID` stable ;
   - **FSRS** : une carte neuve notée « Bien » est due plus tard qu'avec « À revoir » ; aperçu dans l'ordre again ≤ hard ≤ good ≤ easy ;
   - **store** :
     - paquet + modèle créés au départ ;
     - doublon par `key` ;
     - `next` donne l'apprentissage d'abord, et la limite de nouvelles cartes par jour vient de l'historique ;
     - `counts` ;
     - `record` puis `undo` ;
     - `addMedia` ne crée qu'un fichier pour un même contenu ; `mediaReferences` ; `removeUnusedMedia` ;
   - **ReviewSettings** : décodage borné ; `dayStart` à 4 h.
4. Ajouter swift-fsrs dans THIRD_PARTY_NOTICES.md. Commit. **Fini quand** `swift test` est vert.

### [ ] Session 2 — V4-b : export CSV, `.apkg`, AnkiMobile
Nouveau fichier `Sources/ReviewKit/Exporters.swift`.

- **CSV** (lisible par Anki) :
  - en-têtes `#separator:comma`, `#html:true`, `#notetype:<nom>`, `#deck:<nom>`, `#columns:<champs…>,Tags`, `#tags column:<n>` ;
  - guillemets façon RFC 4180 (`"` doublé ; quoter si `,` `"` ou retour à la ligne) ;
  - une ligne par carte, champs dans l'ordre de `fieldNames`.
- **`.apkg`** : format décrit par genanki (MIT, github.com/kerrickstaley/genanki, commit 73f1debf). On le **réécrit** en Swift, sans copier de code.
  - Fichier temporaire `collection.anki2` ouvert avec une `DatabaseQueue` GRDB. Tables `col`, `notes`, `cards`, `revlog`, `graves` + index, comme dans `genanki/apkg_schema.py`.
  - Ligne `col` :
    - `crt` = secondes, `mod`/`scm` = millisecondes, `ver` = 11, `dty`/`usn`/`ls` = 0 ;
    - `conf` = JSON (curDeck, curModel…) ;
    - `models` = `{ "<mid>": modèle }` ;
    - `decks` = `"1"` (Default) + notre paquet ;
    - `dconf` = `"1"` (new.perDay 20, delays [1,10], rev.maxIvl 36500…) ;
    - `tags` = `"{}"`.
  - **Modèle** :
    - clés de base : `id` (texte), `name`, `type` 0, `mod`, `usn` -1, `sortf` 0, `did`, `css` ;
    - `flds` : liste de `{name, ord, sticky:false, rtl:false, font:"Hiragino Sans", size:20, media:[]}` ;
    - `tmpls` : `[{name:"Carte 1", ord:0, qfmt, afmt, bqfmt:"", bafmt:"", did:null, bfont:"", bsize:0}]`, où `qfmt`/`afmt` = `CardTemplate(...).ankiSource` ;
    - le reste : `req: [[0,"any",[0]]]`, `latexPre`/`latexPost` (en-tête LaTeX standard), `latexsvg:false`, `tags:[]`, `vers:[]` ;
    - `mid` stable = hachage du nom du modèle (entier positif < 2^53).
  - **Note** :
    - `id` = millisecondes, +1 à chaque note ; `guid` = `card.guid` ; `mid` ; `mod` en secondes ; `usn` -1 ;
    - `tags` = `" a b "` ; `flds` = champs joints par `\u{1F}` ; `sfld` = premier champ sans HTML ;
    - `csum`, `flags` = 0 ; `data` = "".
  - **Carte** : `nid` ; `did` ; `ord` 0 ; `type`, `queue` = 0 ; `due` = numéro d'ordre ; tout le reste à 0 ; `data` = "". Les cartes partent comme **neuves** dans Anki : l'état FSRS n'est pas exporté, le dire dans les notes.
  - **Zip** (ZIPFoundation) : `collection.anki2` + fichier `media` = `{"0":"nom.jpg",…}` + fichiers nommés `0`, `1`… Seulement les médias cités, trouvés avec `ReviewStore.mediaReferences`.
- **AnkiMobile** :
  - URL `anki://x-callback-url/addnote?type=<noteType>&deck=<deck>&fld<Champ>=<valeur>&tags=<…>` ;
  - encodage `urlQueryAllowed` sans `&+=?#` ;
  - texte seulement (AnkiMobile ne prend pas les médias par URL).
- **Tests** : CSV (guillemets, en-têtes) ; `.apkg` (dézipper, ouvrir le sqlite, compter notes/cartes, lire le JSON `models`, vérifier `media`) ; encodage du lien AnkiMobile.
- THIRD_PARTY_NOTICES : genanki = « format seulement, aucun code copié ». Commit.

### [ ] Session 3 — V4-c : créer une carte depuis le popup et l'onglet Mots
1. **DictionaryKit** : `GlossaryText.items(json) -> [String]` (un sens par élément). Nouveau `CardFields.swift` avec `CardFields.make(term:sentence:source:) -> [String: String]` :
   - `Mot` = expression, `Lecture` = lecture ;
   - `Furigana` = segments de `JapaneseText.distributeFurigana` au format Anki : `texte[lecture]`, une espace avant chaque segment qui a une lecture ;
   - `Sens` = `<ol><li>…</li></ol>` (premières définitions, texte simple, HTML échappé) ;
   - `Accent` = `[n]` (accents uniques) ; `Fréquence` = 1re valeur + nom du dictionnaire ;
   - `Phrase` = phrase avec le mot entouré de `<b>` ; `Source` = « Titre · p. N ».
   - DictionaryKit ne dépend **pas** de ReviewKit. Ajouter des tests.
2. **App** : nouveau `App/Review/ReviewModel.swift` (`@MainActor ObservableObject`).
   - Store dans `Application Support/Kyokasho/Review`. Réglages enregistrés avec `appDatabase.setStoredValue(_, forKey: "review.settings")`.
   - Publie `counts`, `decks`, `templates`.
   - `addCard(term:sentence:imageData:audio:documentId:page:) -> AddResult (.added / .duplicate)`.
   - Ajouter `let review: ReviewModel` dans `AppModel`, à côté de `dictionary`. L'injecter partout où il y a `.environmentObject(model.dictionary)` : `grep -rn 'model.dictionary)' App`.
   - project.yml : ajouter le produit `ReviewKit` à côté de `DictionaryKit`.
3. **Contexte de la page**. Dans `ReaderController.present(text:rects:anchor:)`, garder `lookupContext` : la phrase (texte de la ligne OCR, ou pour un PDF texte `page.selectionForLine(at:)?.string`) et le rectangle de la ligne dans la page.
   - **Image** : dessiner la zone avec `PDFPage.draw` dans un `UIGraphicsImageRenderer` (ligne agrandie de 40 % en hauteur, 1200 px de large au plus), JPEG qualité 0,7, puis `store.addMedia` et `<img src="nom">`.
   - **Audio** : sortir de `DictionaryModel.playAudio` une fonction `audioData(term:reading:) async -> (Data, ext)?`. Champ `Audio` = `[sound:nom.mp3]`. Image et audio selon `ReviewSettings.includeImage/includeAudio`.
4. **Branchement de l'interface** :
   - dans `ReaderScreen`, `LookupPopup(session:onAddCard:close:)` reçoit `onAddCard` → `review.addCard(...)` ; le renderer affiche déjà ＋ puis ✓ ;
   - si doublon : petit message « Déjà dans tes cartes » ;
   - onglet Mots (`App/Study/StudyPanel.swift`, `StudyVocabTab`) : bouton ＋ par ligne, et ✓ si `store.existingKeys` contient le mot ;
   - option : envoi AnkiMobile si `settings.sendToAnkiMobile`.
5. L'app compile. Commit.

### [ ] Session 4 — V4-d : écrans de révision → release 0.5.0
1. **`App/Review/CardWebView.swift`** : copie de `LookupWebView`, avec un gestionnaire de schéma `kyocard` qui sert `store.mediaRoot`.
   - HTML = `<style>css</style><div class="card">recto ou verso</div>`.
   - `src="x"` → `kyocard:///x`. `[sound:x]` → bouton ▶︎ qui envoie un message, et l'app lit le fichier avec `AVAudioPlayer`.
2. **`ReviewScreen`** : ouvert en plein écran depuis la barre latérale de la bibliothèque, ligne « Révisions » avec le nombre de cartes dues (`App/Library/LibraryView.swift`, `actionRow`).
   - Paysage : carte au centre, colonne de droite avec 4 boutons (couleurs Atelier) et l'intervalle sous chacun (`ReviewScheduler.preview` + `intervalLabel`).
   - « Montrer la réponse » (toucher la carte). Bouton annuler (`store.undo`). Durée mesurée.
   - Fin de séance : bilan. Cas `.later(date)` : « Reviens à HH:mm ».
3. **`CardBrowserView`** : recherche, filtre par paquet, édition des champs (un `TextEditor` par champ), suspendre, supprimer (avec confirmation), en-tête de stats (`store.stats`).
4. **Réglages → Révisions** (`SettingsView`) :
   - nouvelles cartes / jour, révisions max, rétention (curseur 0,80–0,97), heure de début de journée ;
   - paquet par défaut + nouveau paquet ;
   - éditeur de modèle : recto / verso / CSS + aperçu en direct + `validationError` ;
   - image / audio ; AnkiMobile (oui/non, noms du paquet et du type) ;
   - export CSV / `.apkg` : fichier temporaire + `ShareLink`, ou `.fileExporter` ;
   - « Nettoyer les médias » (`removeUnusedMedia`).
5. Crédits « À propos » : swift-fsrs, genanki (format). Compiler.
6. **Release 0.5.0** (méthode du § 6). Notes : vérifié = tests unitaires ; non vérifié = tout l'écran, l'import réel dans Anki, AnkiMobile.

### [ ] Session 5 — V5-a : moteur NDLOCR-Lite, partie 1
1. **Vérifier d'abord** (lecture seule, peu de tokens) le dépôt `ndl-lab/ndlocr-lite` sur GitHub :
   - licence du code et des modèles ;
   - fichiers ONNX (détection de la mise en page + reconnaissance des lignes), tailles d'entrée, normalisation ;
   - fichier de caractères ; type de décodage (CTC ou attention) ;
   - URL de téléchargement des modèles.
   Écrire le résumé dans `docs/OCR.md`. Si la licence bloque, **demander** à l'utilisateur.
2. **ONNX Runtime** : paquet SwiftPM `https://github.com/microsoft/onnxruntime-swift-package-manager`, produit `onnxruntime`.
   - Vérifier qu'il marche sur iOS 16 et ce qu'il ajoute à la taille de l'app.
   - L'ajouter à `OCRKit`, ou mieux à une cible à part `NDLOCRKit` pour ne pas alourdir les tests.
3. **`ModelStore`** :
   - téléchargement **à la demande** (taille affichée avant, progression, reprise si coupé) ;
   - rangement dans `Application Support/Kyokasho/Models/<nom>` ; bouton supprimer ;
   - jamais dans l'IPA ;
   - empreinte SHA-256 vérifiée si le dépôt en donne une.
4. **Prétraitement en Swift** : redimensionner, garder les proportions, remplir les bords, normaliser, passer en tableau CHW Float32. Tests sur une image générée.
5. Commit.

### [ ] Session 6 — V5-b : moteur NDLOCR-Lite, partie 2
1. **`NDLOCREngine`** suit le même protocole que `VisionOCREngine` (`Packages/KyokashoKit/Sources/OCRKit/OCREngines.swift`) :
   - détection → boîtes des lignes (souvent verticales) → découpe → reconnaissance → décodage → `OCRLine` ;
   - `NormBox` + boîtes par caractère réparties en proportion, comme le repli déjà en place pour Vision.
   - Ordre de lecture du japonais vertical : colonnes de droite à gauche, de haut en bas.
2. **Choix du moteur** :
   - `OCREngineChoice` (`ReaderCore/ReaderSettings.swift`) gagne `.ndlocr` ; monter `OCRPage.version` pour vider l'ancien cache ;
   - **Auto** : si Vision voit surtout des lignes verticales (hauteur > largeur) et que les modèles sont installés → NDLOCR, sinon Vision ;
   - réglage dans `OCRSettingsView`.
3. **Banc d'essai** (`App/Settings/BenchView.swift`) : ajouter le moteur, comparer le taux d'erreur et le temps.
4. Option PP-OCRv5 mobile (Apache-2.0) : **seulement s'il reste du temps**, sinon la noter dans les idées.
5. L'app compile. Commit.

### [ ] Session 7 — release 0.6.0 + vrais tests
1. Release 0.6.0 (§ 6).
2. **Demander** à l'utilisateur la permission de tester (simulateur et/ou iPad), en expliquant pourquoi.
   Priorité : **mode paysage** (jamais vérifié), popup 辞, onglet Mots, révisions, import d'un vrai dictionnaire (Jitendex), OCR NDLOCR sur un manuel vertical.
3. Noter les bugs et en corriger 2 ou 3 au plus. Le reste va dans une liste « à faire » en bas de ce fichier.

## 5. Carte du code (où est quoi)

- **`project.yml`** (XcodeGen) : version `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` ; produits du paquet utilisés par l'app.
- **`Packages/KyokashoKit/`** :
  - `ReaderCore` : modèles, `AppDatabase` (GRDB, migrations, `storedValue` / `setStoredValue`), réglages ;
  - `OCRKit` : `PageRenderer`, `VisionOCREngine`, `PDFTextEngine`, acteur `OCRService` (cache), taux d'erreur ;
  - `YomitanKit` (**GPL**) : `JapaneseText` (kana, furigana, mores, accent), `LanguageTransformer` (déconjugaison, `japanese-transforms.json`) ;
  - `DictionaryKit` : `DictionaryDatabase`, `DictionaryImporter`, `Translator` (`findTerms`, `findKanji`, `segment`), `GlossaryRenderer` (HTML + pont JS), `GlossaryText`, `DictionaryProfile` ;
  - `ReviewKit` : cartes, voir § 4.
- **`App/`** :
  - `KyokashoApp.swift` (racine, injections) ; `AppModel.swift` (`dictionary`, `ocr`…) ;
  - `Design/Atelier.swift` : couleurs, `AtelierPanel`, `ToolButton`, `CapsuleButton`, `PillTabs`, `PressScale`, `GridBackground` ;
  - `Library/LibraryView.swift` (barre latérale) ;
  - `Reader/` : `ReaderScreen` (barre d'outils, bouton 辞, popup, surlignage), `ReaderController` (recherche au toucher, OCR), `InkOverlay`, `ReaderSheets`, `TextPageSheet` ;
  - `Study/StudyPanel.swift` (onglets Texte / Mots / Notes / Repères), `Study/DeepL.swift` ;
  - `Dictionary/` : `DictionaryModel`, `LookupWebView`, `LookupPopup` (`LookupSession`), `DictionaryViews` ;
  - `Drive/`, `Settings/` : `SettingsView`, `AboutView`, `OCRSettingsView`, `BenchView`.
- **Racine du dépôt** : `build_ipa.sh` → `dist/Kyokasho-<version>.tipa` (le dossier `dist` est ignoré par git). `docs/releases/vX.Y.Z.md`. `THIRD_PARTY_NOTICES.md`. `PLAN.md` (plan d'origine validé).

## 6. Faire une release

1. Monter la version dans `project.yml` : `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` +1.
2. Écrire `docs/releases/vX.Y.Z.md` (même format que `v0.4.0.md` : Installation, Modifications, Vérifié / non vérifié).
3. Ajouter une ligne en haut du tableau « Versions » du README.
4. `./build_ipa.sh 2>&1 | grep -E '==>|OK|error'`
5. Commit, tag et publication :
   ```
   git add -A && git commit -m "Version X.Y.Z …" && git tag vX.Y.Z && git push origin HEAD --tags
   gh release create vX.Y.Z dist/Kyokasho-X.Y.Z.tipa --title "Kyōkasho X.Y.Z — …" --notes-file docs/releases/vX.Y.Z.md
   ```

## 7. Pièges déjà rencontrés

- Types qui portent le même nom que ceux du SDK : `Document` → `LibraryDocument`. Dans ReviewKit, éviter `Card`, `ReviewLog` et `Rating`, déjà pris par FSRS.
- GRDB : dans une fonction `async`, les surcharges async de `write` gênent → garder l'import et l'écriture en synchrone dans une `Task.detached`. Pour récupérer l'id, utiliser `inserted(db)` / `didInsert`.
- ZIPFoundation : `addEntry` est ambigu → typer la closure `{ (pos: Int64, size: Int) in … }`.
- PDFKit :
  - pas de `exchangePage` (plantage) → retirer puis insérer la page ;
  - avec `displaysRTL`, les doubles pages sont rangées à la main ;
  - `autoScales` est cassé par `minScaleFactor` → on ajuste nous-mêmes à la page.
- Les gestes perso bloquaient la sélection de texte → `cancelsTouchesInView = false`.
- Vision : seul le mode `.accurate` lit le japonais. Le cache OCR porte un numéro de version : le monter quand le format change.
- swift-fsrs : le tag 5.0.0 a `FSRS`, `next`, `repeat` en `internal` → on suit un commit de main. Ne pas remettre `from: "5.0.0"`.
- Dates GRDB arrondies à la milliseconde : dans les tests, comparer avec `accuracy`.
- `NSLock.withLock` existe déjà dans Foundation : ne pas le redéfinir.
- Le simulateur sans fenêtre ne pivote pas : le paysage n'a **jamais** été vérifié.

## 8. Idées pour plus tard (pas maintenant)

PP-OCRv5, envoi des médias vers AnkiMobile, synchro des cartes par Drive, statistiques avancées.
