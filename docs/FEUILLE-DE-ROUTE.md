# Feuille de route Kyōkasho — à lire en entier au début de chaque chat

> **Reprise documentaire du 25/10/2026 :** voir [l'index](INDEX.md), [l'audit v1.3](AUDIT-V1.3.md)
> et [le plan de reprise proposé](GOUVERNANCE-ET-REPRISE.md). Les statuts historiques ci-dessous sont conservés ;
> une case cochée n'est pas une preuve de recette iPad. GitHub indique le dépôt comme public à cette date,
> malgré les mentions historiques de dépôt privé. Aucune nouvelle release n'est créée par cette documentation.

> Ce fichier + `docs/IA-LOCALE.md` (avant de toucher à l'IA) suffisent. Ne relis pas le code « pour voir » :
> `grep -rn 'FDR-' App Packages` donne les endroits exacts d'une étape. Une session = les retours de l'utilisateur,
> sinon l'étape suivante non cochée (§ 7 bis, puis § 8) ; puis commit + push (+ release **si demandée**), puis résumé simple.
> **État au 24/10/2026 : v1.3 publiée (build 40).** Toutes les étapes V1 → V14 du § 7 sont faites, ainsi que S
> (lexique), P (portrait / paysage) et E (pages de même taille). Confirmé sur l'iPad : IA locale (OvisOCR2, Qwen3-VL,
> analyse, vérification), gestes au doigt (0.8.9.2). Le reste marqué « non vérifié » peut être faux sur l'appareil.

## 0. Passation (23/10/2026) : le projet passe de Claude Code à ChatGPT Codex

Tout le code jusqu'à la v1.1.0 a été écrit par Claude (Claude Code). **l’utilisateur pilote le projet** ; Claude participe
au cadrage et à la feuille de route ; **ChatGPT Codex contribue au développement, aux corrections et à la revue du code**.
`AGENTS.md` (racine) renvoie ici. Ce qui suit est ce qu'un nouvel assistant doit savoir avant d'écrire une ligne.

**Où sont les choses**
- Code : dépôt **privé** `NOxygen59/kyokasho` (branche `main`, tags `vX.Y.Z`, `.tipa` dans les releases GitHub).
- **Le dépôt local est de nouveau présent** dans `~/Projets-iPad/kyokasho`. Le dépôt `NOxygen59/kyokasho-models`
  n'est pas cloné localement ; `latest.json` peut être mis à jour avec le connecteur GitHub. Les forks MLX sont encore là :
  `~/Projets-iPad/mlx-swift`, `~/Projets-iPad/mlx-swift-lm` (branche `ipad-ios16`, poussés).
- Outils sur le Mac : Xcode (SDK iOS 27.1), `xcodegen`, `gh` (connecté), `trash`. **Pas de système iOS pour le
  simulateur** (0 image installée ; 8-9 Go à télécharger, seulement avec l'accord de l'utilisateur).
- Modèles d'IA pour les tests Mac (OvisOCR2, Qwen3-VL-4B) : n'existent plus que dans d'anciens dossiers temporaires
  (`/private/tmp/claude-501/…/scratchpad/models`), peut-être effacés. Sinon les retélécharger (autorisé pour ces deux-là,
  dire la taille avant). Tests : `Packages/GLMOCRKit/Tests/GLMOCRKitTests/OvisOCR2Tests.swift` (variables
  `KYOKASHO_MODELS`, `KYOKASHO_BENCH_PDF`, `KYOKASHO_TRANSLATE`, `KYOKASHO_CHAT`, `MLX_METAL_LANGUAGE_VERSION=30`).

**Leçons de la dernière session (ne pas refaire)**
- Gestes : un essai « zoom fluide » (modes continus horizontaux de PDFKit + verrou du défilement) a été **jugé
  catastrophique** et annulé. Ce qui marche (confirmé) : PDFKit en **mode annotation permanent**
  (`pdfView.isInMarkupMode = true`, comme le mode Pencil), sélection de texte maison à l'appui long
  (`ReaderController+Navigation.swift`, `handleLongPress`). Ne pas remettre `singleTap.require(toFail: doubleTap)`
  en question sans test sur l'iPad.
- Teinte des pages : un filtre `compositingFilter` posé sur toute la vue a donné un **aplat de couleur** sur l'iPad :
  annulé. Ce qui est en place : teinte peinte page par page (`TonedPage.draw`) + images teintées **préparées pour la
  planche affichée, la précédente et la suivante** (`ToneCache`, `ReaderController.scheduleTone`), « Sombre
  intelligent » (`PageTone.smartDark`, CoreImage).
- Tout changement de gestes / d'affichage sans pouvoir tester : le rendre **désactivable** et le dire.

**À vérifier sur l'iPad (fait à l'aveugle, jamais confirmé)** : teintes préchargées et sombre intelligent (0.9.0),
fenêtre OCR à déplacement libre (0.9.0), pages de même taille + cache `Caches/Equalized` (1.0 / 1.1), Auto / Simple /
Double (1.1), export (V8), ajout de pages (V14, données de l'utilisateur : prudence), stockage et cache (V10, V11),
page par IA et chat (V7), lexique (S).

**Retours traités par Codex le 23/10 (inclus dans la v1.1.1, à confirmer sur iPad)** :
- **Réglages** : accueil en six entrées par usage, recherche (accents, casse et plusieurs mots), descriptions
  courtes, réglages du texte séparés des options OCR avancées ; diagnostic et moniteur regroupés dans l'aide.
  Réglage de la fenêtre OCR et conservation du zoom dans « Lecture et apparence ». Options existantes conservées ;
  « Automatique » ajouté au choix de disposition propre à un livre. Effacement des textes OCR : confirmation
  et mention des corrections manuelles effacées avec eux.
- **Fenêtre OCR / double page** : zone PDF explicitement dimensionnée et contenue dans sa colonne ; taille finale
  sans interpolation pendant un changement de mode. `ReaderPDFContainer` capture le point de lecture et le zoom
  avant de redimensionner la même vue PDF. Le dernier recalage restaure la vue ; une navigation explicite annule
  l'ancien recalage. Les réglages inchangés n'entraînent plus de réajustement ; dessin et changement de disposition
  ne forcent plus systématiquement « page entière ». Une planche déjà ajustée reste ajustée à la place disponible.
  Option désactivable : Réglages → Lecture et apparence → Fenêtre texte OCR → Conserver le zoom et la position.
- **Vérifié** : nouvelles vues de réglages, conteneur et classe PDF vérifiés par le compilateur avec le SDK iOS,
  cible iOS 16 (destinations externes inchangées remplacées par des doublures, pas de compilation complète de l'app).
  Essai autonome PDFKit sur Mac avec PDF synthétique : zoom et point de lecture, tailles successives, disposition
  simple/double, navigation prioritaire et ajustement initial. Catalogue : 14 destinations accessibles et recherche.
  Aperçu des composants des réglages rendu sur Mac. Aucun simulateur ni iPad utilisé ; chevauchement réel à confirmer.

**Retour après v1.1.1 (23/10)** : l'utilisateur confirme que les changements fonctionnent sur son iPad.
Il trouve les changements de fenêtre trop brusques. Correction sur `main`, hors release : panneau ancré animé
sur une couche séparée (sa colonne reste réservée), fenêtre libre/plein écran et pastille animées ; court fondu
de l'ancien rendu PDF pendant le recalage immédiat, sans interpolation de son zoom. Interrupteur « Animer les
changements de fenêtre » dans les réglages de la fenêtre OCR ; respect de « Réduire les animations ». À confirmer
sur iPad pour les transitions. Archive Release de contrôle réussie (SDK iOS, minimum iOS 16),
sans simulateur ni appareil. La v1.1.1 publiée n'est pas modifiée.

**Dictionnaire partagé (après v1.1.1, hors release)** : l'accueil ouvre un espace Dictionnaire avec recherche
par début de mot ou de lecture, fiches Yomitan existantes, kanji, mots/kanji enregistrés, historique persistant
et accès au lexique personnel déjà présent dans l'app.
Le même espace remplace « Mots de la page » dans la fenêtre OCR et dans la barre du lecteur ; les mots restent
consultables directement dans le texte HTML. Les dictionnaires se gèrent depuis cet espace. Aucun dictionnaire
ou modèle tiers ajouté au dépôt. Vérification sur iPad à faire après une future release.

**Activité des IA (après v1.1.1, hors release)** : petites pastilles OvisOCR2, GLM-OCR et Qwen3-VL sur l'accueil
et dans le lecteur, liées aux tâches, à l'analyse des documents et à l'état réel du modèle MLX. Elles affichent
chargement, action en cours, attente ou modèle chargé ; leur opacité baisse quand l'IA ne travaille plus. Le lecteur
les montre même lorsque ses barres sont masquées. Toucher ouvre toujours les tâches et leurs boutons d'arrêt.
Option désactivable dans Réglages → Modèles d'IA et outils. Compilation iOS générique réussie, iPad à confirmer.

**Furigana des nouveaux scans (après v1.1.1, hors release)** : retour utilisateur : les furigana apparaissent
dans la fenêtre OCR mais pas sur la page d'un PDF rescanné ; couper/rallumer l'option de la page n'aide pas.
L'échantillon VueScan de cinq pages fourni le 23 octobre est composé uniquement d'images : aucune couche texte.
L'hypothèse précédente (couche OCR cachée) ne s'applique donc pas à cet échantillon. La capture du lecteur montre
Apple Vision, les lectures dans le panneau et l'option de la page cochée. Une différence vérifiée dans le code
peut expliquer l'écart : sans MeCab, le panneau utilisait le dictionnaire Yomitan, la page l'analyseur système.
Les lectures des scans sont maintenant calculées avec la même méthode que le panneau. Les adaptations aux PDF
avec couche texte cachée restent utiles pour d'autres scans. Le mode diagnostic note les lignes OCR, caractères
Ovis et lectures placées. Compilation iOS générique réussie ; rendu sur iPad à confirmer après une future release.

**Suite proposée** : § 7 bis (R : « Continuer » dans la bibliothèque ; F codé par Codex, à essayer sur iPad), puis § 8 (B3 furigana
verticaux, B5 tableaux / texte vertical, B6 performance, B7 GLM-OCR plus rapide, K grammaire), § 11.

**Chat du livre (24/10, hors release)** : onglet Chat dans la fenêtre OCR, mêmes conversations depuis l'accueil
et le lecteur, plusieurs discussions enregistrées par document. L'ancien chat du livre est repris sans effacer son
fichier. Chaque nouvelle question cherche d'abord avec ses propres termes dans les pages OvisOCR2 ; seul le dernier
échange aide à résoudre une relance explicite. Sélecteur de modèle présent avec Qwen3-VL 4B seul pour l'instant.
Qwen3.5-2B 4 bits est une piste plus légère compatible avec le registre du fork MLX Swift, mais son intégration
et sa qualité sur l'iPad restent à vérifier. Compilation iOS générique réussie ; usage sur iPad non vérifié.

**Lecture et relecture OCR (24/10, incluse dans la v1.2.3)** : consignes du chat recentrées sur la question actuelle et les
passages du livre, sans sujet de design d'intérieur imposé. Furigana de la page accessibles directement près de
« … » ; le panneau Texte affiche les pages majoritairement verticales de droite à gauche avec ruby dans le bon
sens. Depuis Texte, « Corrections IA » ouvre les corrections proposées et « Rescanner » relit vraiment
la page avec OvisOCR2, même si elle était en cache. Une nouvelle lecture invalide le vote de fiabilité de cette
page jusqu'à sa prochaine analyse. Rendu vertical et usage à confirmer sur iPad.

**Retours après v1.2.3 (24/10, inclus dans la v1.2.4)** : une question « p. 6 » cible désormais uniquement la page 6
et indique clairement si sa lecture Ovis manque ; les formules LaTeX d'Ovis sont affichées comme des formules
lisibles dans le panneau, tout en gardant le Markdown original. L'analyse propose d'accepter sur tout le document
les différences déjà lues par Ovis, en sautant les lignes retouchées à la main et les formules ; aucun nouveau scan.
Le panneau OCR ancré occupe sa propre colonne pour éviter le chevauchement lors d'une navigation par la pellicule.
L'orientation des furigana sur les légendes verticales tient compte des boîtes de caractères ; les kanji isolés
empilés sans contexte sont ignorés. Le geste de changement de page au doigt ne doit plus capter le trackpad,
avec une option de retour dans les réglages. À confirmer sur l'iPad, sans simulateur ni appareil utilisé ici.
Compilation iOS générique réussie ; aucun essai de geste sur appareil.

**Version 1.2.2** : Qwen3.5-4B 4 bits ajouté en modèle de chat optionnel (téléchargement à la demande, ≈ 3,06 Go,
poids et tokenizer SHA-256 vérifiés). Changement de modèle et conversations par livre, bouton pour insérer la page
affichée et liens vers les pages consultées. L'accueil ouvre le chat même si seul Qwen3.5 est installé. Pastille
d'activité et place de stockage renseignées. Le moteur compile pour iOS 16 ; chargement et qualité du modèle
sur l'iPad non vérifiés, car ses poids n'ont pas été téléchargés sur le Mac.

## 1. Prompt à coller dans le nouveau chat

```
Projet Kyōkasho (dépôt NOxygen59/kyokasho, dans ~/Projets-iPad/kyokasho — le recloner s'il manque). Lis AGENTS.md,
docs/FEUILLE-DE-ROUTE.md (et docs/IA-LOCALE.md si l'étape touche l'IA) puis `git log -5 --oneline`. Fais mes retours
s'il y en a, sinon l'étape suivante non cochée (§ 7 bis puis § 8). Pas de simulateur, pas d'iPad sans ma permission.
```

## 2. Règles de l'utilisateur (obligatoires)

- **Vocabulaire** : la « **fenêtre OCR** » = le panneau d'étude (`StudyPanel`, Texte / Mots / Notes / Repères).
- **Français, court, simple** (l'utilisateur ne code pas) : dire *ce qui change pour lui* et *pourquoi*.
- **Jamais** demander ni taper un mot de passe, une clé API ou un jeton.
- Suppression de ses fichiers : `trash`, jamais `rm`. **Ne jamais supprimer un dépôt GitHub.**
- Commits en français, message clair (ce qui change et pourquoi). Mention de l'assistant en dernière ligne si l'outil
  l'ajoute (anciens commits : `Co-Authored-By: Claude …`).
- **Pushs autorisés** : l'utilisateur a autorisé le 23/10 l'envoi sur `main` de `NOxygen59/kyokasho`, ainsi que
  les futurs pushs de ce projet. Les releases nécessitent toujours sa demande et son numéro de version.
- **Simulateur interdit** sauf « tu peux tester ». Tests sur l'iPad : c'est l'utilisateur qui les fait (release).
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

- **Mode diagnostic** (Réglages → Aide et informations → Aide au diagnostic → Mode diagnostic, `App/Settings/Diagnostics.swift`) : il active, refait le
  geste ; l’activation ne produit pas forcément de changement visuel dans le lecteur. Consulter « Voir le journal »,
  puis recopier seulement un extrait sans données personnelles pour GitHub. « Partager le journal » envoie le fichier complet
  (aussi dans Fichiers → Kyōkasho → Diagnostics/journal.txt), sans filtrage automatique. Erreurs toujours notées, MLX
  compris (avant l'arrêt). Ajouter `Diagnostics.log / measure / error` sur tout nouveau chemin lourd.
- Rapport `.ips` : `dwarfdump --uuid build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM` doit = `slice_uuid`, puis
  `atos -arch arm64 -o <dSYM>/Contents/Resources/DWARF/Kyokasho -l <base> <adresses>` (base = `usedImages` Kyokasho).
  Attention : `build_ipa.sh` écrase l'archive → symboliser **avant** de reconstruire.

## 4. Économiser les tokens (méthode qui marche)

- Gros fichier : `grep -n` puis `sed -n 'A,Bp'`. `ReaderController` : fichier principal + `ReaderController+<thème>.swift`.
- Modifier : `python3 - <<'EOF' … assert s.count(a)==1 … EOF` (attention aux `"""` collés à un `"` : préférer
  des chaînes `'…'` Python quand le texte Swift contient des guillemets).
- Fichier ajouté dans `App/` → `xcodegen generate -q` avant de compiler.
- Sorties filtrées :
  - tests : `cd Packages/KyokashoKit && swift test 2>&1 | grep -E ': error|error:|with [1-9][0-9]* failure' | head -5`
  - app : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E ' error:|BUILD' | sort -u | head -20`
  - `.tipa` : `./build_ipa.sh 2>&1 | grep -E 'OK|error' | tail -2` → `dist/Kyokasho-<version>.tipa`
- Visuel : rendu d'essai sur Mac (petit script Swift hors dépôt qui écrit un PNG, puis le regarder). Ex. la mise en
  page IA et les fonds des thèmes ont été vérifiés ainsi.
- Gros chantier : **faire relire le diff** (deuxième passe critique, ou un autre agent) avant commit : à chaque fois
  de vrais bugs ont été trouvés (décalage de données, état bloqué, course entre tâches).
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
5. Donner à l'utilisateur le lien de la release et le chemin du `.tipa` (il l'installe avec TrollStore).

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
- Langue de lecture IA par document : Japonais (défaut) ou Automatique, choisie avant l'import depuis Fichiers et
  visible avant l'analyse complète. OvisOCR2 garde chiffres, lettres latines et formules ; la confusion observée
  `图` → `図` est corrigée à la lecture des anciens caches et lors des nouvelles lectures, sans modifier le Markdown
  brut ni les lignes retouchées à la main. Le chemin des lectures IA est centralisé dans `DocumentAITextStore` ; voir
  `docs/ARCHITECTURE-LECTURE.md`. Rendu sur iPad à confirmer après une future release.
- `OCRService` (actor) : cache SQLite par page et moteur (`OCRPage.currentVersion` = 5) ; `resolve` (auto : texte PDF
  sinon NDLOCR → PP-OCRv5 → Vision) ; **post-traitement** `OCRProofreader` (dictionnaire, confusions 未/末…) →
  `OCRLine.doubt` ; `store` (corrections).
- NDLOCR + passe PP-OCRv5 pour mesurer les caractères (`CharacterAlignment`).
- Relecture IA des lignes douteuses : `ReaderController.rereadDoubtful` (GLM-OCR), option `ocr.aiReread`.
- Correction à la main : appui long sur une ligne en mode Brut → `correctOCRLine` (`edited` = jamais retouchée).

**Panneau d'étude** (`App/Study/StudyPanel.swift`) — onglets Texte / Dico / Notes / Repères
- Texte : recherche (kanji / kana / romaji, `PageTextSearch`), moteur OCR en icône, « Mis en forme » (`OCRLayout`,
  géométrie ou PP-DocLayout / DocLayout-YOLO), « Brut » (doutes soulignés), **✨ Mise en page IA** (`AILayoutView` :
  Markdown d'OvisOCR2 → `AILayout.blocks` → HTML du thème, furigana, dictionnaire, figures découpées en vignettes ;
  **日本語 / Français** avec traduction Qwen3-VL hors ligne), ふりがな (`FuriganaTextView`, WKWebView `<ruby>`),
  traduction DeepL.
- Vérifier la double page (OvisOCR2) : menu du moteur → `VerifySheet`.

**Japonais**
- Dictionnaires Yomitan (`DictionaryKit`, `YomitanKit`), espace partagé `DictionarySearchView` et popup
  `LookupPopup` (+ traduction FR des définitions
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
la langue ciblée du scan est aussi accessible dans « Ce document ». La lecture automatique OvisOCR2 est dans
« Texte des pages » ; les fiches de modèles renvoient vers le réglage de leur usage. « Effacer le cache OCR »
annonce clairement que les lectures OvisOCR2 restent enregistrées ; le compteur compte les résultats par moteur.
L'import Drive propose la langue avant une nouvelle importation, lance le même scan de fond que Fichiers et garde
la langue du livre lors d'une mise à jour.
Vider le cache OCR remet aussi les votes de fiabilité à refaire, car ils dépendaient de ces résultats ; l'option
est indisponible pendant une analyse en cours.
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
  ne republie ni `ocrPage`, ni `focusSource`, ni `pageHasPDFText`. Retour 0.8.7 (double page, p. 2 choisie → regarder
  la p. 1 la remettait sur 1) : `pinnedFocus` (pilule) gardé tant que visible ; en double page `visibleSources` et la
  page courante comptent la planche entière (`spread(of:)`), même zoomée sur une page. Position de défilement par page : pas faite
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

### [x] V6 — Thèmes (fonds personnalisés, innover)
- **Retouche Codex (23/10, demande de l'utilisateur)** : les 11 thèmes existants conservent leurs noms et
  identifiants. Palettes plus douces, surfaces mieux séparées, textes secondaires et accents éclaircis ; traits,
  fibres de papier, plan d'intérieur et pétales affinés. Sélecteur avec motifs visibles, exemple de panneau et
  description de chaque ambiance ; interrupteur « Motifs de fond » persistant. Couleurs partagées reprises par
  le dictionnaire et les cartes via les palettes existantes. Aucune image ni dépendance ajoutée.
  Vérifié sur Mac : compilation des trois fichiers de design dans un rendu SwiftUI autonome (seul le pont
  couleur UIKit est adapté à AppKit), planche des 11 palettes/fonds, contrôle des contrastes sur `surfaceHigh`
  (accents ≥ 5,08:1 ; texte tertiaire composé ≥ 4,52:1). Compilation complète de l'app et essai iPad non faits.
- **Fait (22/10, non vérifié sur iPad)** : `App/Design/ThemeBackdrop.swift` (fonds tracés en `Canvas`, hasard fixé
  `Seeded`) ; 6 thèmes : Washi, Architecte (plan bleu, cotes), Intérieur (plan d'appartement), Lumière du soir,
  Encre et or, Sakura (`Theme.backdrop`). `GridBackground` = fond du thème. Cartes du choix de thème = vrai fond.
  B4 fait : `GlossaryRenderer.palette` (← `Theme.cssPalette`) et `CardHTML.page` aux couleurs du thème.
  Image d'essai Mac des 7 fonds : OK.
- `App/Design/Themes.swift` (`Theme`, `ThemeManager`, `ThemePickerView`) + `Atelier.swift` (couleurs).
- Idées : fonds dessinés en SwiftUI (pas d'image tierce) : papier washi (bruit), grille d'architecte (lignes fines,
  thème du manuel), plan d'intérieur discret, dégradé « lumière du soir », mode encre (noir et or), sakura discret ;
  aperçu en direct ; le thème colore aussi le HTML (panneau, dictionnaire, cartes : voir backlog B4).
- Balises `FDR-V6`.

### [x] V3 — Furigana refaits sur le texte de l'IA, document scanné à l'import
- **Fait (22/10, non vérifié sur iPad ni par image d'essai)** : (a) `App/Library/DocumentScan.swift` : à l'import
  (`AppModel.importFiles`) et à l'ouverture (`ReaderController.observe`), tâche `scan|<id>` (`AITaskCenter`) qui lit
  par OvisOCR2 les pages sans `ovisocr2-<page>.md` ; une lecture de document à la fois ; cède la place à l'analyse ;
  pastille : barre % + « Voir le détail » (`Job.log`). (b) `OCRReferenceDiff.alignedLines` / `match` (testés) :
  texte IA posé sur les boîtes OCR ; `FuriganaLayer.marks(from:reference:frame:)` ; `.aiPageRead` → furigana refaits
  (`furiganaGeneration` : dernier calcul seul gardé). Limite : relecture GLM pendant le scan = va-et-vient de modèle.
- (a) **Scan obligatoire** : à l'import d'un PDF (`AppModel.importFiles`) et à l'ouverture d'un document, lancer
  (via V4) la lecture IA (OvisOCR2) des pages **pas encore lues** seulement ; petite fenêtre avec barre de
  pourcentage + « Voir le détail » (journal en direct : page, durée, erreurs — réutiliser `Diagnostics.measure`).
- (b) **Furigana d'après le texte de l'IA** : texte = Markdown d'OvisOCR2 (fiable) ; positions = boîtes de
  caractères de l'OCR habituel (NDLOCR/PP). Aligner les deux (`OCRReferenceDiff.align` donne déjà la lecture IA de
  chaque ligne OCR ; puis `CharacterAlignment` pour caractère ↔ boîte) → lectures MeCab sur le texte IA, posées
  sur les boîtes OCR alignées. Centrer chaque lecture sur le **groupe de kanji** (pas sur le mot entier),
  `FuriganaLayer.marks(from:frame:)` + `layout`. Vérifier par une image d'essai Mac sur le manuel.
- Balises `FDR-V3`.

### [x] V5 — Revérifier les « caractères douteux » à chaque nouvel OCR de la page
- **Fait (22/10, non vérifié sur iPad)** : `runOCR` → `proofread = false` + `refineOCR()` (dictionnaire relancé
  même en cache) ; `refineOCR` ajoute `OCRReferenceDiff.markDifferences` (caractères ≠ OvisOCR2 = douteux, testé) ;
  `.aiPageRead` (scan, vérification, mise en page IA) → `recheckDoubtsAfterAIRead`.
- `runOCR(force:)` / « Relancer » / nouvelle lecture IA → relancer `OCRProofreader` et rafraîchir `doubtRow`
  (aujourd'hui seulement à la 1re lecture : `postProcess` sur calcul neuf, `refineOCR` si `proofread != true`).
- Balises `FDR-V5`.

### [x] V8 — Exporter un document depuis la bibliothèque (plusieurs formats, style GoodNotes)
- **Fait (22/10, non vérifié sur iPad)** : `App/Library/DocumentExport.swift` (appui long → « Exporter… ») : PDF
  d'origine, PDF annoté (surlignages, encre, pastilles des notes ancrées + pages « Notes »), Markdown (mise en page
  IA sinon OCR, traduction, surlignages, notes), PNG ≈ 200 ppp en zip (`NSFileCoordinator .forUploading`), `.apkg` des
  cartes du document ; pages au choix ; dossier `tmp/Export/<uuid>` par export, annulé à la fermeture.
- Aussi (retours 0.8.8) : fenêtre OCR, texte IA déplaçable (`RubyWebView` : défilement réactivé, verrou de direction) ;
  vérification Ovis = réutilise la lecture déjà faite (scan) au lieu de relire.
- Menu d'appui long `LibraryView.menu(for:)` → « Exporter… » : PDF d'origine ; **PDF annoté** (surlignages, dessins
  `InkOverlay`, notes / ancres aplaties : rendre chaque page dans un `UIGraphicsPDFRenderer`) ; **texte / Markdown**
  (OCR, mise en page IA, traduction FR si présente, notes) ; **images PNG** par page (zip) ; cartes `.apkg` (existe).
  Choix des pages ; `ShareLink` / `UIDocumentPickerViewController(forExporting:)`.
- Balises `FDR-V8`.

### [x] V10 — Réglages : graphique de la place prise par l'app
- **Fait (22/10, non vérifié sur iPad)** : `App/Settings/StorageUsage.swift` (Réglages → Stockage → « Place prise par
  l'app ») : documents, un élément par gros modèle (≥ 200 Mo, les petits ensemble), UniDic, dictionnaires, analyses,
  base, caches, temporaires, autres ; barre empilée Swift Charts + légende (taille, %) ; place libre de l'iPad ;
  tirer pour recalculer. Balise `FDR-V11` posée dans `StorageUsageView`.
- Tailles : Documents (PDF), modèles (`ModelStore.root` par modèle + `unidic`), analyses (`Analysis`), base SQLite
  (OCR, notes, cartes), caches (`Caches/*`, vignettes, nettoyage), temporaires. Barre empilée Swift Charts + légende,
  calcul hors du fil principal (`FileManager.enumerator` + `totalFileAllocatedSize`). Balises `FDR-V10`.

### [x] V11 — Effacer le cache (sans rien perdre d'important)
- **Fait (22/10, non vérifié sur iPad)** : bouton dans `StorageUsageView` (confirmation, place libérée affichée).
  `StorageUsage.clearCaches` vide le **contenu** de `Caches/*` et `tmp` (dossiers gardés : `ThumbnailCache` ne les
  recrée pas ; rien de modifié depuis < 5 min), + caches mémoire (vignettes, pages nettoyées, furigana, mise en page,
  `PDFPool`, ONNX, MLX inactif) + cache web seulement (cookies du navigateur gardés).
- Effacer seulement : `Caches/` (vignettes régénérables, `Sharpened`, `Update`), `tmp`, données WebKit, cache
  `LayoutRegionsCache`, `MLX.GPU.clearCache()`. **Garder** : PDF, base (notes, OCR, cartes), `Analysis`, modèles,
  UniDic, réglages. Confirmation + taille libérée affichée. Balises `FDR-V11`.

### [x] V14 — Ajouter un PDF à un document existant (suite du manuel), avec ordre
- **Fait (22/10, non vérifié sur iPad)** : `App/Library/AddPagesView.swift` (appui long → « Ajouter des pages… »,
  liste réordonnable, ajout à la fin d'office) + `App/Library/PageShift.swift` : base (`AppDatabase.shiftPages`,
  transaction, testé) → PDF (`replaceItemAt`) → rapport (`shiftReport`) → fichiers IA (dossier de passage
  `<id>.shift`) → cartes (`ReviewStore.shiftSourcePages`, base `review.sqlite` à part, testé). Étapes dans
  `page-shift.json` ; `PageShift.reconcile` au lancement (`AppModel.init`) annule ou termine. Refusé si une lecture
  IA du document tourne. Limite : arrêt pile pendant l'écriture du rapport → rapport non décalé (jamais deux fois).
- Menu du document → « Ajouter des pages… » : liste réordonnable [document actuel] + nouveaux PDF (réutiliser
  `PDFMergeView`). Fusion dans un nouveau fichier puis **remplacement** du PDF du document (même id).
- **Délicat** : tout ce qui est rangé par numéro de page doit être renuméroté si des pages sont insérées **avant** :
  tables `ocrResult`, `highlight`, `inkDrawing`, `bookmark`, `pageComment`, `pageTransform` (colonne `pageIndex`),
  fichiers `Analysis/<id>/<lecteur>-<page>.md` et `fr-<page>.md`, rapport JSON, caches `Sharpened`. Faire une table
  de correspondance ancienne → nouvelle page, appliquer en une transaction GRDB, puis `document.pageCount`.
  Ajout **à la fin** = aucun renumérotage (cas le plus courant : proposer d'office).
- Balises `FDR-V14`.

### [x] V7 — Réglages : une page par IA locale (+ chat pour celles qui discutent)
- **Fait (22/10, non vérifié sur iPad)** : `App/Settings/AIModelViews.swift` (Réglages → Modèles → « Chaque IA ») :
  `AIModelDetailView` (description, place, état chargé / en cours, mémoire GPU, dernier usage, « Décharger »,
  réglages : lecture auto d'Ovis `scan.auto`, relecture GLM, Qwen dans l'analyse ; dernières tâches =
  `Diagnostics.recent`, gardé en mémoire même sans mode diagnostic). `QwenChatView` + `GLMOCRKit/QwenChat.swift`
  (`ChatSession` avec historique `Chats/qwen.json`, modèle tenu tant que l'écran est ouvert puis déchargé).
  Qwen 4B inventait les lectures (天井 « あまね ») → `QwenChat.hints` ajoute lectures (MeCab) + glossaire du
  manuel à chaque question : réponses justes (test Mac `testQwenChatAnswers`). Pas fait : longueur / résolution.
- Une page par modèle (OvisOCR2, GLM-OCR, Qwen3-VL-4B, MeCab, NDLOCR…) : description, taille, état chargé / non,
  mémoire, dernier usage, bouton « Décharger », réglages propres (longueur de lecture, résolution, option
  « ajouter à l'analyse ») et **journal** des dernières tâches (via `Diagnostics`).
- **Chat** pour Qwen3-VL-4B (seul vrai modèle de conversation ; OvisOCR2 / GLM-OCR = OCR seulement) : `ChatSession`
  de mlx-swift-lm ou `UserInput(chat:)` avec historique, réponses en flux, historique gardé (JSON par session),
  modèle chargé à l'ouverture, **déchargé en quittant** l'écran (V12). Uniquement dans les Réglages.
- Balises `FDR-V7`.

### [x] V9 — Désencombrer le code (en dernier)
- **Fait (22/10)** : code mort retiré (366 + 30 lignes : `TextPageSheet`, `BookmarksSheet`, `OutlineList`,
  `CommentsSheet`, `reloadNotes`, `renderCurrentPage`, `hasCard`, `renameDeck`, `deleteDeck`, `cardCount`,
  `setPostProcess`, `colorScheme`, `isIdentity`) ; `TextPageSheet.swift` → `OCRTextViews.swift` (`OCRTextView`,
  `CompareEnginesView` gardés). `ReaderController.swift` (2 216 l.) découpé : fichier principal (état, chargement,
  dictionnaire, notifications, ≈ 850 l.) + `ReaderController+Display / Navigation / OCR / Verification /
  Annotations / PageLayout / Search.swift`, code déplacé tel quel (contrôle ligne à ligne) ; variables des
  extensions remontées dans « État des extensions » ; `private` retirés (un fichier ne voit pas le `private` d'un
  autre). Gardé : `AppSettings.theme` (enregistré), `BenchView` (utilisé). **Pas fait** : profilage au moniteur
  (rendus SwiftUI, `@Published` trop larges) — il faut l'iPad.
- Méthode pour retrouver du code mort : script `grep` des noms déclarés qui n'apparaissent qu'une fois (en excluant
  les méthodes appelées par iOS : délégués, `body`, `makeUIView`…).
- Chercher les types / fichiers inutilisés (`grep` du nom de chaque `struct` / `func` hors de son fichier), ex. à
  vérifier : `BenchView` (banc d'essai OCR), `TextPageSheet`, anciennes options (`LayoutEngineMenu`…), copies
  devenues inutiles. Découper `ReaderController.swift` (2100 l.) en extensions par thème (OCR, notes, IA, gestes,
  dictionnaire) **sans changer le comportement**. Profiler (moniteur) : rendus SwiftUI en trop, `@Published` trop
  larges. Toujours une relecture du diff après. Balises `FDR-V9` (fichiers à regarder).

## 7 bis. Idées pour la v1.0 (22/10, à faire dans cet ordre conseillé)

- [x] **P — Portrait = une page** (1.0.0, `ReaderController.adaptLayout`, sans option : comportement par défaut) : en portrait, le lecteur passe tout seul en page simple ; en revenant en paysage,
  il reprend la disposition choisie (double page). Ne pas toucher au réglage enregistré : disposition **affichée**
  = réglage sauf portrait (taille de la vue dans `ReaderScreen` / `ReaderPDFView.layoutSubviews`, puis
  `applyDisplaySettings`), garder la page courante. Option dans Affichage pour couper.
- [x] **E — Double page de même taille** (1.0.0 : pages recréées à la hauteur commune à la construction ; annotations
  d'avant sur une page agrandie = décalées ; export annoté de ces pages pas adapté). **Rectification documentaire QA-02 (25/10/2026)** : l’égalisation est automatique, aucun interrupteur n’existe. L’intention historique était d’agrandir seulement l’**affichage** de la plus
  petite (jamais ses coordonnées : notes, encre, surlignages, OCR sont en repère de page). À tester sur l'iPad.
- [x] **F — Cartes de la page** (Codex, 23/10, non vérifié sur iPad) : menu « Cette page » → aperçu
  des termes du lexique trouvés ; lecture et sens modifiables et obligatoires avant ajout. Texte OvisOCR2 déjà
  gardé, sinon OCR en cache ou lecture OCR. Page de travail figée à l'ouverture (double page). Ajout atomique
  hors du fil principal, doublons ignorés, lien livre/page conservé, export Anki existant. Lectures manquantes : suggestion
  locale MeCab / analyseur système à vérifier ; champ vide si la lecture reste incomplète.
  Vérifié : syntaxe Swift et diff ; compilation complète et essai iPad non faits.
- [ ] **R — Reprendre** : bandeau « Continuer : <livre>, p. X » en haut de la bibliothèque + progression (pages lues,
  pages lues par l'IA).

## 8. Backlog (plus ancien, après le § 7)

- [x] **S — Lexique du domaine** (fait 22/10, non vérifié sur iPad : `App/Dictionary/DomainLexicon.swift`, `lexique.json`,
  Réglages → Japonais ; `OCRProofreader.addingTerms` testé ; relecture, analyse, traductions, chat ; pages déjà
  relues : prises en compte à la prochaine lecture) (design d'intérieur) modifiable : mots connus pour `OCRProofreader` /
  `DocumentAnalysisService.preferred` **et** glossaire de traduction (aujourd'hui `Qwen3VLReader.defaultGlossary`,
  ≈ 50 termes). Balises `FDR-S`.
- [ ] **N — Furigana « vérifiés »** : MeCab et dictionnaire d'accord, sinon doute signalé (à fondre dans V3).
- [ ] **K — Grammaire** : conception `docs/GRAMMAIRE.md` ; coder seulement après accord.
- [ ] **B1 — Gestes / zoom** — en cours (0.8.9.1, pas testé : simulateur sans système iOS, 8-9 Go à télécharger si
  l'utilisateur accepte). Retour du 22/10 : pincement qui saute, toucher lent, zoomé on bouge mal ; voulu = liseuse,
  double page. Fait : toucher sans `require(toFail: doubleTap)` (barres différées `barsToggleWork`, 2e toucher ignoré
  `lastTapAt`) ; [0.8.9.1 jugée « catastrophique » → annulée (f5de73c). 0.8.9.2 : `isInMarkupMode = true` en
  permanence (le mode Pencil était parfait au doigt), sélection au doigt maison (`handleLongPress`), teinte =
  `ToneOverlay` (compositingFilter) au lieu du dessin par page.] Ancien essai : « Zoom fluide » (`ReaderController.fluidZoom`, menu Affichage) = modes continus horizontaux de PDFKit,
  `panGestureRecognizer` du défilement interne coupé à la taille de la page, tour par planche (`turnTarget`),
  recalage `snapToSpread`. Journal « gestes » : classe du défilement trouvé. Ancien texte : (retour du 21/10, cause pas trouvée) : demander lesquels. Pistes (`configureGestures`,
  `applyDisplaySettings`) : modes non continus, `singleTap.require(toFail: doubleTap)`, survol, glisser, `fitToPage`
  à chaque changement de taille. Balises `FDR-1`.
- [ ] **B3 — Furigana vertical**, furigana imprimés à sauter, texte vertical du panneau (`writing-mode`). `FDR-3`.
- [x] **B4 — Thème dans le dictionnaire et les cartes** (fait avec V6) (`GlossaryRenderer`, `CardHTML` : palette non enregistrée).
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
- Le paysage n'a jamais été vérifié par l'assistant (pas de simulateur) : seulement par l'utilisateur sur l'iPad.

## 11. Idées / plus tard

PP-OCRv6, médias vers AnkiMobile, synchro des cartes par Drive, statistiques, redressement des photos de pages,
super-résolution des scans flous.
