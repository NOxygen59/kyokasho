# IA locale sur iOS 16 — comment ça marche (à lire avant de toucher à MLX ou aux modèles)

> Écrit le 22/10/2026, état v0.8.6. Tout ce qui suit a été **vérifié sur l'iPad de l'utilisateur** (OvisOCR2 lit,
> l'analyse et la vérification de double page marchent : « BORDEL ÇA FONCTIONNE DE FOU ») sauf mention contraire.

## 1. Les pièces

| Pièce | Où | Rôle |
|---|---|---|
| **MLX** (Apple, C++ + Metal) | fork `NOxygen59/mlx-swift`, branche **`ipad-ios16`** (défaut), clone `~/Projets-iPad/mlx-swift` | moteur de calcul GPU |
| **mlx-swift-lm** (modèles LLM/VLM en Swift) | fork `NOxygen59/mlx-swift-lm`, branche **`ipad-ios16`**, clone `~/Projets-iPad/mlx-swift-lm` | Qwen3.5 (OvisOCR2), Qwen3-VL, GLM-OCR… |
| **swift-transformers 1.3.5** (Hugging Face) | dépendance de `Packages/GLMOCRKit` | tokenizers (mlx-swift-lm 3.x ne les charge plus lui-même) |
| **`Packages/GLMOCRKit`** | dépôt kyokasho | nos lecteurs : `GLMOCREngine`, `PageVLMReader` / `OvisOCR2Reader` / `Qwen3VLReader`, `GLMModel` (cache), `Tokenizers+MLX.swift` |
| **ONNX Runtime** (Microsoft) | `ONNXOCRKit` | NDLOCR-Lite, PP-OCRv5, DE-GAN, PP-DocLayout, DocLayout-YOLO (pas MLX) |
| **MeCab + UniDic-lite** | `MeCabC` + `MorphologyKit` | analyseur japonais (furigana), C++ CPU, dictionnaire `mmap` |

Versions de base : mlx-swift **0.32.3**, mlx-swift-lm **3.32.3**. `Package.resolved` de l'app épingle une
**révision** des forks : après chaque `git push` dans un fork, **mettre à jour l'épingle** (sinon Xcode garde l'ancienne) :

```
cd ~/Projets-iPad/kyokasho && f=$(find Kyokasho.xcodeproj -name Package.resolved | head -1)
A=$(git -C ~/Projets-iPad/mlx-swift rev-parse HEAD) B=$(git -C ~/Projets-iPad/mlx-swift-lm rev-parse HEAD) F=$f python3 - <<'EOF'
import json,os
d=json.load(open(os.environ['F']))
for p in d['pins']:
    if p['identity']=='mlx-swift': p['state']['revision']=os.environ['A']
    if p['identity']=='mlx-swift-lm': p['state']['revision']=os.environ['B']
json.dump(d,open(os.environ['F'],'w'),indent=2)
EOF
rm -rf build/ipa/DerivedData/SourcePackages/checkouts/mlx-swift*   # sinon build_ipa.sh garde l'ancien checkout
```
Contrôle dans le binaire : `unzip` du `.tipa` puis `strings Payload/Kyokasho.app/Kyokasho | grep -c '<texte du correctif>'`.

## 2. Pourquoi des forks : ce qui bloquait iOS 16, et comment c'est comblé

**Règle de l'utilisateur** : combler par du code qui fait **exactement la même chose**, jamais retirer ou couper un
contrôle (mémoire `ios16-backport-rules`). Chaque correctif est listé dans `IPAD-IOS16.md` de chaque fork.

### mlx-swift (`~/Projets-iPad/mlx-swift`)
1. `Package.swift` : `.iOS(.v16)` (déclarait 17). Dossier **`Source/Cmlx/ios16-overrides`** ajouté **en premier** dans
   `cSettings` **et** `cxxSettings` (`headerSearchPath`) : un en-tête de même chemin y remplace celui d'un sous-module
   (les réglages C passent avant les C++ : il faut les deux).
2. **`bfloat` natif = Metal 3.1 (iOS 17)** : MLX ≥ 0.30 l'utilise partout. Remplacé par le **bfloat logiciel**
   `_MLX_BFloat16` de mlx-swift 0.29.1 (`tools/ipad-ios16-bf16-software.h`). Sites adaptés : `utils.h`
   (`val.bits_` au lieu de `as_type<uint16_t>`), `fp8.h` (constructeur `bits_to_bfloat`), `complex.h` (complexe
   bfloat = tests de compilation seulement, retirés), `dot.h` (lecture `vec<T,4>` → élément par élément pour le bfloat).
3. Ces noyaux existent **deux fois** : `Source/Cmlx/mlx-generated/metal/*.h` (compilés par Xcode dans
   `default.metallib`) **et** `Source/Cmlx/mlx-generated/*.cpp` (texte embarqué, compilé **sur l'iPad** à la volée =
   JIT). Le dossier `mlx/mlx/backend/metal/kernels` du sous-module est **exclu** du build : ne pas y toucher.
   → **`python3 tools/ipad-ios16-patch.py`** applique tout aux deux, rejouable, échoue s'il reste du Metal 3.1.
4. **Langage Metal du JIT** : `device.cpp` choisissait ≥ 3.1. Remplacé par `ios16-overrides/src/metal_device.cpp`
   (l'original est **exclu** dans `Package.swift`) : branche « iOS 17 → 3.1, sinon **3.0** ».
   Variable d'essai **`MLX_METAL_LANGUAGE_VERSION=30`** : force Metal 3.0 sur Mac.
5. **`metal::remove_addrspace_t`** (Metal 3.1, absent du compilateur d'iOS 16, **présent sur Mac même en 3.0** : le test
   Mac ne le voyait pas) → `mlx_remove_addrspace_t`, copie exacte de la définition d'Apple (`metal_type_traits`),
   insérée avant `#define integral_const_binop` (script).
6. **`#pragma clang fp reassociate(off)`** (noyau GatedDelta de mlx-swift-lm, somme de Kahan) inconnu du clang
   d'iOS 16 → dans `metal_device.cpp::build_library_`, si Metal < 3.1 : directive retirée **et**
   `setFastMathEnabled(false)` pour cette bibliothèque (même garantie : aucune réassociation).
7. `std::format` (mlx-c `private/io.h`) exige libc++ d'iOS 16.3+ → `ios16-overrides/mlx/c/private/io.h` = copie avec
   les **mêmes messages** construits par concaténation. **Interdit** : `_LIBCPP_DISABLE_AVAILABILITY` (a fait
   planter la 0.8.4 au lancement : `exception_ptr::__from_native_exception_pointer` absent d'iOS 16).
8. **`simdgroup_matrix<bool>`** (masque booléen de l'attention « steel », Qwen3-VL en traduction) : le compilateur
   d'iOS 16 refuse même sa **déclaration** dans `BaseMMAFrag<bool>` (le Mac l'accepte : pas reproductible) →
   `mlx_simdgroup_matrix_or_none` (script) : type vide pour `bool` seulement, jamais utilisé. Journal 0.8.7 :
   « Unable to build metal library … is_simdgroup_matrix_element<bool> ». Test Mac Metal 3.0 : traduction OK.

### mlx-swift-lm (`~/Projets-iPad/mlx-swift-lm`)
1. `Package.swift` : `.iOS(.v16)`, trait `FoundationModelsIntegration` coupé par défaut, dépend du fork mlx-swift
   (`branch: "ipad-ios16"`). Pour compiler contre le clone local : remplacer temporairement par
   `.package(path: "../mlx-swift")`, puis `git checkout Package.swift` avant de committer.
2. `GenerationWorker.swift` : `DispatchSerialQueue` (iOS 17) → `QueueSerialExecutor` maison sur `DispatchQueue`.
3. `Load.swift` : chargement des poids sur une file Dispatch (qui perd le gestionnaire d'erreurs MLX de la tâche) →
   enveloppé dans `withError { }` : une erreur MLX devient un `throw` au lieu d'arrêter l'app.

### Méthode qui a marché (à refaire pour tout nouvel obstacle)
- L'iPad dit **le premier** obstacle seulement (le compilateur Metal s'arrête au premier fichier en erreur). Boucle :
  journal de diagnostic → corriger → **chercher tout de suite les semblables** dans tous les noyaux
  (`grep -rhoE '#pragma …'`, `grep -ohE 'metal::[a-zA-Z_]+'`, comparer à ce que Metal 3.0 connaît) → test Mac
  `MLX_METAL_LANGUAGE_VERSION=30` → épingle → `.tipa`.
- Le Mac ne reproduit pas tout (son compilateur Metal est plus récent) : le **journal de diagnostic de l'iPad** fait
  foi (Réglages → Outils → Diagnostic → Partager le journal ; les erreurs MLX y sont notées même en cas d'arrêt).
- Erreurs MLX dans l'app : jamais d'arrêt. `Diagnostics.start()` pose un gestionnaire global qui **note puis**
  `fatalError` (dernier recours) ; les lectures sont dans `withError { }` (`PageVLMReader.read`, `GLMModel.read`,
  `Qwen3VLReader.translate`) → erreur de page affichée.

## 2 bis. Vitesse (mesures du 22/10, Mac Metal 3.0, vraie page du manuel)

- OvisOCR2 (8 bits) : **lecture de l'image 1,6 s** (1358 jetons à ≈ 830 /s), **écriture du texte 19 s** (849 jetons
  à ≈ 44 /s) = 92 % du temps. L'écriture est limitée par la bande passante mémoire (poids relus à chaque jeton).
- Essayé et **écarté** : passer les paramètres `bfloat16` en `float16` au chargement (texte identique, **aucun gain** :
  21,0 s contre 21,0 s). Le `bfloat16` logiciel n'est pas le goulot.
- Gains sans perte faits : ne jamais relire une page déjà lue (scan à l'ouverture → vérification, mise en page,
  analyse réutilisent `ovisocr2-<page>.md`). Pistes restantes, **avec** risque de qualité : Ovis en 4 bits (≈ ×1,6
  attendu), cache clé-valeur quantifié, GLM-OCR par groupes de lignes (B7). Mesure : `testProfileRealPage`.

## 3. Nos lecteurs (Packages/GLMOCRKit)

- **`GLMModel`** (actor) : **un seul modèle MLX en mémoire**. `container(directory:extraEOSTokens:)` garde le chargé,
  partage un chargement en cours (`loading`), libère l'autre modèle avant d'en charger un nouveau ;
  `unload(directory:)` ne libère que celui-là. `MLX.GPU.set(cacheLimit: 256 Mo)`.
  Toute lecture passe par `GLMModel.using` : cache GPU vidé après, modèle libéré après 45 s d'inactivité,
  au retour à la bibliothèque et en arrière-plan (`GLMOCREngine.unloadIfIdle`).
- **Chargement** : `VLMModelFactory.shared.loadContainer(from: LocalOnly(), using: TransformersTokenizerLoader(),
  configuration: ModelConfiguration(directory:extraEOSTokens:))` — modèles déjà sur l'iPad (`ModelStore`), aucun
  téléchargement ici ; `TransformersTokenizerLoader` = pont écrit à la main (même code que la macro
  `#huggingFaceTokenizerLoader`).
- **Génération** : `UserInput(chat: [.user(prompt, images: [.ciImage(…)])], additionalContext:)` (jamais
  `UserInput(prompt:images:)` : perd les images), `MLXLMCommon.generate(… temperature: 0)`, rappel
  `Task.isCancelled ? .stop : .more` (sinon une annulation laisse tourner jusqu'à `maxTokens`).
- **Longueur bornée** : `DocumentAnalysisService.tokenBudget(page)` = ≈ 2 × texte trouvé par l'OCR + 256 (≤ 4096) :
  un modèle qui boucle ne remplit plus la mémoire.
- **Mémoire libre vérifiée** avant chargement (`os_proc_available_memory`, `PageVLMReader.minimumFreeMemory`) → erreur
  claire plutôt qu'un arrêt par iOS. Droits TrollStore : `increased-memory-limit` + `extended-virtual-addressing`.

| Modèle | Fichier / spec | Taille | Rôle | Mesures (Mac, Metal 3.0, vraie page) |
|---|---|---|---|---|
| **OvisOCR2** (Qwen3.5, 0,9 B, 8 bits) | `ModelSpec.ovisocr2`, `OvisOCR2Reader` (consigne officielle de la carte HF, `enable_thinking: false`, 1600 px) | 1 Go | **lecteur principal** : page → Markdown | ≈ 22 s/page, pic GPU 2,1 Go, texte excellent |
| **GLM-OCR** (0,9 B, 4 bits) | `ModelSpec.glmocr`, `GLMOCREngine` (ligne par ligne, détection PP-OCRv5) | 1,2 Go | relecture des lignes douteuses, 2e voix de l'analyse | ≈ 1 s/ligne |
| **Qwen3-VL-4B** (4 bits) | `ModelSpec.qwen3vl4b`, `Qwen3VLReader` | 3,1 Go | **traduction** FR (`translate`, texte seul, glossaire) ; lecture optionnelle (moins bonne : 襖 → 桜) | lecture 37 s, 4 Go ; traduction 49 s/page, 3,75 Go |

## 4. Où l'IA sert dans l'app

- **Vérifier la double page** (`ReaderController.verifyShownPages`, `VerifySheet`) : OvisOCR2 → `OCRReferenceDiff`
  (alignement caractère par caractère) → propositions à accepter.
- **Analyser le document entier** (`DocumentAnalysisService`, `DocumentAnalysisSheet`) : OCR habituel → chaque
  lecteur sur **toutes** les pages (un modèle à la fois) → `DocumentAnalysis.vote` (≥ 2 lectures identiques =
  confirmée) → fiabilité, choix conseillés. Lectures brutes `Application Support/Analysis/<id>/<lecteur>-<page>.md`.
- **Mise en page IA** (`AILayoutView`) : Markdown d'OvisOCR2 → `AILayout.blocks` (blocs sûrs) → HTML du thème,
  figures découpées. **Traduction** : `Analysis/<id>/fr-<page>.md`.
- **Relecture OCR** : `OCRProofreader` (dictionnaire) puis GLM-OCR sur les lignes douteuses (`rereadDoubtful`).

## 5. Tester sur le Mac (autorisé par l'utilisateur le 22/10 pour OvisOCR2 / Qwen3-VL)

Modèles et PDF d'essai **hors dépôt** (scratchpad du chat ; le PDF de l'utilisateur :
`~/Downloads/INTERIOR COORDINATOR HANDBOOK HAWE.pdf`, 24 p., ne jamais le copier dans le dépôt).
```
cd Packages/GLMOCRKit && swift package update mlx-swift mlx-swift-lm && swift build --build-tests
MLX_METAL_LANGUAGE_VERSION=30 KYOKASHO_MODELS=<dossier contenant ovisocr2/ qwen3vl4b/> \
  KYOKASHO_SAMPLE_PDF="$HOME/Downloads/INTERIOR COORDINATOR HANDBOOK HAWE.pdf" KYOKASHO_SAMPLE_PAGES=1,2 \
  swift test --skip-build --filter testRealSample          # + KYOKASHO_ONLY=OVIS|QWEN, KYOKASHO_DUMP=<dossier>
KYOKASHO_TRANSLATE=<page.md> … --filter testQwenTranslatesPage
```
Téléchargement d'un modèle pour test : fichiers listés dans `ModelStore.swift` (URL figée sur une révision HF),
`curl -sSLo` dans `<dossier>/<id>/`, **tous** les fichiers du spec (sinon `isInstalled` = faux, ex. `LICENSE`).

## 6. Mettre MLX à jour plus tard
1. Dans le fork mlx-swift : `tools/update-mlx.sh` (régénère `mlx-generated`), puis `python3 tools/ipad-ios16-patch.py`,
   re-vérifier `Package.swift` (iOS 16, `ios16-overrides`, exclusion de `device.cpp`) et refaire le correctif
   `metal_device.cpp` à partir du nouveau `device.cpp` (branches Metal 3.0 + `reassociate`).
2. mlx-swift-lm : rebaser `ipad-ios16`, refaire les 3 changements ci-dessus.
3. Test Mac Metal 3.0 sur une vraie page, épingle, `.tipa`, essai iPad avec le journal de diagnostic.
