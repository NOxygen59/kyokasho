<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Stratégie de tests et recette iPad

## Objectif

Éviter les pertes de données, préserver la lecture et rendre les corrections démontrables. Les tests Mac contrôlent les modules ; la compilation iOS contrôle les API et le linkage ; la recette de NOxygen59 contrôle l'app réelle sur iOS 16.6.1. Ces preuves sont complémentaires. Aucun simulateur ou appareil n'est lancé sans son accord.

## Tests existants

Au SHA `23d33c0ff70747ba7b47a7484c1e713ed0cd83c5` (25/10/2026), `Packages/KyokashoKit/Package.swift` déclare **neuf cibles de tests**, avec **163 déclarations `func test` dans 20 fichiers**. Ce relevé des sources n'est pas une nouvelle exécution. Les sept cibles / 142 tests du registre historique en bas de page décrivent la base avant les PR #2/#3. GLMOCRKit garde sa cible séparée de tests de modèles. `project.yml` ne déclare pas de cible XCTest de l'app ni de tests UI.

**Campagne en préparation : [QA-02 — recette iPad PageShift et sauvegarde](RECETTE-IPAD-QA-02.md).** Elle détaille le corpus synthétique à fabriquer, les gestes, les attentes, les conditions d'arrêt, les autorisations et les fiches GitHub. Aucun essai iPad ni build n'est effectué par cette préparation.

| Cible | Exemples de comportements contrôlés | Limite |
|---|---|---|
| ReaderCoreTests | Réglages rétrocompatibles, repères, import/remplacement, décalage des pages, base | Pas l'orchestration multi-fichier de PageShift |
| OCRKitTests | Géométrie, services/cache, comparaison, lignes éditées, analyse, HTML | Vision dépend de l'environnement ; ne certifie pas les vrais scans |
| DictionaryKitTests | Import de corpus synthétique, recherche, variantes, rendu, champs | Dictionnaires personnels absents du dépôt |
| YomitanKitTests | Déconjugaison, kana, classes de caractères, furigana | Qualité linguistique globale non mesurée |
| ReviewKitTests | FSRS, stockage, modèles et export Anki | Import dans une app Anki réelle à vérifier séparément |
| ONNXOCRKitTests | Alignement et essais de moteurs | Modèles réels requis pour plusieurs scénarios |
| MorphologyKitTests | CSV et lectures MeCab/extraction UniDic | Dictionnaire/archive requis pour les essais réels |
| PageShiftTests | 39 tests (27/10/2026) : reprise à 14 frontières, matrice de double interruption 14 × 13, décalages 0/1/2, SIGKILL à 9 frontières, journal ambigu/corrompu/modifié (S1, S2, S5), lien symbolique, PDF tiers, ajouts concurrents, erreurs SQL/fichiers, décalage unique ; cinq tests OCR tardif/concurrence/annulation/reprise/réactivité ; RET-048 corrigé (#74), S7 sert de test de régression | Adaptateurs Mac pour l'interface ; ni parcours UIKit ni coupure matérielle |
| BackupIntegrationTests | 1 test : vraies bases AppDatabase/ReviewStore, sauvegarde/restauration et réouverture en écriture | Conteneur synthétique Mac ; ni extraction ni réinstallation TrollStore |
| GLMOCRKitTests | Lecture Ovis/GLM/Qwen, vrais échantillons, traduction, chat, profil | Poids et corpus externes ; tests opt-in, pas une suite légère systématique |

## Exécution Mac reproductible

Sur un checkout disposant des dépendances épinglées :

```sh
mkdir -p work/test-results
swift test --package-path Packages/KyokashoKit \
  --disable-automatic-resolution > work/test-results/macos.log 2>&1
```

Conserver le code de sortie, le journal complet, le SHA et les versions Swift/Xcode. Une commande filtrée par `grep` ne suffit pas comme preuve ; un pipeline sans gestion des erreurs peut masquer un échec. Ne pas lancer `swift package update` pour résoudre un problème de compilation du test.

Pour cibler un scénario, ajouter `--filter ServiceTests` ou le nom d'une classe existante. Le filtrage d'exécution peut néanmoins compiler les autres cibles de test ; il ne contourne pas nécessairement un test qui ne compile plus. `--skip-build` exige un binaire construit à partir des mêmes sources et réglages.

Pour les essais MeCab/ONNX, renseigner les chemins d'assets extérieurs au dépôt via `KYOKASHO_UNIDIC`, `KYOKASHO_UNIDIC_ARCHIVE` ou `KYOKASHO_MODELS`. Un test signalé `XCTSkip` doit rester « ignoré : asset absent », jamais « modèle validé ». Ne pas télécharger des modèles silencieusement pour faire verdir une suite.

Pour une lecture MLX réelle déjà autorisée et équipée :

```sh
MLX_METAL_LANGUAGE_VERSION=30 \
KYOKASHO_MODELS=/chemin/externe/modeles \
KYOKASHO_SAMPLE_PDF=/chemin/externe/echantillon.pdf \
KYOKASHO_SAMPLE_PAGES=1,2 \
swift test --package-path Packages/GLMOCRKit \
  --disable-automatic-resolution --filter testRealSample
```

Ce sont des chemins à adapter, pas des assets fournis. `KYOKASHO_SAMPLE_PAGES` utilise des numéros de page destinés à cet essai ; `KYOKASHO_BENCH_PAGE` est un index dans le test de profil. Lire le test avant de comparer des résultats. Metal 3.0 sur Mac laisse subsister des écarts avec le compilateur de l'iPad.

### Procédure locale standard avant une PR

C'est la voie de preuve par défaut tant que GitHub Actions n'a pas de protection contre la facturation vérifiée (voir la politique « Zéro dépense » de [CI-ROADMAP.md](CI-ROADMAP.md)). Elle se lance à la main, sur le Mac de NOxygen59, dans un clone séparé, sur le SHA exact de la PR.

```sh
set -o pipefail
SHA=<sha-de-la-pr>
cd ~/Projets-iPad/kyokasho-preuves      # clone dédié, jamais le clone de travail
git fetch origin && git checkout --detach "$SHA"
git status --porcelain                   # doit être vide
mkdir -p ~/kyokasho-journaux/"$SHA"      # journaux hors dépôt
J=~/kyokasho-journaux/"$SHA"
sw_vers; uname -m; xcodebuild -version; swift --version

# 1. Documentation (toujours)
python3 scripts/check_documentation.py 2>&1 | tee "$J/doc.log"
# 2. Outil de sauvegarde (toujours)
python3 -m unittest discover -s tests -v 2>&1 | tee "$J/python.log"
# 3. Suite Swift (dès qu'un fichier Swift ou un manifeste change)
swift test --package-path Packages/KyokashoKit \
  --disable-automatic-resolution 2>&1 | tee "$J/swift.log"
# 4. Résolutions figées (après chaque commande Swift)
git diff --exit-code -- Packages/KyokashoKit/Package.resolved Packages/GLMOCRKit/Package.resolved
```

Selon le lot, on ajoute :
- la compilation iOS générique décrite dans [CI-ROADMAP.md](CI-ROADMAP.md) (« Compilation iOS générique sans installation ») si `App/`, `project.yml` ou les forks changent ;
- ASan (`--sanitize address`) pour du code C/C++, de la mémoire ou de la concurrence ;
- les essais MLX/ONNX réels ci-dessus, seulement s'ils sont autorisés et que les assets sont présents.

Relever le code de sortie de chaque commande. Avec `tee`, `set -o pipefail` le conserve. Résumer ensuite le tout dans la **fiche de preuve locale** de [CI-ROADMAP.md](CI-ROADMAP.md), en commentaire de la PR. Les journaux restent dans `~/kyokasho-journaux/`, hors du dépôt, et ne sont jamais publiés en entier.

## Couverture à ajouter par risque

1. **Préservation des données** : les PR #2/#3 couvrent plusieurs injections de panne, reprises répétées et la restauration synthétique ; le cadrage [#73](https://github.com/NOxygen59/kyokasho/issues/73) ajoute la sécurité du journal et la double interruption (section « PageShift — sécurité et reprise » ci-dessous). Restent à qualifier les parcours UIKit, l’espace réellement disponible, les copies volumineuses et le conteneur TrollStore ; ne pas présenter les tests Mac comme une validation iPad. Voir les limites de [PageShift](PHASE2-STOCKAGE.md) et de [sauvegarde](PHASE2-SAUVEGARDE.md).
2. **Contrats v1.3** : langue Japonais/Auto, `图`/`図`, nombres/latin/formules intacts, lignes `edited` intactes, brut IA inchangé, suppression de traduction périmée et invalidation de vote.
3. **Chat** : « p. 6 » et numérotation romaine, page absente/hors limites, aucune lecture disponible, relance versus nouvelle question, isolation des conversations et modèles. Sortie attendue sur sélection des passages, sans dépendre d'un texte exact produit par un LLM.
4. **Géométrie** : pages tournées et de tailles différentes, coordonnées des annotations, double page et export ; vérifier les repères plutôt que seulement une capture d'écran.
5. **Concurrence/mémoire** : annulation pendant chargement/génération, fermeture de vue, changement rapide de document/modèle, fin de tâche ancienne après changement de page, retour bibliothèque puis inactivité. Voir [mémoire](MEMOIRE-ET-SANITIZERS.md).

Ajouter un test de régression ciblé avant chaque correction fonctionnelle. Utiliser des PDF synthétiques générés en temporaire et des jeux de textes dont les droits sont maîtrisés. Les tests de logique ne doivent pas dépendre d'un réseau ou d'un modèle de plusieurs Go.

Pour l'OCR réel, garder hors dépôt un corpus daté avec vérité terrain relue humainement : horizontal, vertical, petits caractères, tableaux, formules, pages tournées et scans dégradés. Mesurer CER, erreurs numériques et qualité de placement séparément ; un bon CER ne garantit pas une formule juste. Mesurer temps à froid/à chaud et pics mémoire par modèle. Fixer les seuils après une première mesure de référence, pas des pourcentages arbitraires.

## Recette iPad à remplir par NOxygen59

Pour PageShift et la sauvegarde (I03/I08/I09/I11/I12), suivre d’abord [QA-02](RECETTE-IPAD-QA-02.md), qui permet le niveau A sur l’installation existante avec les précautions A0 et le risque de perte accepté par NOxygen59 le 25/10/2026 ; le niveau B reste bloqué jusqu’à qualification et accords distincts. La grille suivante reste le catalogue général, pas une autorisation de tout essayer. Préparer uniquement des données synthétiques et noter version/build affichés, SHA source externe et SHA-256 du `.tipa`, iOS, modèle installé, mode diagnostic et espace libre. Pour chaque ligne : réussi/échoué/non essayé, date, observation, journal ou capture. « Non essayé » reste visible dans les notes de release.

| ID | Scénario | Résultat attendu |
|---|---|---|
| I01 | Import Fichiers puis Drive, Japonais et Auto | Livre ouvrable, langue conservée et traitement de fond cohérent |
| I02 | « Page simple » / « Double page » / « Automatique selon l'orientation », rotation, zoom, doigt/Pencil/trackpad | Page/position cohérentes ; pas de panneau recouvrant le PDF |
| I03 | Dessin, surlignage, note, repère ; fermeture/réouverture | Données conservées sur la bonne page |
| I04 | PDF texte et scan image ; furigana page/panneau | Texte exploitable, lectures et emplacements vérifiés visuellement |
| I05 | Relecture Ovis, correction manuelle, acceptation globale | Retouche protégée, vote actualisable, traduction périmée retirée |
| I06 | Question ciblée « p. 6 », page non lue, changement de conversation | Source exacte ou absence indiquée ; pas de confusion de livre |
| I07 | Chaque modèle de chat installé, dont Qwen3.5 séparément | Charge, répond, s'arrête ; qualité et mémoire mesurées |
| I08 | Export PDF/annoté/Markdown/PNG/Anki sur petit corpus | Résultats ouverts ailleurs, bon ordre, notes et caractères vérifiés |
| I09 | Ajout en fin puis avant le livre, sur copie | Total exact, repères/notes/OCR/cartes sur les bonnes pages |
| I10 | Effacement cache général puis opération OCR distincte | Données conservées selon l'avertissement propre à chaque action |
| I11 | Lecture répétée, annulation, retour bibliothèque, arrière-plan | Pas de crash ; tâches et mémoire explicables après stabilisation |
| I12 | Sauvegarde/restauration par méthode qualifiée | Corpus et relations retrouvés ; limites consignées |

Ne pas provoquer une interruption destructive sur l'unique bibliothèque de l'utilisateur. Les tests automatisés de panne doivent précéder la recette de reprise.

## Registre des preuves — 25 octobre 2026

Base : `d866319`, Mac arm64, Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), cible package macOS 14. Le premier lancement sous sandbox échoue sur le cache compilateur ; un lancement avec accès aux caches autorisé a ensuite compilé les dépendances épinglées.

**Avant correction du test :** `swift test --disable-automatic-resolution` échoue à la compilation, car `ServiceTests.testCacheAndEngines` lit deux fois `.ocrCacheStats().pages` alors que l'API renvoie `(bytes, results)`. Aucun résultat d'exécution de suite ne découle de cet échec.

**Correction limitée :** ces deux références de test deviennent `.results`, en conservant les valeurs attendues 1 et 0 ; le code produit n'est pas modifié. La relance se termine avec le code de sortie 0 : **142 tests comptabilisés, dont 7 ignorés et 135 exécutés sans échec**.

| Cible | Total | Ignorés | Échecs |
|---|---:|---:|---:|
| YomitanKitTests | 10 | 0 | 0 |
| ReviewKitTests | 24 | 0 | 0 |
| ReaderCoreTests | 28 | 0 | 0 |
| ONNXOCRKitTests | 8 | 5 | 0 |
| OCRKitTests | 47 | 0 | 0 |
| MorphologyKitTests | 3 | 2 | 0 |
| DictionaryKitTests | 22 | 0 | 0 |

Les cinq essais de modèles ONNX (DE-GAN, mise en page, NDLOCR, PP-OCR horizontal/vertical), la lecture MeCab contextuelle et l'extraction UniDic sont ignorés faute d'assets configurés. Les messages Swift Testing « 0 tests » additionnels ne remplacent pas ces résultats XCTest. Le journal complet a été conservé comme pièce locale de l'intervention, hors dépôt public.

Contrôles documentaires : 49 liens locaux examinés sans erreur ; diff sans erreur d'espacement ; YAML du workflow lisible ; vérificateur essayé sur un lien valide, un exemple dans un bloc de code et un lien cassé volontairement (rejeté). Les deux `Package.resolved` restent identiques à la base. L'exécution distante du workflow, après ouverture de la PR, doit être distinguée de ces contrôles locaux.

App iOS complète : non recompilée par ce lot. GLMOCRKit avec poids : non exécuté. Recette iPad : non exécutée. ASan/LSan de l'app : non exécutés. Aucun statut historique n'est promu au rang de nouvelle validation.


## PageShift — sécurité et reprise (27 octobre 2026, cadrage #73)

Base : `main` `85839f0`. Fichier `Packages/KyokashoKit/Tests/PageShiftTests/PageShiftSafetyTests.swift`, extension de `PageShiftRecoveryTests` (même harnais `withFixture` : dossier temporaire, `PageShift.support` redirigé, aucune bibliothèque réelle).

| Code | Test | Ce qui est vérifié |
|---|---|---|
| S1 | `testS1TamperedJournalDocumentIdIsRefusedWithoutWriting`, `testS1HostileDocumentIdIsRefusedBeforeAnyCopy` | `documentId` = `../…`, `a/b`, `..`, `.`, vide : blocage, journal et fichiers inchangés (inventaire SHA-256), puis reprise normale avec le journal authentique |
| S2 | `testS2TamperedJournalTransactionIsRefusedWithoutWriting` | `transaction` = `../../…`, `abc`, absente ; leurre d'espace de travail authentique hors du conteneur, intact |
| S3 | `testS3SymlinkInAIReadingsStopsTheAdditionAndLeavesTargetIntact` | lien symbolique dans les lectures IA : refus, cible hors conteneur intacte |
| S4 | `testS4OutOfRangeAIReadingStopsTheAddition`, `testS4UnusualAIReadingNamesShiftOnlyTheTrailingPageNumber` | `x-9.md` refusé ; `a-b-1.md` → `a-b-3.md`, `x--1.md` → `x--3.md` (le tiret n'est pas un signe), `notes.md` et `data.json` copiés tels quels |
| S5 | `testS5TamperedCardPagesInJournalAreRefused` | pages de cartes hors plage dans le journal : blocage, FSRS intact |
| S6 | `testS6ThirdPDFBeforeRecoveryIsNeverOverwritten` | troisième PDF avant la reprise : jamais écrasé, base non décalée |
| S7 | `testS7ReportPageOutsideTheDocumentStopsTheAddition` | rapport portant une page 7, 2 ou −1 sur un document de 2 pages : ajout arrêté avant le journal, rapport, base, PDF et cartes intacts. Test de régression de **RET-048** ([#74](https://github.com/NOxygen59/kyokasho/issues/74)), corrigé le 27/10 ; marqué `XCTExpectFailure` jusqu'au correctif |
| R1 | `testR1DoubleInterruptionMatrix` | interruption au point a, reprise interrompue au point b, puis reprise libre : 182 couples (14 × 13 ; `journal.after` n'est jamais traversé par la reprise), chaque seconde interruption prouvée atteinte et laissant le journal (≈ 7 s) |
| R2 | `testR2BareDocumentInterruptedAtEveryBoundary` | document sans rapport, brouillons ni lectures IA, 14 frontières |
| R3 | `testR3EveryOffsetInterruptedAtEveryBoundary` | décalages 0, 1, 2 × 14 frontières |
| R4 | `testR4ConcurrentAdditionsOnTheSameDocumentApplyOnce` | deux ajouts simultanés : un seul aboutit, l'autre refusé avec l'erreur exacte « déjà en cours », un seul décalage ; stable 10/10 |
| R5 | `testR5PendingJournalOfOneDocumentBlocksAnotherUntilRecovered` | journal du livre A en attente : B refusé, puis accepté après la reprise de A |
| R6 | `testR6OrphanWorkspaceBeforeJournalIsNeitherReusedNorBlocking` | copie de travail orpheline : ni bloquante, ni réutilisée, ni modifiée |
| R7 | `testR7LeftoverPDFInstallFileIsReplacedOnRecovery` | fichier `.page-shift-<UUID>.pdf` resté : remplacé, PDF final = `newHash` |
| R8 | `testR8AbruptProcessDeathAtRemainingBoundaries` | SIGKILL à `journal.after`, `report.after`, `drafts.after`, `cards.before`, `complete.before` (les 4 autres frontières sont déjà dans `testAbruptProcessDeathAfterCommittedEffects`) |

**Résultats sur ce Mac (macOS 27.0, Swift de Xcode), code non modifié, après la revue de Codex :**

- `swift test --filter PageShiftTests` : 39 tests, 0 échec (S7 en échec attendu), 14,2 s.
- Après le correctif de RET-048 (garde de plage du rapport) : 39 tests, 0 échec, **aucun échec attendu**, 13,7 s ; ASan 39 tests, 0 échec, 22,9 s ; suite complète 218 tests, 7 ignorés, 0 échec. Garde retirée temporairement : S7 échoue.
- `swift test --scratch-path .build-asan --sanitize address --filter PageShiftTests` : 39 tests, 0 échec, aucun rapport ASan, 23,8 s.
- `swift test` (suite complète `KyokashoKit`) : 218 tests exécutés, 7 ignorés (modèles ONNX/UniDic absents), 0 échec.

**Puissance des tests (mutations temporaires de `PageShift.swift`, annulées) :**
- Contrôle du lien symbolique retiré : S3 échoue.
- Contrôle UUID de `transaction` retiré : S2 échoue.
- Contrôle de plage de `cardPages` retiré : S5 échoue.
- Garde de concurrence `applyingDocuments` retiré : R4 échoue.
- Panne étrangère ajoutée au scénario S7 : S7 échoue (elle n'est pas absorbée par l'échec attendu).
- `safeName` neutralisé : S1 **reste vert**, car un second rempart arrête l'opération avant toute écriture (empreinte du PDF ou document absent de la base). S1 vérifie donc le résultat (rien n'est écrit), pas ce contrôle précis.

Non couvert : parcours UIKit, espace disque réel, gros PDF, conteneur TrollStore, iPad.

## QA-02 — vérifications de préparation du 25 octobre 2026

Base de travail : `23d33c0ff70747ba7b47a7484c1e713ed0cd83c5`, worktree dédié `codex/qa02-recette-ipad`. Mac local, macOS 27.0.1 (26A434), Python 3.13.13. La PR ne modifie que des documents Markdown.

| Contrôle | Nature de la preuve | Résultat |
|---|---|---|
| `python3 -m unittest discover -s tests -v` | Exécution locale sur cette base ; conteneurs temporaires synthétiques | 16 réussis, 0 échec, 0 ignoré, code 0 |
| Inventaire des cibles et méthodes Swift | Lecture des sources au SHA ci-dessus | 9 cibles / 163 méthodes ; dont 20 PageShift et 1 restauration |
| Correspondance recette / interface | Lecture de AddPagesView, StudyPanel, ReaderController et guides | Ajout par blocs avant/après ; refus de lecture IA active distinct de l'attente OCR |
| `python3 -I scripts/check_documentation.py` et `git diff --check` | Contrôles locaux après édition | 139 liens, 0 erreur ; diff sans erreur, codes 0 ; [PR #7](https://github.com/NOxygen59/kyokasho/pull/7) |

Les 20 tests PageShift (également sous ASan) et le test de restauration Swift ont des preuves historiques dans les PR [#2](https://github.com/NOxygen59/kyokasho/pull/2) et [#3](https://github.com/NOxygen59/kyokasho/pull/3). **Swift/ASan ne sont pas relancés pour ce lot documentaire** ; leurs résultats antérieurs ne sont pas des résultats du présent checkout. Les 7 tests sans modèles ONNX/UniDic restaient ignorés dans la suite historique. Aucun téléchargement d'asset ni lecture de bibliothèque personnelle.

Non exécutés : build iOS, simulateur, appareil, MLX/Metal, LSan, extraction/restauration TrollStore, scénario manuel QA-02. GitHub Actions désactivé : réglage `enabled: false` relu le 25/10 avant publication ; aucun workflow utilisé ou lancé. Les risques et le tableau de résultats vierge sont dans la [recette QA-02](RECETTE-IPAD-QA-02.md).


### Correction documentaire après revue indépendante

La [revue de Claude](https://github.com/NOxygen59/kyokasho/pull/7#issuecomment-6397411518) a été validée par NOxygen59 le 25/10/2026. Le niveau A admet désormais l'installation existante avec risque de perte accepté et PDF synthétiques `QA02-…`, sans exiger une seconde app. L'accord ne couvre pas B : extraction/restauration TrollStore restent bloquées jusqu'à qualification et autorisations distinctes.

La recette compare « Page simple » et « Double page » ; l'égalisation des hauteurs est automatique, sans interrupteur. Elle donne le chemin exact de « Lire les nouvelles pages avec OvisOCR2 » et explique son arrêt temporaire pour éviter les lectures déclenchées après import/ouverture/ajout. Le parcours d'export comprend « Tout le document », « Exporter » puis « Partager <nom du fichier> ».

Diagnostic facultatif : **Réglages → Aide et informations → Aide au diagnostic → Mode diagnostic**. Son activation enrichit le journal sans nouvel indicateur dans le lecteur ; les erreurs sont toujours notées. Sur l'installation existante, le journal peut inclure des données personnelles antérieures : aucun partage brut.

La future build sera identifiée extérieurement par le SHA source et le SHA-256 du `.tipa`, associés au fichier effectivement sélectionné lors de l'installation. L'écran affiche seulement version/build ; `1.3 (40)` ne distingue pas la release historique d'une nouvelle compilation. Aucun changement de numéros sans autorisation. Contrôles de cette révision : liens documentaires et diff local, résultats exacts dans la réponse de Codex sur la PR #7. Les résultats Python du premier lot restent historiques et ne sont pas présentés comme relancés.
