<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Plan directeur — professionnalisation de Kyōkasho

> **Point d'entrée de pilotage pour les humains et agents IA.** Ce fichier suit la transformation *technique* du projet, pas le backlog de fonctionnalités. Il n'est **pas** une autorisation d'implémenter, fusionner, publier ou modifier les données. Lire [AGENTS.md](../AGENTS.md) avant toute action.
>
> **Dernier instantané vérifié : 27 octobre 2026, après la recette 1.3.2.** `main` à `738dceb7fd09ccfcb1b9feb454c1d695d2658d9d` (fusion de #59), avant la fusion de cette mise à jour (#62). Les PR #8 à #10, #25, #27 à #33 et #56 à #59 sont fusionnées. Le [registre des retours iPad](RETOURS-IPAD.md) contient **RET-001 à RET-042** et fait foi. La build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e` a été validée par NOxygen59 **avec limites** : RET-010, RET-011 et RET-012 **confirmés iPad** (Issues #13, #14, #15 fermées) ; deux nouveaux retours ouverts, RET-041/[#60](https://github.com/NOxygen59/kyokasho/issues/60) et RET-042/[#61](https://github.com/NOxygen59/kyokasho/issues/61). **Aucune release publiée.** **GitHub Actions reste désactivé** (CI-0). Ne pas considérer cet instantané comme actuel sans interroger GitHub.

## 1. Utilisation par un nouvel agent (obligatoire)

1. Vérifier sur GitHub la branche `main`, son SHA, les PR, les Issues et leurs contrôles, ainsi que la présence des documents cités. Ne pas déduire l'état actuel de cet instantané.
2. Lire `AGENTS.md` (Claude Code le charge via `CLAUDE.md`), ce plan, la [collaboration entre agents](GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex), [la feuille de route produit](FEUILLE-DE-ROUTE.md), l'[index documentaire](INDEX.md) et les documents techniques du domaine touché.
3. Comparer chaque statut ci-dessous aux preuves GitHub et aux retours d'essais iPad. Documenter les divergences, sans les résoudre arbitrairement.
4. Choisir **une seule tâche débloquée** par mission. Avant de coder, préciser objectif, périmètre, dépendances, invariants, tests, critère d'acceptation et autorisation requise.
5. Travailler sur branche/PR dédiée ; ne pas fusionner, changer la visibilité, créer une release ou toucher aux données personnelles sans accord explicite.
6. À la fin : mettre à jour les lignes touchées, leurs preuves (PR/commit/tests) et ce « point de reprise » ; déclarer les contrôles **non exécutés**.

**Hiérarchie des preuves :** état GitHub actuel et code au SHA étudié pour l'implémentation ; tests et artefacts datés pour la vérification ; essais documentés sur l'iPad pour l'expérience réelle ; guides et historiques pour les intentions. Une affirmation d'agent ne suffit pas.

**Statuts par axe** : préparation (`prévu / en cours / bloqué`), intégration (`PR / fusionné`), validation (`Mac vérifié / iOS compilé / iPad confirmé / non essayé`). Ne jamais compresser tous ces axes en un unique « terminé ».

## 2. Contrat produit à préserver

- Application personnelle de lecture et d'étude de PDF japonais ; cible concrète : **iPad Pro M1, iOS 16.6.1, TrollStore**. Déploiement déclaré : iOS 16.0 minimum.
- PDF et données originales à préserver ; éviter toute modification destructive, surtout notes, encre, repères, corrections OCR, cartes FSRS et lectures IA.
- Les tests Mac, une compilation générique iOS et les retours iPad **ne sont pas interchangeables**.
- MLX/Metal : forks `ipad-ios16` et dépendances épinglées ; pas de remplacement opportuniste.
- Pas de simulateur, installation appareil, modification de version, release ou fusion implicite.
- Le dépôt est **public** au relevé du 25/10 (alors que [la feuille de route](FEUILLE-DE-ROUTE.md) § 0 le dit « privé ») ; la décision de visibilité appartient au propriétaire. Ne jamais publier des PDF, secrets, logs bruts ou jeux d'essai privés.

## État actuel au 27 octobre 2026

| Niveau | Éléments |
|---|---|
| **Terminé et confirmé** | Socle documentaire et gouvernance fusionnés ; PR #8 à #10, #25, #27 à #33 et #56 à #59 fusionnées ; RET-008 et RET-009 confirmés iPad (1.3.1 (41), puis sans régression en 1.3.2 (42)) ; RET-010, RET-011 et RET-012 confirmés iPad en 1.3.2 (42) |
| **En validation** | RET-001, RET-002, RET-003 et RET-006 : correctifs présents dans les builds locales, sans scénario dédié dans les recettes 1.3.1 et 1.3.2 |
| **Ouvert** | Retours marqués « rapporté » dans [RETOURS-IPAD.md](RETOURS-IPAD.md), ainsi que DATA-01, DATA-02, DATA-03, QA-03, PERF-01, MAINT-01 et SEC-01 selon leurs preuves manquantes |
| **Conception seulement** | RET-034 (suppression de pages), RET-036 (cloud), RET-040 et PORT-01 (version Mac), DIAG-01 ; aucune implémentation autorisée par ce classement |

Le registre iPad porte le détail par retour. Cette vue indique seulement le niveau de maturité et ne remplace ni les Issues ni les preuves.

## 3. Registre des chantiers de professionnalisation

**Code de statut de cette table :** « fusionné » n'est **pas** « testé iPad » ; « à valider iPad » n'est **pas** « testé iPad ». Les tâches nouvelles ne sont que **proposées**, jamais automatiquement autorisées.

| ID | Chantier | Situation au relevé | Preuve / source | Prochaine condition de clôture |
|---|---|---|---|---|
| GOV-01 | Documentation, architecture, contribution, tests | **Fusionné** le 25/10 (commit de fusion `92a0315`) ; contrôle `Documentation` réussi sur `main` | [PR #1](https://github.com/NOxygen59/kyokasho/pull/1) ; [INDEX.md](INDEX.md) | Clos pour l'intégration ; tenir les guides à jour à chaque PR |
| GOV-02 | Plan directeur de professionnalisation (ce fichier) | **Fusionné** le 25/10 (`ee07c55`) ; mise à niveau au 27/10 préparée dans une PR documentaire séparée, sans changement applicatif | [PR #4](https://github.com/NOxygen59/kyokasho/pull/4) ; ce fichier | Fusionner la mise à niveau seulement après relecture ; continuer à actualiser le plan quand un chantier évolue |
| GOV-03 | Consolidation : instructions des agents, publication du plan CI, contrôle des documents obligatoires | **Fusionné** le 25/10 (`f76d9f6`) ; contrôle `Documentation` réussi sur `main`. Contenu : `AGENTS.md` commence par l'état GitHub et ce plan ; `docs/CI-ROADMAP.md` publié ; `scripts/check_documentation.py` vérifie aussi les documents et renvois obligatoires | [PR #5](https://github.com/NOxygen59/kyokasho/pull/5) (branche `docs/gouvernance-ci-roadmap`) | Clos pour l'intégration |
| GOV-04 | Protocole Claude / Codex, documentation du code, gabarits de PR et d'Issue, politique « Zéro dépense » | **Fusionné le 25/10/2026** (`f83aec8`), vérifié lors de QA-02 ; revue de Codex reçue (2 remarques, traitées) : protocole dans [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex) (autorisations de NOxygen59 valables dans un chat et consignées, commentaires signés [Claude]/[Codex]), règles de documentation dans [CONTRIBUTING.md](../CONTRIBUTING.md), `CLAUDE.md` qui importe `AGENTS.md`, gabarits `.github/`, politique « Zéro dépense » et tests locaux dans [CI-ROADMAP.md](CI-ROADMAP.md) et [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | [PR #6](https://github.com/NOxygen59/kyokasho/pull/6) (branche `claude/collaboration-agents-ci-gratuite`) | Intégration close ; QA-02 reprend le gabarit de PR et fournit la preuve locale |
| DATA-01 | Reprise idempotente d'ajout de pages / PageShift | **Fusionné** le 25/10 (`a016091`) ; `Stockage Mac` réussi sur `main` après #1+#2 et après #1+#2+#3 ; **non essayé sur iPad** | [PR #2](https://github.com/NOxygen59/kyokasho/pull/2) ; [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md) ; runs `40152364389`, `40152582505` | Recette iPad sur copie : OCR concurrent, annotations, gros PDF |
| DATA-02 | Sauvegarde et restauration hors ligne | **Fusionné** le 25/10 (`c2b1b29`) ; `Sauvegarde synthétique` réussi sur `main` ; **restauration TrollStore/iPad non démontrée** | [PR #3](https://github.com/NOxygen59/kyokasho/pull/3) ; [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md) ; run `40152580509` | Qualifier extraction/restauration sur iPad avec une bibliothèque jetable avant tout usage réel |
| QA-01 | Tests de logique et stockage | Socle de stockage fusionné et testé sur Mac ; les PR récentes documentent leurs preuves locales séparément. Preuve déclarée sur l'assemblage local des trois PR #31 → #32 → #57 (`aeb8d01`) : 188 tests Swift réussis, 7 ignorés, 16 Python, documentation sans erreur et compilation iOS générique réussie. **Ce résultat ne valide ni l'iPad, ni MLX/Metal.** | PR #2/#3 ; [TESTS.md](TESTS.md) ; preuves des PR #31/#32/#57 | Maintenir les tests ciblés par correction ; relever explicitement les ignorés et réserver les scénarios matériels à l'iPad réel |
| CI-01 | Automatisation CI | **GitHub Actions désactivé le 25/10/2026** (décision CI-0 de NOxygen59, vérifiée via l'API : `enabled: false`). Les trois workflows (`documentation.yml`, `storage.yml`, `backup.yml`) restent versionnés mais inactifs. Politique « Zéro dépense » (GOV-04). **Tests exécutés localement** sur le Mac de NOxygen59 et documentés dans chaque PR par une fiche de preuve | [CI-ROADMAP.md](CI-ROADMAP.md) ; [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | CI-G (script local de fiche de preuve) sur accord ; réactivation d'Actions seulement par NOxygen59, après protection vérifiée et autorisation par workflow |
| QA-02 | Recette iPad par version | Recette fusionnée avec la [PR #7](https://github.com/NOxygen59/kyokasho/pull/7) (`431f1c6`). Registre **RET-001 à RET-042**. Build locale 1.3.1 (41) : RET-008/009 confirmés. Build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e` : RET-010/011/012 **confirmés iPad**, régressions rapides OK, nouveaux RET-041 et RET-042. DATA-01/DATA-02/DATA-03/PERF-01 restent sans validation appareil complète. | [RETOURS-IPAD.md](RETOURS-IPAD.md) ; [RECETTE-IPAD-QA-02.md](RECETTE-IPAD-QA-02.md) ; Issues [#60](https://github.com/NOxygen59/kyokasho/issues/60), [#61](https://github.com/NOxygen59/kyokasho/issues/61) | Prochaine candidate seulement pour un nouveau lot autorisé ; ne fermer les Issues qu'après résultat consigné |
| DATA-03 | Géométrie annotations/export après égalisation | Risque identifié, **non clos** | [AUDIT-V1.3.md](AUDIT-V1.3.md) ; [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) | Tests pages tournées et tailles mixtes + validation iPad |
| QA-03 | Contrats OCR, japonais, chat et citations de pages | Tests existants, couverture supplémentaire proposée | [TESTS.md](TESTS.md), [ARCHITECTURE-LECTURE.md](ARCHITECTURE-LECTURE.md) | Tests ciblés des corrections manuelles, langues, invalidations et requêtes « p. 6 » |
| PERF-01 | Profilage mémoire/performance | Procédures documentées ; **pas de campagne globale iPad/MLX ou LSan réussie attestée** | [MEMOIRE-ET-SANITIZERS.md](MEMOIRE-ET-SANITIZERS.md) | Baselines froid/chaud ; instruments compatibles ; vérifier Swift ARC, MeCab, ONNX et Metal séparément |
| MAINT-01 | Nettoyage et modularisation progressifs | Dix pistes classées, désormais sur `main` ; **pas de nettoyage général réalisé** | [PHASE2-NETTOYAGE.md](PHASE2-NETTOYAGE.md) | Une correction ciblée par PR, test avant/après, preuve d'absence de régression |
| DIAG-01 | Centre de tests guidés sur iPad / Diagnostic 2.0 | **Idée proposée, non implémentée et non approuvée** | Discussion de conception ; aucun commit revendiqué | Spécification privacy-first, faisabilité, prototypes limités ; résultats humain/automate distincts |
| SEC-01 | Confidentialité, licences, visibilité, protection de `main` | Dépôt **public** ; `main` **sans protection de branche** ; divergence avec la feuille de route (« privé ») | État GitHub au 25/10 ; [AUDIT-V1.3.md](AUDIT-V1.3.md) | Décision du propriétaire sur la visibilité et la protection, inspection des données publiques, garde-fous et licences |
| OPS-01 | Gouvernance de PR/release, traçabilité et ADR | Guides fusionnés avec #1 ; fusions #1→#3 faites PR par PR avec revérification de `main` | [CONTRIBUTING.md](../CONTRIBUTING.md), [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) | Gabarits utiles, statut sur chaque PR, liens exigences→tests→résultats |
| PORT-01 | Application macOS (.app/.dmg) | **Option de produit, non démarrée** ; packages macOS ≠ app macOS | `Packages/KyokashoKit/Package.swift`, `project.yml` | Décision produit + étude Catalyst/natif séparée, sans altérer la cible iPad |

Les chantiers n'ont **pas** d'avancement en pourcentage : cela produirait une précision trompeuse. L'ordre n'est pas une promesse de calendrier.

## 4. Dépendances et ordre suggéré

1. ~~**Vérifier le lot intégré et faire la recette iPad**~~ : **fait le 27/10** — `main` `242be8f` vérifié (188 Swift, 16 Python, 2 JS, documentation, iOS générique), candidate locale 1.3.2 (42), recette de NOxygen59 validée avec limites.
2. **Retours ouverts du lot** : RET-041 (#60, clignotement en haut à gauche au changement de page) et RET-042 (#61, fiabilité du survol avec Maj) à cadrer avec leurs informations manquantes, puis à prioriser avec le reste du registre ; aucun correctif autorisé par cette ligne.
3. **Données avant refactorisation** : exécuter sur corpus synthétique les recettes DATA-01 (PageShift), DATA-02 (sauvegarde/restauration TrollStore) et DATA-03 (géométrie annotations/export). Aucun essai de restauration sur l'unique bibliothèque réelle.
4. **Performance et énergie** : mesurer PERF-01 et RET-017 avant de proposer une optimisation MLX/Metal. Les procédures ASan/diagnostic restent distinctes des preuves iPad.
5. **Maintenabilité** : une correction ou extraction ciblée par PR, avec test avant/après ; aucune réécriture générale.
6. **Backlog produit** : les 40 retours restent priorisés dans le registre et leurs Issues. Les fonctions, le cloud et la version Mac ne deviennent pas autorisés par leur seule présence.
7. **CI et sécurité** : Actions reste désactivé au titre de CI-0. SEC-01 (visibilité et protection de `main`) demeure une décision du propriétaire.

Une anomalie critique démontrée peut modifier cet ordre, avec justification enregistrée. Les chantiers n'ont pas de pourcentage d'avancement : intégration, tests Mac, compilation iOS et validation iPad restent des axes séparés.

## 5. Registre des validations et limites

- **État GitHub du 27/10, après recette 1.3.2** : `main` `738dceb7fd09ccfcb1b9feb454c1d695d2658d9d` (fusion de #59), avant la fusion de #62. Issues #11 à #15 fermées après confirmation iPad ; #60 et #61 ouvertes.
- **Contrôles du `main` fusionné `242be8f`** (Mac arm64, Xcode 27.1, Swift 6.4) : 188 tests Swift réussis, 0 échec, 7 ignorés ; 16 Python ; 2 JS ; documentation 0 erreur ; compilation iOS générique avec dépendances figées réussie ; `Package.resolved` inchangés.
- **Candidate locale 1.3.2 (42), recette NOxygen59 du 27/10** : Build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e`. Installation et données OK ; RET-010, RET-011 et RET-012 confirmés ; régressions rapides OK ; résultat général « validée avec limites » ; nouveaux retours RET-041 et RET-042. Aucune release publiée.
- **Build locale 1.3.1 (41), recette NOxygen59 du 27/10** : candidate non publiée, source locale `e3232d5` (`main` `ec51cb8` + version/build), SHA-256 `c5b31ced0e89ee30cac80c0ff55cd3f21e4dcef712469b9a61397e6946bf9016`. Installation/version/données observées OK ; RET-008 et RET-009 confirmés ; RET-011 partiel ; RET-012 précisé vers un stockage par document.
- **Preuves avant fusion** (historique) : assemblage local #31 → #32 → #57 à `aeb8d01` : 188 Swift, 7 ignorés, 16 Python, documentation et iOS générique réussies ; correction finale #57 `68274a1` : 184 Swift, 16 Python, 2 JS, documentation et iOS générique réussies.
- **Suivi produit** : [RETOURS-IPAD.md](RETOURS-IPAD.md) contient RET-001 à RET-042 et la matrice O01–O13 / P01–P10. Les Issues et PR liées portent le détail ; le plan directeur conserve seulement l'état des chantiers.


- **Reprise de la PR #7 après revue (25/10)** : [revue de Claude](https://github.com/NOxygen59/kyokasho/pull/7#issuecomment-6397411518) validée par NOxygen59 ; instructions corrigées contre le code au SHA `f83aec8`. Aucune logique ni configuration changée. Contrôles documentaires locaux consignés en réponse dans la PR ; aucun nouvel essai de sauvegarde, Swift ou iPad.

- **Préparation QA-02 (25/10, base `f83aec8`)** : 16 tests Python synthétiques locaux réussis (0 échec/ignoré), inventaire de 20 tests PageShift et 1 test Swift de restauration vérifié dans les sources ; aucune nouvelle exécution Swift/ASan. Contrôles documentaires et diff consignés dans la PR dédiée. [Recette](RECETTE-IPAD-QA-02.md) et fiches GitHub prêtes ; corpus PDF à fabriquer hors dépôt ; aucun résultat iPad revendiqué.

- **Intégration du 25/10 (GitHub)** — fusions par commit de fusion, branches conservées :
  - PR #1 → `92a0315c2684b83674ee50eaac4cd49a8722aac7` : `Documentation` réussi sur `main`.
  - PR #2 → `a016091323b5850010334f91d7cfa61872619366` : `Documentation` réussi ; `Stockage Mac` relancé manuellement sur `main` (#1+#2) et réussi (run `40152364389`).
  - PR #3 → `c2b1b2978c3722c73b6b90681fa09c5888b4816a` : `Documentation` réussi ; `Sauvegarde synthétique` (run `40152580509`) et `Stockage Mac` (run `40152582505`) relancés sur `main` (#1+#2+#3) et réussis.
- **Résultats rapportés par Codex (25/10, assemblage local)** : 156 tests Swift réussis, 7 ignorés ; 16 Python ; 20 PageShift sous ASan ; compilation générique iOS déclarée réussie, minimum iOS 16. Ces nombres restent des **résultats de rapport**, non revérifiés dans les journaux des runs `main`.
- **Non effectué** : aucun essai sur iPad ; MLX/Metal non qualifiés pour ce lot ; restauration TrollStore non prouvée ; LSan non disponible sur la toolchain employée ; compilation iOS non exécutée en CI ; 7 essais ignorés faute de modèles ONNX/UniDic.
- **Écueils documentés** : un OCR commencé avant changement de pagination peut écrire sur la mauvaise page ; un fichier ordinaire suffixé `-wal` n'est pas forcément une annexe SQLite. Les PR #2/#3 apportent des correctifs et tests dédiés ; ne jamais les réintroduire.
- **Plan CI** : `docs/CI-ROADMAP.md` provient d'un fichier local non suivi de Codex (audit du 25/10 sur `edd09b2`, arbre identique à `c2b1b29`). Sa partie workflows a été revérifiée contre `main` ; ses tarifs, labels de runners, versions Xcode/XcodeGen et sources externes **ne l'ont pas été**.
- **Contrôle documentaire** : `scripts/check_documentation.py` vérifie les liens locaux et, depuis GOV-03, la présence des documents de pilotage et leurs renvois. Sur un push groupant plusieurs commits, `git diff --check HEAD^ HEAD` ne couvre que le dernier (CI-ROADMAP, phase 1). Les en-têtes SPDX des Markdown ne sont pas contrôlés : plusieurs documents historiques n'en ont pas.
- **À ne pas confondre** : le fichier racine `PLAN.md` est le plan historique du produit (V1→V5), pas ce plan directeur.

## 6. Mode opératoire : une tâche du début à la fin

1. **Cadre** : identifiant du chantier, bug/objectif, bénéfice, périmètre, propriétaire de la décision.
2. **Contrat** : invariants, données touchées, contraintes iOS 16 et modèles, tests requis, non-objectifs.
3. **Preuve avant** : test de régression qui échoue pour un bug ; mesures de référence pour une optimisation.
4. **Modification** : branche et PR petites, pas d'évolution silencieuse des dépendances, pas de fusion sans accord.
5. **Vérification** : commandes + SHA + environnement, résultats passés/échoués/ignorés ; test iPad explicitement absent ou réalisé.
6. **Revue** : contrôle indépendant pour données, concurrence, sécurité ou changements de fichiers persistants.
7. **Intégration** : validation du propriétaire, contrôles sur le résultat combiné, plan de retour arrière.
8. **Transmission** : mise à jour de ce tableau, liens PR/Issues, documentation du domaine et prochaine action débloquée.

**Définition de terminé** : implémentation + vérifications exigées + documentation + revue + intégration, *et* validation sur iPad si le critère la demande. Ne jamais clore implicitement une preuve manquante.

## 7. Répertoire documentaire — sans double emploi

- **Ce fichier** : suivi du programme de professionnalisation.
- [INDEX.md](INDEX.md) : navigation dans la documentation.
- [FEUILLE-DE-ROUTE.md](FEUILLE-DE-ROUTE.md) : backlog produit et historique.
- [HISTOIRE-DU-DEVELOPPEMENT.md](HISTOIRE-DU-DEVELOPPEMENT.md) : chronologie et décisions passées.
- [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) : règles ; [TESTS.md](TESTS.md), [CI-ET-LIVRAISON.md](CI-ET-LIVRAISON.md), [MEMOIRE-ET-SANITIZERS.md](MEMOIRE-ET-SANITIZERS.md), [DONNEES-ET-SAUVEGARDES.md](DONNEES-ET-SAUVEGARDES.md) : procédures.
- [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md), [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md), [PHASE2-NETTOYAGE.md](PHASE2-NETTOYAGE.md) : lots de la phase 2.
- [RETOURS-IPAD.md](RETOURS-IPAD.md) : registre des retours d'usage réel (identifiant stable, build, état, Issue, PR, preuve) ; [RECETTE-IPAD-QA-02.md](RECETTE-IPAD-QA-02.md) : scénarios de recette.
- [CI-ROADMAP.md](CI-ROADMAP.md) : plan d'automatisation CI à mettre en œuvre par phases ; [CI-ET-LIVRAISON.md](CI-ET-LIVRAISON.md) décrit l'existant et la livraison.

**Résolution des contradictions** : rapporter les deux sources et leur date, vérifier le code/les runs et demander une décision si nécessaire. Ne pas effacer l'historique ni mettre à jour silencieusement les anciennes notes.

## 8. Point de reprise pour le prochain chat

**État de référence du 27/10/2026, après la recette 1.3.2 :**

- `main` : `738dceb7fd09ccfcb1b9feb454c1d695d2658d9d` avant la fusion de cette mise à jour (#62) ; relever le SHA courant sur GitHub.
- Registre central : [RETOURS-IPAD.md](RETOURS-IPAD.md), RET-001 à RET-043 ; prochain identifiant libre RET-044.
- Candidate locale 1.3.2 (42), non publiée : source `bfd4312`, `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e`. RET-010/011/012 confirmés iPad ; #13, #14, #15 fermées.
- Ouverts : RET-041 (#60) et RET-042 (#61), non résolus ; RET-043 (#63, navigation PDF en mode lecture), investigation proposée sans correctif.
- Actions désactivé ; aucune release ; dépendances/forks MLX inchangés ; aucune donnée personnelle manipulée.

**Une seule séquence recommandée :** fixer avec NOxygen59 les priorités du registre (dont #60 et #61), puis un lot à la fois : Issue cadrée, PR, preuves Mac, candidate locale, recette iPad. Les validations DATA-01, DATA-02, DATA-03 et PERF-01 demeurent ouvertes et passent avant une refactorisation importante.

**Question standard de reprise :** « Lis `AGENTS.md`, `docs/PLAN-DIRECTEUR.md` et `docs/RETOURS-IPAD.md`, compare avec GitHub actuellement, puis indique l'état vérifié, les blocages et une seule prochaine action ; ne fusionne ni ne publie sans mon accord. »

### Historique condensé du 26 octobre

La campagne QA02 1.3 build 40 a produit les lots diagnostics, OCR/dictionnaire et panneau OCR, ensuite fusionnés par les PR [#8](https://github.com/NOxygen59/kyokasho/pull/8), [#9](https://github.com/NOxygen59/kyokasho/pull/9) et [#10](https://github.com/NOxygen59/kyokasho/pull/10). Les constats, corrections, limites et recettes restent dans [QA02-CORRECTIONS-DIAGNOSTICS.md](QA02-CORRECTIONS-DIAGNOSTICS.md), [QA02-CORRECTIONS-OCR-DICTIONNAIRE.md](QA02-CORRECTIONS-OCR-DICTIONNAIRE.md) et [QA02-CORRECTIONS-PANNEAU.md](QA02-CORRECTIONS-PANNEAU.md). O07 et le retard de défilement n'y étaient qu'instrumentés ; ne pas les déclarer résolus sans preuve ultérieure.

### Historique conservé du 25 octobre


**Dernier fait vérifié ici (25/10) :** PR #1 à #5 fusionnées (`92a0315`, `a016091`, `c2b1b29`, `ee07c55`, `f76d9f6`), PR #6 (GOV-04) fusionnée sur autorisation de NOxygen59, commit `f83aec8c61d88f1e6c119376590899c9c1ce2876` vérifié lors de QA-02. Les derniers contrôles GitHub réussis datent d'avant la désactivation. **GitHub Actions est désactivé** (CI-0) : les preuves se font désormais en local et se documentent dans les PR. Aucune Issue. Dépôt public, `main` non protégée. Aucune build, aucun essai iPad, aucune release depuis v1.3.

**Validations encore ouvertes (aucune effectuée) :** recette iPad de DATA-01 (ajout de pages, OCR concurrent, annotations, gros PDF) et de DATA-02 (extraction/restauration TrollStore) ; MLX/Metal sur iPad pour ce lot ; DATA-03 (géométrie des annotations) ; LSan et campagne mémoire (PERF-01).

**Décisions du propriétaire encore ouvertes :**

- **Réactivation éventuelle de GitHub Actions** (désactivé, CI-0 fait le 25/10/2026) : uniquement après un constat écrit de NOxygen59 (aucun moyen de paiement, ou budget Actions à 0 $ avec « *Stop usage when budget limit is reached* ») et une autorisation par workflow. Une simple alerte de budget ou une rétention courte ne suffisent pas.
- Visibilité du dépôt et protection de `main` (SEC-01).
- Réglages Actions de sécurité à appliquer avant toute réactivation : épinglage SHA obligatoire, approbation de tous les contributeurs externes.
- Autorisation d'une build de test et de son installation pour la recette iPad. Le niveau A sur l'installation existante avec risque de perte accepté est déjà décidé par NOxygen59 ; appliquer les précautions A0. Aucun changement de version/build sans nouvel accord ; identification externe par SHA source et SHA-256 du `.tipa`.
- Qualification de la méthode d'extraction/réimport TrollStore sur conteneur jetable ; autorisations distinctes pour B1 puis B2. La copie Mac n'est pas une assurance de récupération iPad.
- Création éventuelle des étiquettes GitHub `agent:claude`, `agent:codex`, `revue-croisée`.

**Prochaine priorité :** relire/fusionner la PR documentaire QA-02 seulement sur accord. La [recette](RECETTE-IPAD-QA-02.md) est préparée ; les essais restent **non effectués**. La revue de Claude a été validée par NOxygen59 : corrections documentaires sur la même branche, niveau A admis sur l'installation existante avec acceptation du risque de perte et PDF synthétiques préfixés QA02-. Après autorisation de build/installation et précautions A0, NOxygen59 remplit A0–A5 ; B1/B2 restent bloqués jusqu'à qualification séparée d'un conteneur synthétique et accords explicites. Ne pas assimiler l'installation existante à un conteneur sans données personnelles. Aucun travail CI, aucune release ni accès à la bibliothèque personnelle ne découle de cette préparation. Les lignes DATA-01, DATA-02, DATA-03 et PERF-01 restent ouvertes pour leurs preuves appareil.

**Question standard de reprise :** « Lis `AGENTS.md` et `docs/PLAN-DIRECTEUR.md` dans `NOxygen59/kyokasho`, compare avec GitHub actuellement, puis indique en français l'état vérifié, les blocages et une seule prochaine action ; ne code ni ne fusionne sans ma demande. »

**Mise à jour à chaque PR de professionnalisation** : modifier les lignes pertinentes, associer des liens permanents vers les preuves et renouveler ce point de reprise. Ne pas transformer une intention, une checklist cochée ou un rapport IA en preuve iPad.
