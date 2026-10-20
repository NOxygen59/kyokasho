# PLAN — Kyōkasho (nom provisoire)

Lecteur personnel de cours et de manuels PDF pour iPad, avec annotations, OCR japonais,
dictionnaire au toucher façon Yomitan et cartes de révision. **Jamais distribué.**

> **En clair :** une app iPad écrite en Swift. Le cœur (base de données, import, OCR,
> dictionnaire, révisions) est rangé dans des « modules » séparés et testés automatiquement sur
> le Mac. L'interface utilise le lecteur PDF d'Apple (PDFKit) autant que possible et n'ajoute du
> code maison que pour ce qu'il ne sait pas faire. On avance version par version (V1 → V5) ;
> chaque version doit compiler, tourner dans le simulateur et passer ses tests avant la suivante.

---

## 0. Décisions déjà prises

| Sujet | Choix |
|---|---|
| Bundle ID | `fr.noxygen59.kyokasho` |
| Dossier | `~/Projets-iPad/kyokasho` |
| Dépôt | GitHub **privé** `NOxygen59/kyokasho` (archive) ; `*.pdf` et toute donnée tierce exclus |
| Cible | iPad Pro 12,9" M1, iOS 16.6.1 ; *deployment target* iOS 16.0 |
| Outils Mac | macOS 27.0.1, Xcode 27.1, Swift 6.4 (vérifié : compile bien pour iOS 16.0) |
| Simulateur | **iOS 27 uniquement** (pas de runtime iOS 16 installé, choix validé). Le compilateur bloque les API trop récentes, mais les différences de comportement iOS 16 ne se verront que sur l'iPad |
| Installation | TrollStore (déjà sur l'iPad) via `build_ipa.sh` |

## 1. Vérifications faites avant le plan

| Point | Résultat |
|---|---|
| `PDFPageOverlayViewProvider` (surcouche par page) | Disponible depuis **iOS 16.0** ✅ (`PDFView.pageOverlayViewProvider`, `isInMarkupMode`) |
| GRDB.swift | MIT ✅ |
| swift-fsrs | MIT ✅, Swift 5.10, iOS 16 minimum ✅ |
| onnxruntime-swift-package-manager | MIT ✅, iOS **15** minimum ✅ (compatible iOS 16.0) |
| genanki | MIT ✅ (format .apkg) |
| fsrs-rs | BSD-3-Clause ✅ (référence) |
| Aidoku, Yomitan, Hoshi Reader (Android), chimahon, hoshidicts | GPL-3.0 ✅ (portage autorisé → module GPL séparé) |
| NDLOCR-Lite | CC BY 4.0 ✅ (cité par toi en V5) |
| jiten | AGPL-3.0 ✅ **autorisé par toi** (portage possible, module GPL séparé ; AGPL compatible avec GPLv3) |

Avant chaque portage, je relirai le fichier LICENSE **et les en-têtes des fichiers** du dépôt
source (certains disent « GPL-3.0-or-later » : l'en-tête SPDX recopiera la licence réelle).

## 2. Architecture

```
kyokasho/
├─ project.yml                 # description du projet Xcode (XcodeGen), le .xcodeproj est généré
├─ App/                        # cible app : point d'entrée, assemblage des écrans
├─ Packages/
│  ├─ ReaderCore/   (MIT)      # modèles, base GRDB, import + hash, réglages, signets,
│  │                           # commentaires, export Markdown — logique pure, testable sur Mac
│  ├─ ReaderUI/     (MIT)      # écrans SwiftUI, ponts PDFKit / PencilKit / WebKit
│  ├─ OCRKit/       (MIT)      # protocole OCREngine, moteur Vision, cache, banc d'essai (V2)
│  ├─ ReviewKit/    (MIT)      # cartes, templates, FSRS, export CSV / .apkg (V4)
│  ├─ YomitanKit/   (GPL/AGPL) # code porté de Yomitan / jiten / hoshidicts : import de dictionnaires,
│  │                           # déconjugaison, recherche, rendu des définitions (V3)
│  └─ NDLOCRKit/    (CC BY 4.0 + MIT) # pré/post-traitement NDLOCR-Lite + ONNX (V5)
├─ Tests/ (dans chaque package)
├─ build_ipa.sh
├─ LICENSES/                   # texte de chaque licence utilisée
├─ THIRD_PARTY_NOTICES.md      # URL + commit source de chaque portage, attributions
└─ README.md
```

- **Pourquoi des packages séparés :** le code original (MIT) et le code porté (GPL) restent
  physiquement séparés, comme demandé, et la logique pure se teste sur le Mac avec `swift test`
  sans lancer le simulateur (plus rapide, moins de chauffe).
- **XcodeGen** (outil Mac, MIT, installé via Homebrew) génère le projet Xcode depuis un petit
  fichier texte : pas de gros fichier `.pbxproj` illisible dans Git. *Seul outil ajouté au Mac.*
- **État de l'app :** `ObservableObject` + Combine (pas d'API iOS 17).
- **Dépendances SPM prévues :** GRDB (V1), ZIPFoundation (MIT, lecture des zip Yomitan en
  streaming, V3), swift-fsrs (V4), onnxruntime (V5). Rien d'autre sans te demander.
- **Note licence :** dès que YomitanKit (GPL) est lié à l'app (V3), *le binaire* de l'app est
  couvert par la GPLv3. Aucun problème pour un usage personnel, et ça reste publiable en GPLv3
  si un jour tu le décides (aucune dépendance incompatible).

## 3. Modèle de données (SQLite via GRDB)

Fichiers : PDF copiés dans `Application Support/Documents/<hash>.pdf` (jamais modifiés),
base `Application Support/kyokasho.sqlite`, médias de dictionnaires et modèles OCR sur disque.

| Table | Contenu principal |
|---|---|
| `document` | `id` = SHA-256 du fichier, titre, nom d'origine, nb de pages, date d'import, dernière page, dernière ouverture, réglages propres (JSON, vide = valeurs globales) |
| `pageTransform` | doc, page, rotation, découpe double page (oui/non), rognage |
| `highlight` | doc, page, rectangles (coordonnées PDF), couleur, texte sélectionné |
| `inkDrawing` | doc, page, dessin PencilKit (données binaires) |
| `bookmark` | doc, page, titre |
| `pageComment` | doc, page, texte, dates (plusieurs par page) |
| `aiPrompt` | prompts prédéfinis (texte, ordre) |
| `ocrResult` (V2) | **clé (doc, page, moteur)**, lignes JSON (texte, boîte de ligne, boîtes par caractère), date, durée |
| `benchSample` (V2) | image, texte de référence ; résultats par moteur (taux d'erreur, temps) |
| `dictionary`, `term`, `termMeta`, `kanji`, `kanjiMeta`, `tag` (V3) | format Yomitan, index sur l'expression et la lecture, priorité/activation par dictionnaire |
| `profile` (V3) | profils de réglages de recherche |
| `card`, `reviewLog`, `noteTemplate` (V4) | carte (champs, image, audio), état FSRS, historique, templates |

Réglages globaux : table `setting` (clé/valeur). Migrations GRDB versionnées dès la V1.

## 4. Plan par version

### V1 — Lecteur

**A. Import et bibliothèque**
- Import via le sélecteur Fichiers (`UIDocumentPickerViewController`, `asCopy: true` →
  télécharge les fichiers Google Drive qui ne sont que des espaces réservés), copie dans l'app,
  hash SHA-256 → un même fichier importé deux fois n'est pas dupliqué.
- Bibliothèque en grille/liste : miniature, titre, dernière page ; reprise automatique.

**A bis. Google Drive (demandé)** — deux niveaux :
1. **Via l'app Fichiers** (inclus dans A) : si l'app Google Drive est installée, Drive apparaît
   dans le sélecteur. Je gère proprement les fichiers « en ligne seulement » : téléchargement
   coordonné (`NSFileCoordinator`) avec barre de progression, reprise si coupure, message clair.
2. **Accès direct dans l'app** (option, *à valider : voir § 9*) : un onglet « Google Drive »
   pour parcourir tes dossiers, télécharger un PDF et **resynchroniser** une nouvelle version
   d'un cours (même fichier Drive, contenu changé → nouveau hash, annotations gardées par page).
   Demande une connexion Google (OAuth, `ASWebAuthenticationSession`, jeton dans le Trousseau)
   et un **identifiant client OAuth que tu crées toi-même** dans Google Cloud (gratuit) : ce
   n'est pas une clé payante, mais c'est un écart avec « aucune clé API ». Seules des requêtes
   que tu déclenches partent vers Google ; rien d'autre n'est envoyé.

**B. Lecteur** — PDFKit d'abord :

| Fonction | Comment |
|---|---|
| Simple / double page, paginé / continu | `displayMode` (`.singlePage`, `.twoUp`, `…Continuous`) + `usePageViewController` |
| Sens de lecture | `displaysRTL` |
| Décalage (1ʳᵉ page seule en double) | `displaysAsBook` |
| Rognage des bordures, rotation par page, séparation d'un scan double page | **code maison** : copie *en mémoire* de chaque page avec une `cropBox` / `rotation` modifiée (le fichier sur disque n'est jamais touché) ; rognage auto = détection des marges blanches sur un rendu basse résolution |
| Couleur de fond, transition, préchargement N pages | `backgroundColor`, options du page controller, pré-rendu des pages voisines |
| Zones de tap (+ inversion), double tap zoom, barres masquées au défilement | **code maison** (reconnaisseurs de gestes au-dessus de PDFView) |

Réglages par document, avec valeurs par défaut globales.

**C. Annotations** (PDF jamais modifié)
- Surcouche par page via `PDFPageOverlayViewProvider` : une vue PencilKit par page,
  `drawingPolicy = .pencilOnly` (le doigt fait défiler), surlignages dessinés dans la même surcouche.
- Surlignage : sélection de texte → rectangles enregistrés en base.
- Signets, recherche plein texte (`findString`).

**D. Commentaires de page** : plusieurs par page, liste par document, export Markdown (partage).

**E. Page vers IA, sans API**
- « Copier la page en image » (rendu haute résolution → presse-papiers) + prompts prédéfinis
  copiables et modifiables.
- Option : panneau web claude.ai à côté du PDF (`WKWebView`, session gardée).

**F. Réglages** : listes groupées à bascules façon Aidoku, thème sombre par défaut, rubrique
« OCR » vide, écran « À propos » (attributions).

**Tests unitaires V1 :** import + hash + dédoublonnage, migrations, calcul des pages en double
page (décalage, RTL), zones de tap, géométrie du rognage/découpe/rotation, export Markdown.

**Fini quand :** tourne dans le simulateur, `build_ipa.sh` produit un paquet installable, tests
verts, README clair.

### V2 — OCR
- `protocol OCREngine { func recognize(image) async throws -> [OCRLine] }` ;
  `OCRLine` = texte, boîte de ligne, boîtes par caractère (optionnelles).
- **Moteur Vision**, ja-JP. **Stratégie pour toucher un caractère précis** (à documenter et
  mesurer au banc d'essai) :
  1. passe `.accurate` sur la page → bon texte + boîtes de ligne ;
  2. boîtes par caractère d'abord estimées par **découpe proportionnelle** de la boîte de
     ligne (pleine chasse = 1, demi-chasse ≈ 0,5) — instantané ;
  3. quand tu touches une ligne, passe `.fast` sur *cette ligne seulement* pour obtenir les vraies
     boîtes par caractère et corriger l'estimation, si le texte des deux passes concorde.
- Cache (doc, page, moteur) ; changer de moteur n'efface rien. Moteur choisi : Auto / précis,
  remplaçable par document, affiché dans la barre d'info. Bouton « Comparer ».
- Vue texte de la page (style lecteur de texte d'Aidoku) : défilement ou pages, police, taille,
  interligne, marges.
- Banc d'essai : images + texte de référence → taux d'erreur de caractères (CER) et temps.
- **Tests :** calcul du CER, découpe proportionnelle, cache, sérialisation des résultats.

### V3 — Dictionnaire au toucher (parité Yomitan)
- Import zip Yomitan **en streaming** (ZIPFoundation, un fichier `term_bank_N.json` à la fois,
  insertion par lots dans une transaction, progression, annulation) ; suppression, mise à jour.
- Plusieurs dictionnaires, priorité, activation.
- Recherche portée de Yomitan : normalisation (katakana ↔ hiragana, demi-chasse, variantes),
  déconjugaison par **tables de transformation** de Yomitan, plus long mot à partir du
  caractère touché, lecture + furigana.
- Popup : contenu structuré Yomitan rendu en HTML dans une `WKWebView` (le plus fidèle),
  popups imbriqués, historique, fréquence, accent, infos kanji, audio local et en ligne
  (téléchargé seulement quand tu le demandes).
- Page de recherche manuelle, profils.
- Performances : j'étudie **hoshidicts** (GPL-3.0, compatible) ; si utile, portage ou
  compilation de son cœur C++ dans YomitanKit.
- **Tests :** sur un **petit dictionnaire factice écrit par moi** : import, déconjugaison
  (table de cas), segmentation, normalisation, plus long mot.

### V4 — Cartes et révisions
- Carte depuis le popup : mot, lecture, sens, phrase (OCR), image de la zone, audio.
- Templates façon Handlebars : **sous-ensemble écrit par moi** (`{{champ}}`, `{{#if}}`,
  `{{#each}}`) plutôt qu'une grosse dépendance.
- Révisions **FSRS via swift-fsrs** (compatible avec ton Xcode, pas besoin de SM-2).
- Export CSV, puis `.apkg` (format décrit par genanki, réécrit en Swift).
  Option AnkiMobile : envoi via son schéma d'URL `anki://` si simple.
- **Tests :** rendu des templates, planification FSRS, CSV, structure du `.apkg`.

### V5 — Moteurs OCR supplémentaires
- NDLOCR-Lite via ONNX Runtime (iOS 15+ ✅). Prétraitement/post-traitement réécrits en Swift.
  Modèles **téléchargés à la demande** (taille affichée, bouton supprimer), jamais dans l'IPA.
- « Auto » : texte vertical détecté → NDLOCR-Lite, sinon Vision. Option PP-OCRv5 mobile (Apache-2.0).
- Décision finale d'après le banc d'essai.

## 5. Installation sur l'iPad (`build_ipa.sh`)

1. `xcodegen generate` (régénère le projet).
2. `xcodebuild archive` en Release pour `generic/platform=iOS`, **sans signature**
   (`CODE_SIGNING_ALLOWED=NO`), optimisations maximales (voir § 5 bis). Vitesse pleine pour l'instant
   (tu as dit que la chauffe du Mac n'est pas un souci en ce moment).
3. Copie de `Kyokasho.app` dans `Payload/`, pseudo-signature `ldid -S` avec les entitlements.
4. Zip → `dist/Kyokasho-<version>.tipa` (même format qu'un `.ipa`, extension habituelle de
   TrollStore et de tes autres apps).
5. Ouvrir le `.tipa` avec TrollStore sur l'iPad.

Chaque étape expliquée dans le README.

## 5 bis. Performances et mémoire (exigence forte)

Objectif : **fluide à 120 Hz** (écran ProMotion du M1), mémoire stable même sur un gros manuel,
aucun gel de l'interface. Chaque version se termine par une mesure, pas par une impression.

**Cibles mesurées** (simulateur pour la tendance, iPad pour les vrais chiffres) :

| Mesure | Cible |
|---|---|
| Défilement / tourne-page | 120 images/s, aucune image ratée visible |
| Ouverture d'un document déjà importé | < 300 ms jusqu'à la 1ʳᵉ page nette |
| Reprise de l'app | < 0,5 s jusqu'à la bibliothèque |
| Popup dictionnaire (toucher → affichage) | < 50 ms (données en cache OCR) |
| OCR Vision d'une page | en tâche de fond, jamais sur le fil principal |
| Mémoire, manuel de 500 pages ouvert | < 300 Mo, sans croissance au fil des pages |
| Import d'un gros dictionnaire | mémoire plafonnée (< 150 Mo) quelle que soit sa taille |

**Comment :**
- **Rendu PDF** : PDFKit dessine déjà par tuiles à la résolution affichée ; je n'ajoute aucun
  rendu pleine page inutile. Miniatures générées hors du fil principal, cache mémoire limité
  (`NSCache` avec coût) + cache disque ; tout est vidé sur alerte mémoire.
- **Pages transformées** (rognage, découpe, rotation) : créées à la demande pour les pages
  visibles ± N seulement, jamais tout le document.
- **Surcouches** : une seule vue PencilKit par page *affichée*, recyclées (pool) quand la page
  sort de l'écran ; dessins chargés à la demande, sauvegardés en différé hors fil principal.
- **Base de données** : GRDB en mode WAL (`DatabasePool`) → lectures en parallèle, écritures en
  tâche de fond ; requêtes préparées en cache ; index pensés pour chaque recherche.
- **Dictionnaire** : tables compactes avec index sur clés normalisées, toutes les formes
  candidates d'un toucher cherchées **en une seule requête**, cache des dernières recherches,
  tables de déconjugaison précompilées. Import en flux (un fichier du zip à la fois, analyse JSON
  incrémentale, lots de quelques milliers de lignes). Si le banc de test le justifie : cœur de
  recherche porté d'hoshidicts (C++).
- **OCR** : image rendue à la résolution utile seulement, file d'attente limitée, annulation si
  la page sort de l'écran, résultats en cache (une page n'est jamais refaite). V5 : session ONNX
  réutilisée, accélération Core ML / Neural Engine si le modèle s'y prête.
- **Interface SwiftUI** : petits objets observés (un changement ne redessine pas tout l'écran),
  listes paresseuses, vues lourdes en UIKit (PDFView) ; aucune grosse opération dans `body`.
- **Compilation** : Release en `-O` + optimisation du module entier ; pas de journalisation en
  production sauf signposts (coût nul hors Instruments).
- **Vérification** : tests de performance automatiques (temps + mémoire) sur les parties pures
  (import, recherche, déconjugaison), session Instruments (Time Profiler, Allocations, Leaks)
  à la fin de chaque version, chiffres notés dans le bilan. Vrais chiffres sur l'iPad seulement
  avec ta permission.

## 6. Façon de travailler

- Petits commits en français (+ ligne Co-Authored-By), branche `main`, dépôt privé.
- Chaque version : compile → tourne dans le simulateur (vérifié par moi : captures, taps) →
  tests verts → bilan honnête **testé / non testé / fragile** → ton accord → version suivante.
- Simulateur dédié : « iPad Pro 12.9 (5th gen) Kyokasho » (iOS 27).
- Je ne touche à ton iPad qu'avec ta permission, en te disant pourquoi.
- En-tête SPDX dans chaque fichier, `LICENSES/`, `THIRD_PARTY_NOTICES.md` tenus à jour.

## 7. Ce qui ne pourra pas être testé dans le simulateur

- **Apple Pencil** (dessin pencilOnly, pression), le **trackpad** et le comportement réel d'iOS 16.
- **Google Drive** : le chemin Fichiers se teste en partie (pas d'app Drive dans le simulateur) ; l'accès direct (§ 4 A bis) se teste dans le simulateur si tu crées l'identifiant Google.
- Performances réelles (gros manuel, gros dictionnaire) : le Mac est bien plus rapide que l'iPad.
- Installation TrollStore. → Tout ça se vérifie sur l'iPad, avec ta permission.

## 8. Risques

| Risque | Gravité | Parade |
|---|---|---|
| Simulateur iOS 27 ≠ iOS 16 (bugs PDFKit/SwiftUI propres à iOS 16 invisibles) | Moyenne | Compilation stricte iOS 16.0, test final sur l'iPad |
| PDFKit : `usePageViewController` + RTL + double page parfois capricieux ; double tap/zoom en conflit avec les zones de tap | Moyenne | Gestes maison au-dessus de PDFView, tests manuels de chaque combinaison |
| Rognage / découpe / rotation en mémoire : coût mémoire sur gros scans | Moyenne | Pages créées à la demande, pas tout le document |
| Vision en japonais **vertical** souvent mauvais | Haute (pour les manuels verticaux) | Découpe en colonnes ; vraie réponse en V5 (NDLOCR-Lite) |
| Boîtes par caractère imprécises avec `.accurate` | Moyenne | Stratégie en 3 temps (§ V2), mesurée au banc d'essai |
| Gros dictionnaires (centaines de Mo) : import long, base lourde | Moyenne | Streaming, lots, index ciblés, étude d'hoshidicts |
| Google Drive direct : Google peut limiter les apps non vérifiées (écran d'avertissement, 100 utilisateurs max) | Faible (usage perso) | Tu acceptes l'avertissement une fois ; repli : chemin Fichiers |
| Objectifs de perf mesurés au simulateur seulement (Mac bien plus rapide que l'iPad) | Moyenne | Mesure sur l'iPad à chaque fin de version, avec ta permission |
| Connexion à claude.ai dans une `WKWebView` (Google refuse souvent la connexion dans une vue web intégrée) | Moyenne | Connexion par e-mail, ou Split View iPad avec Safari |
| ONNX Runtime alourdit l'app et la mémoire | Moyenne | Seulement en V5, modèles téléchargés à part |

## 9. Décisions (réponses du 20 octobre 2026)

1. **Google Drive direct : oui** (tu as un compte Google perso ; je te guide pour créer
   l'identifiant client OAuth quand on y arrive).
2. **XcodeGen : oui** (installé).
3. **Versions** : `v0.1.0` = V1 … `v1.0.0` à la fin, `.tipa` joints aux releases privées, README
   avec ton en-tête habituel.
4. **claude.ai** : panneau intégré dans l'app + bouton « Ouvrir dans Safari » en repli si la
   connexion est bloquée dans la vue intégrée.
5. **Licences** : toutes celles citées sont acceptées, jiten (AGPL-3.0) compris.

> Note d'organisation : les « modules » sont des cibles d'un même package Swift local
> (`Packages/KyokashoKit`) ; les écrans SwiftUI vivent dans la cible de l'app (`App/`).

## 10. Découpage en sessions (1 par jour, jusqu'au mardi 27 octobre 2026)

Règle : une session = une étape, peu de code relu, pas de simulateur sauf feu vert.
Au début de chaque session, lire seulement cette section et `git log -3`.

| Jour | Étape | Fini quand |
|---|---|---|
| mer. 21 | V4-a : ReviewKit compile (cible + swift-fsrs dans Package.swift), tests templates / FSRS / file de révision | `swift test` vert |
| jeu. 22 | V4-b : export CSV + `.apkg` (format genanki) + lien AnkiMobile, tests | tests vert |
| ven. 23 | V4-c : app, créer une carte depuis le popup et l'onglet Mots (champs, phrase, image de la zone, audio, anti-doublon) | app compile |
| sam. 24 | V4-d : app, écran de révision, liste des cartes, réglages + éditeur de modèle, export → release **0.5.0** | release publiée |
| dim. 25 | V5-a : ONNX Runtime, téléchargement des modèles NDLOCR-Lite à la demande, prétraitement | tests vert |
| lun. 26 | V5-b : inférence + post-traitement, mode « Auto » (vertical → NDLOCR), banc d'essai | app compile |
| mar. 27 | Release **0.6.0** + tests simulateur / iPad (si tu dis oui) + corrections | release publiée |

État au 20 octobre : V3 publiée (0.4.0). ReviewKit commencé (`Sources/ReviewKit` : templates,
modèles, base, FSRS) mais **pas encore dans Package.swift, jamais compilé**.
