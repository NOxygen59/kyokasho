<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Feuille de route CI — GitHub Actions sur Apple Silicon

## Objet et état de référence

Ce document prépare une future mise en œuvre de l'intégration continue. Il ne modifie aucun workflow, ne lance aucune compilation et ne prépare aucune release.

Audit réalisé le **25 octobre 2026** sur le commit local combiné `edd09b29df7dd9aa02cbdbe01730a3a054e98985` (`codex/validation-combinee-2`). Ce checkout assemble le travail des PR 1, 2 et 3. Avant toute mise en œuvre, le futur agent doit relever le SHA de départ, relire `AGENTS.md`, [le plan directeur](PLAN-DIRECTEUR.md) et [la feuille de route](FEUILLE-DE-ROUTE.md), puis comparer ce document avec les workflows réellement présents sur la branche cible.

**Vérification lors de la publication (25 octobre 2026, `main` à `ee07c55`)** : l'arbre de fichiers du commit audité `edd09b2` est identique à celui de `main` au commit `c2b1b29` (fusion de la PR #3) ; `main` n'a reçu depuis que le plan directeur (PR #4). Les trois workflows décrits ci-dessous sont identiques, octet pour octet, à ceux de `main`. Le reste du document est publié tel que rédigé par Codex ; les tarifs, labels de runners et versions Xcode cités n'ont **pas** été revérifiés lors de cette publication.

Contraintes permanentes : iOS 16.0 minimum, aucune installation sur l'iPad, aucune donnée ou modèle utilisateur dans GitHub, aucune mise à jour opportuniste des dépendances ou des forks MLX, aucune création de release. Un succès Mac ne confirme jamais le comportement sur l'iPad iOS 16.6.1.

## Audit des workflows présents

Trois workflows sont versionnés sur l'état audité.

| Workflow | Déclenchement et runner | Travail réel | Points solides | Limites observées |
|---|---|---|---|---|
| `.github/workflows/documentation.yml` | PR et push sur `main` limités aux documents ; `ubuntu-latest` | Liens Markdown locaux ; `git diff --check HEAD^ HEAD` | `contents: read`, checkout épinglé, délai de 5 min, aucun accès aux données | Sur une PR, le checkout du commit de fusion synthétique permet normalement de couvrir le changement complet face à son premier parent ; sur un push groupant plusieurs commits, la commande ne couvre que le dernier. La preuve dépend donc de l'événement et de la sémantique du checkout. Aucun contrôle du YAML, des licences ou de l'état généré. |
| `.github/workflows/storage.yml` | PR touchant `PageShift.swift`, `KyokashoKit` ou le workflow ; `macos-15` | Suite complète `KyokashoKit` avec résolutions figées | `macos-15` désigne actuellement un runner standard arm64 ; checkout épinglé ; aucun secret ; délai de 20 min ; contrôle des deux `Package.resolved` | Xcode utilisé implicitement ; architecture non vérifiée ; aucune compilation de l'app ; aucun ASan ; les autres fichiers `App/` liés à l'orchestration ne déclenchent pas le job. |
| `.github/workflows/backup.yml` | PR touchant l'outil, ses tests, tout `KyokashoKit` ou le workflow | 16 tests Python sur Ubuntu ; test Swift `BackupRoundTripTests` sur Mac | Données synthétiques, restauration réelle de bases GRDB, résolutions figées, délais courts | Tout changement de `KyokashoKit` lance à la fois ce job Mac et la suite Mac complète, qui compile déjà le test de sauvegarde ; coût dupliqué ; aucun résultat structuré ni journal conservé en cas d'échec. |

Les trois workflows utilisent `actions/checkout` avec un SHA complet et `persist-credentials: false`. C'est la bonne base de sécurité. Ils n'utilisent ni secrets, ni signature, ni `pull_request_target`, ni runner auto-hébergé.

L'historique des exécutions GitHub n'a pas été interrogé avec succès pendant l'audit initial. Relevé lors de la publication, sur `main` à `c2b1b29` : `Stockage Mac` (run `40152582505`, job `tests` ≈ 1 min 22 s), `Sauvegarde synthétique` (run `40152580509`, jobs `outil` ≈ 5 s et `bases-reelles` ≈ 1 min 49 s) et `Documentation` réussis. Les deux workflows Mac ont été lancés **manuellement** (`workflow_dispatch`) : ils ne se déclenchent pas sur un push vers `main`. Le futur agent devra associer chaque résultat au SHA exact avant de définir des contrôles obligatoires.

### Tests déjà automatisables

| Groupe | Commande de référence | Runner conseillé | Statut CI proposé |
|---|---|---|---|
| Documentation | `python3 scripts/check_documentation.py` puis diff complet de la PR | Ubuntu | Obligatoire à chaque PR pertinente |
| Sauvegarde synthétique | `python3 -m unittest discover -s tests -v` | Ubuntu | Obligatoire ; 16 méthodes présentes à l'audit |
| Logique et intégration Swift | `swift test --package-path Packages/KyokashoKit --disable-automatic-resolution` | macOS 15 arm64 | Obligatoire pour le code Swift ; 163 méthodes `test…` présentes à l'audit |
| PageShift | Filtre `PageShiftTests` | macOS 15 arm64 | Inclus dans la suite ; filtre utile pour diagnostic ou ASan |
| Restauration GRDB | Filtre `BackupRoundTripTests` | macOS 15 arm64 | Inclus dans la suite ; peut rester un job court si un contrôle distinct est souhaité |
| Compilation de l'app | XcodeGen puis `xcodebuild` vers `generic/platform=iOS`, sans signature | macOS 15 arm64 | Obligatoire pour l'app, `project.yml`, les manifestes et les résolutions |
| GLMOCRKit sans modèles | Construction du paquet et de ses tests avec résolution figée | macOS 15 arm64 | Obligatoire seulement pour MLX, GLMOCRKit, projet ou épingles concernés |
| ASan CPU | `swift test … --sanitize address` | macOS 15 arm64 | Manuel au début, puis périodique après qualification |
| Modèles ONNX, UniDic et MLX réels | Variables `KYOKASHO_*` avec assets externes autorisés | Runner dédié qualifié | Jamais obligatoire sur chaque PR ; essais contrôlés et privés |

Les tests sans asset doivent rester signalés comme ignorés. Un `XCTSkip` faute de modèle, dictionnaire ou corpus ne constitue pas une validation de cet asset. `GLMOCRKit` comporte huit méthodes de test, presque toutes destinées à des modèles ou documents externes ; une simple compilation reste utile, mais une suite verte sans ces assets ne prouve pas l'inférence.

## Architecture CI cible

### 1. Contrôles rapides sur Ubuntu

Créer ou faire évoluer un workflow léger, par exemple `quality.yml`, avec :

- liens documentaires et espaces du diff correspondant exactement à l'événement : base de fusion vers SHA de tête pour une PR, ancien SHA vers nouveau SHA pour un push ;
- 16 tests Python de sauvegarde ;
- contrôle que les deux `Package.resolved` sont valides, suivis par Git et inchangés après les commandes ;
- recherche limitée aux fichiers suivis de données interdites évidentes : PDF utilisateur, poids de modèles, dictionnaires et fichiers de secrets ;
- `permissions: contents: read`, checkout à SHA complet, `persist-credentials: false`, délai et annulation des exécutions PR devenues obsolètes.

Ce niveau ne doit pas prétendre valider Swift, PDFKit, Vision, GRDB natif, ONNX ou MLX.

### 2. Tests Swift sur macOS Apple Silicon

Utiliser explicitement `macos-15`. Au 25 octobre 2026, GitHub documente ce label comme un runner standard **M1 arm64, 3 cœurs, 7 Go de RAM et 14 Go de stockage**. Ne pas utiliser `macos-latest`, qui peut changer de version de macOS et de chaîne Xcode.

Le premier bloc du job doit échouer si l'environnement n'est pas celui attendu :

```sh
test "$(uname -m)" = arm64
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
xcodebuild -version
swift --version
```

Xcode 16.4 est actuellement disponible sur l'image `macos-15` et fournit le SDK iOS 18.5. Le chemin doit être contrôlé à chaque évolution de l'image. Si GitHub retire cette version, ouvrir un lot explicite de qualification au lieu de basculer silencieusement vers le Xcode par défaut.

La suite `KyokashoKit` doit conserver `--disable-automatic-resolution`. En cas d'échec, conserver le code de sortie et un journal borné ; avec `tee`, activer `set -o pipefail`. Vérifier après le test que les deux fichiers résolus sont inchangés.

Pour éviter la duplication actuelle, commencer par mesurer la durée des deux jobs Mac. Si la suite complète exécute bien `BackupRoundTripTests`, garder le job Swift de sauvegarde séparé seulement s'il fournit un contrôle obligatoire plus rapide et clairement nommé. Sinon, conserver les tests Python sur Ubuntu et laisser l'intégration GRDB dans la suite Swift unique.

### 3. Compilation iOS générique sans installation

Ajouter un job distinct pour les changements de `App/`, `project.yml`, des deux packages, des résolutions ou des forks épinglés. Il ne doit démarrer ni simulateur ni appareil :

```sh
xcodegen generate --quiet
mkdir -p Kyokasho.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Packages/GLMOCRKit/Package.resolved \
  Kyokasho.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO build
```

Le job doit vérifier avant la construction que `project.yml` garde `iOS: "16.0"` et `IPHONEOS_DEPLOYMENT_TARGET: "16.0"`. Compiler avec un SDK récent et une cible minimale 16.0 détecte des erreurs de disponibilité au build ; cela ne reproduit ni le compilateur Metal de l'iPad, ni le lancement sous iOS 16.6.1.

XcodeGen n'apparaît pas dans la liste actuelle des logiciels préinstallés du runner. La machine locale possède la version 2.46.0, mais cela ne vaut pas pour GitHub. Le futur agent doit choisir une méthode reproductible et documentée : version XcodeGen explicite, provenance officielle, intégrité vérifiée et version imprimée dans le journal. Un `brew install xcodegen` non figé est acceptable pour un prototype manuel, pas comme état final reproductible. Ne jamais versionner le `.xcodeproj` généré uniquement pour contourner ce point.

### 4. ASan

Créer d'abord un workflow `workflow_dispatch` sans calendrier. Qualifier le runtime avec un test témoin, puis exécuter :

```sh
swift test --package-path Packages/KyokashoKit \
  --disable-automatic-resolution --sanitize address
```

Si la durée ou la mémoire dépasse la capacité du runner standard, cibler d'abord `PageShiftTests`, `BackupRoundTripTests`, les conversions d'images OCR et les ponts MeCab/C++. Une fois deux ou trois exécutions stables obtenues, programmer une campagne hebdomadaire sur la branche par défaut. La campagne doit échouer sur tout rapport ASan et conserver uniquement le journal nécessaire, avec une rétention courte.

ASan couvre les accès CPU invalides du code instrumenté. Il ne valide ni les kernels Metal, ni la pression mémoire MLX, ni les cycles ARC, ni les fuites. `ASAN_OPTIONS=detect_leaks=1` ne doit être activé qu'après un test témoin prouvant la présence du runtime correspondant. ThreadSanitizer relève d'une campagne séparée.

### 5. MLX et assets réels

Séparer deux preuves :

1. **Compilation sans poids** sur runner GitHub standard lorsque `GLMOCRKit`, `project.yml`, `Package.resolved` ou les manifestes changent. Elle contrôle le graphe SwiftPM, les forks épinglés et le linkage.
2. **Inférence réelle** seulement via déclenchement manuel sur un runner qualifié disposant légalement des modèles et d'un corpus synthétique ou autorisé. Les sorties ne doivent pas contenir de page utilisateur, de prompt privé ou de poids.

La dépendance `mlx-swift-lm` est déclarée par branche `ipad-ios16` ; la reproductibilité dépend donc du `Package.resolved`. Toute modification de la révision des forks doit être un lot explicite avec examen des correctifs iOS 16, compilation générique et recette iPad ultérieure. Ne jamais exécuter `swift package update` pour faire passer la CI.

Le Mac GitHub ne remplace pas l'iPad pour Metal 3.0. Même une exécution avec `MLX_METAL_LANGUAGE_VERSION=30` utilise un compilateur plus récent et peut manquer une incompatibilité déjà observée sur iOS 16.

## Déclenchement et contrôles obligatoires

Architecture recommandée :

| Workflow logique | Événements | Contrôle obligatoire |
|---|---|---|
| Qualité | `pull_request`, push sur `main`, manuel | Oui |
| Swift Mac arm64 | `pull_request` de code, push sur `main`, manuel | Oui |
| Build iOS générique | `pull_request` touchant app/projet/packages, push sur `main`, manuel | Oui après qualification |
| ASan | Manuel, puis hebdomadaire sur `main` | Non au début ; obligatoire seulement quand stable |
| MLX réel | Manuel sur SHA approuvé | Non |

Éviter qu'un contrôle obligatoire soit porté uniquement par un workflow avec `paths`, car un workflow entièrement ignoré peut laisser un état attendu ambigu selon la protection de branche. Employer des noms de jobs stables et, si des jobs sont conditionnels, terminer par un petit job de synthèse toujours présent qui échoue lorsqu'un contrôle requis a échoué.

Ajouter `concurrency` par PR pour annuler les anciens commits, sauf pour une campagne manuelle dont les preuves doivent être conservées. Fixer un `timeout-minutes` par job. La compilation iOS et ASan doivent rester séparées afin qu'un dépassement de temps n'efface pas la preuve des tests rapides.

## Coûts et capacité

Le dépôt public bénéficie actuellement de minutes gratuites sur les runners GitHub standard. Ce point doit être revérifié si le dépôt devient privé. La tarification publiée au 25 octobre 2026 est de **0,062 USD par minute** pour un runner macOS standard hors quota, chaque job étant arrondi à la minute supérieure.

Le runner macOS arm64 plus grand (`macos-15-xlarge`, M2 Pro, 5 cœurs CPU, accélération GPU et 14 Go de RAM) coûte **0,102 USD par minute**, reste facturé pour un dépôt public et n'est disponible que dans les offres d'organisation éligibles. Il ne doit pas devenir la valeur par défaut sans mesure montrant que le runner standard est insuffisant.

Les artefacts et caches peuvent également être facturés au-delà des quotas. Au tarif publié, le stockage partagé des artefacts vaut 0,25 USD/Go/mois et le cache Actions 0,07 USD/Go/mois. Fixer une rétention courte, ne publier les journaux lourds qu'en cas d'échec et ne jamais mettre les modèles MLX/ONNX en cache Actions.

Commencer sans cache de compilation. Mesurer trois exécutions à froid. Si le téléchargement SwiftPM domine, introduire un cache limité aux téléchargements, avec une clé incluant macOS, arm64, version Xcode et hachage des deux `Package.resolved`. Ne pas partager un cache d'artefacts compilés entre branches non fiables.

## Risques de sécurité

- Garder `permissions: contents: read`, `persist-credentials: false` et chaque action tierce épinglée à un SHA complet vérifié.
- Utiliser `pull_request`, jamais `pull_request_target`, pour compiler le code proposé. Aucun secret ne doit être disponible à une PR externe.
- Ne pas interpoler directement titres, noms de branche ou corps de PR dans un script shell.
- Ne jamais téléverser `App/Config/Local.xcconfig`, `Secrets.plist`, PDF, dictionnaires, modèles, journaux privés, données restaurées ou chemins révélant les données de l'utilisateur.
- Traiter le code de PR comme non fiable. Il peut lire l'environnement du runner et modifier les fichiers produits pendant le job.
- Un runner auto-hébergé persistant ne doit pas exécuter les PR publiques. Si un Mac dédié est nécessaire aux modèles, limiter son workflow à `workflow_dispatch` sur un SHA approuvé, utiliser un compte isolé, nettoyer le workspace, interdire l'accès à l'iPad et aux données personnelles, et ne lui donner aucun secret de publication.
- Ne pas ajouter de signature, certificat Apple, jeton GitHub à droits d'écriture ou clé de release aux workflows de validation.
- Vérifier les changements de `Package.resolved` comme du code : URL, révision, fork attendu et justification. Les dépendances sont téléchargées pendant le build même avec une résolution figée.

## Ce que la CI ne peut pas confirmer

Les vérifications suivantes restent à faire sur l'iPad par NOxygen59, avec une copie sans valeur des données quand une opération est destructive :

- lancement et fonctionnement sous iOS 16.6.1 ;
- compilation JIT des kernels Metal 3.0 des forks MLX ;
- mémoire unifiée, déchargement des modèles, pression mémoire et jetsam ;
- qualité OCR, traduction et chat sur les modèles réellement installés ;
- PDFKit, PencilKit, gestes, rotation, double page et rendu ;
- ajout/décalage de pages sur une copie, reprise après interruption réelle et cohérence des annotations ;
- sauvegarde/restauration du conteneur réel, application arrêtée, sans toucher à l'unique bibliothèque ;
- installation TrollStore, entitlements, signature et `.tipa`, qui restent hors de la CI proposée.

## Plan d'implémentation pour un futur agent Codex

### Phase 0 — photographier l'état

1. Lire les instructions du dépôt et vérifier la branche cible.
2. Lister les workflows et les exécutions GitHub récentes ; noter SHA, durée, architecture, Xcode, Swift, tests et ignorés.
3. Vérifier les règles de protection de branche et le budget Actions sans les modifier.
4. Exécuter localement uniquement les contrôles légers nécessaires pour confirmer les commandes ; ne pas lancer de modèles.

**Sortie attendue :** tableau de référence daté, aucun changement de production.

### Phase 1 — fiabiliser les contrôles existants

1. Rendre explicite le calcul du diff pour les PR et les pushes groupant plusieurs commits.
2. Ajouter architecture et versions aux journaux Mac.
3. Ajouter annulation des runs obsolètes et délais cohérents.
4. Éliminer seulement la duplication Mac démontrée par les logs.
5. Conserver les noms de contrôles nécessaires à la protection de branche, ou préparer leur migration explicitement.

**Critère d'acceptation :** mêmes tests fonctionnels qu'avant, commandes visibles, résolutions inchangées, exécution verte sur une PR témoin.

### Phase 2 — ajouter la compilation iOS générique

1. Choisir et figer XcodeGen ; documenter provenance, version et intégrité.
2. Générer le projet dans le job, copier la résolution GLMOCRKit dans le workspace SwiftPM et construire pour `generic/platform=iOS` sans signature.
3. Vérifier le déploiement iOS 16.0 et l'absence de modification des résolutions.
4. Tester un échec volontaire sur une branche jetable afin de confirmer que le contrôle bloque réellement.

**Critère d'acceptation :** build Debug générique réussi sur arm64, aucun simulateur, aucune installation, aucun artefact de release.

### Phase 3 — qualifier ASan

1. Ajouter un workflow manuel et un témoin ASan hors code produit.
2. Exécuter les filtres PageShift, sauvegarde et frontières C/C++ ; élargir ensuite à la suite complète si le runner tient dans ses limites.
3. Documenter durée, RAM, ignorés et faux positifs éventuels.
4. Ajouter le calendrier seulement après plusieurs runs reproductibles.

**Critère d'acceptation :** le témoin est détecté lors de la qualification, puis les tests réels passent sans rapport ASan ; aucune affirmation sur LSan, Metal ou iPad.

### Phase 4 — qualifier MLX sans élargir la confiance

1. Ajouter la compilation de `GLMOCRKit` sans téléchargement de poids.
2. Vérifier que les révisions résolues correspondent aux forks attendus.
3. Décider séparément si un runner GPU ou auto-hébergé est justifié par un besoin mesuré.
4. Si oui, créer un protocole manuel avec corpus autorisé, sorties nettoyées et aucune PR non fiable.

**Critère d'acceptation :** compilation reproductible des forks épinglés ; les tests sans assets sont comptés comme ignorés ; aucune donnée utilisateur dans les logs.

### Phase 5 — rendre les contrôles obligatoires

1. Observer stabilité et durée sur plusieurs PR.
2. Activer uniquement les contrôles rapides, Swift et build iOS qualifiés dans la protection de branche.
3. Garder ASan programmé et MLX réel informatifs tant que leur fiabilité ou leur coût ne permet pas de bloquer chaque PR.
4. Mettre à jour `docs/CI-ET-LIVRAISON.md`, `docs/TESTS.md` et ce document avec les noms exacts des jobs et les preuves.

**Arrêt :** ne pas automatiser la release, la signature, la construction `.tipa`, l'installation ou l'essai iPad dans ce chantier.

## Sources externes à revérifier lors de l'implémentation

- [Runners hébergés par GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Images macOS arm64 et labels](https://github.com/actions/runner-images)
- [Logiciels de l'image macOS 15 arm64](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
- [Tarification des runners Actions](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- [Facturation et quotas Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Sécurisation des workflows](https://docs.github.com/en/actions/reference/security/secure-use)
- [XcodeGen et ses méthodes d'installation](https://github.com/yonaskolb/XcodeGen)

Ces pages sont temporelles. Le futur agent doit conserver dans sa PR les valeurs observées le jour de l'implémentation et signaler tout écart avec cette feuille de route.
