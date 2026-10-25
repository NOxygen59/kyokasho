<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Stratégie de tests et recette iPad

## Objectif

Éviter les pertes de données, préserver la lecture et rendre les corrections démontrables. Les tests Mac contrôlent les modules ; la compilation iOS contrôle les API et le linkage ; la recette de NOxygen59 contrôle l'app réelle sur iOS 16.6.1. Ces preuves sont complémentaires. Aucun simulateur ou appareil n'est lancé sans son accord.

## Tests existants

`Packages/KyokashoKit/Package.swift` déclare sept cibles, réparties dans 17 fichiers comportant 142 déclarations `func test` à la base auditée. Ce décompte statique ne mesure ni la couverture ni les tests réellement exécutés. GLMOCRKit déclare une cible supplémentaire avec deux fichiers d'essais de modèles. `project.yml` ne déclare pas de cible XCTest de l'app ni de tests UI.

| Cible | Exemples de comportements contrôlés | Limite |
|---|---|---|
| ReaderCoreTests | Réglages rétrocompatibles, repères, import/remplacement, décalage des pages, base | Pas l'orchestration multi-fichier de PageShift |
| OCRKitTests | Géométrie, services/cache, comparaison, lignes éditées, analyse, HTML | Vision dépend de l'environnement ; ne certifie pas les vrais scans |
| DictionaryKitTests | Import de corpus synthétique, recherche, variantes, rendu, champs | Dictionnaires personnels absents du dépôt |
| YomitanKitTests | Déconjugaison, kana, classes de caractères, furigana | Qualité linguistique globale non mesurée |
| ReviewKitTests | FSRS, stockage, modèles et export Anki | Import dans une app Anki réelle à vérifier séparément |
| ONNXOCRKitTests | Alignement et essais de moteurs | Modèles réels requis pour plusieurs scénarios |
| MorphologyKitTests | CSV et lectures MeCab/extraction UniDic | Dictionnaire/archive requis pour les essais réels |
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

1. **Préservation des données** : injection de panne à chaque étape PageShift, journal non inscriptible, espace disque insuffisant, redémarrage répété, sources avant/après. Vérifier PDF, tables, rapports, Markdown, cartes et absence de double décalage.
2. **Contrats v1.3** : langue Japonais/Auto, `图`/`図`, nombres/latin/formules intacts, lignes `edited` intactes, brut IA inchangé, suppression de traduction périmée et invalidation de vote.
3. **Chat** : « p. 6 » et numérotation romaine, page absente/hors limites, aucune lecture disponible, relance versus nouvelle question, isolation des conversations et modèles. Sortie attendue sur sélection des passages, sans dépendre d'un texte exact produit par un LLM.
4. **Géométrie** : pages tournées et de tailles différentes, coordonnées des annotations, double page et export ; vérifier les repères plutôt que seulement une capture d'écran.
5. **Concurrence/mémoire** : annulation pendant chargement/génération, fermeture de vue, changement rapide de document/modèle, fin de tâche ancienne après changement de page, retour bibliothèque puis inactivité. Voir [mémoire](MEMOIRE-ET-SANITIZERS.md).

Ajouter un test de régression ciblé avant chaque correction fonctionnelle. Utiliser des PDF synthétiques générés en temporaire et des jeux de textes dont les droits sont maîtrisés. Les tests de logique ne doivent pas dépendre d'un réseau ou d'un modèle de plusieurs Go.

Pour l'OCR réel, garder hors dépôt un corpus daté avec vérité terrain relue humainement : horizontal, vertical, petits caractères, tableaux, formules, pages tournées et scans dégradés. Mesurer CER, erreurs numériques et qualité de placement séparément ; un bon CER ne garantit pas une formule juste. Mesurer temps à froid/à chaud et pics mémoire par modèle. Fixer les seuils après une première mesure de référence, pas des pourcentages arbitraires.

## Recette iPad à remplir par NOxygen59

Préparer une copie sans valeur des données et noter version/build, iOS, modèle installé, mode diagnostic et espace libre. Pour chaque ligne : réussi/échoué/non essayé, date, observation, journal ou capture. « Non essayé » reste visible dans les notes de release.

| ID | Scénario | Résultat attendu |
|---|---|---|
| I01 | Import Fichiers puis Drive, Japonais et Auto | Livre ouvrable, langue conservée et traitement de fond cohérent |
| I02 | Simple/Double/Auto, rotation, zoom, doigt/Pencil/trackpad | Page/position cohérentes ; pas de panneau recouvrant le PDF |
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

Base : `16d2dd8`, Mac arm64, Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), cible package macOS 14. Le premier lancement sous sandbox échoue sur le cache compilateur ; un lancement avec accès aux caches autorisé a ensuite compilé les dépendances épinglées.

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
