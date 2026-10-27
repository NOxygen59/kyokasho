<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Plan directeur — professionnalisation de Kyōkasho

> **Point d'entrée de pilotage pour les humains et agents IA.** Ce fichier suit la transformation *technique* du projet, pas le backlog de fonctionnalités. Il n'est **pas** une autorisation d'implémenter, fusionner, publier ou modifier les données. Lire [AGENTS.md](../AGENTS.md) avant toute action.
>
> **Dernier instantané vérifié : 25 octobre 2026, préparation QA-02.** `main` à `f83aec8c61d88f1e6c119376590899c9c1ce2876`, relevé par récupération Git ; PR #1 à #6 fusionnées, aucune PR ouverte ni Issue au démarrage initial. À la reprise, PR #7 ouverte à `4692188`, revue de Claude reçue et corrections autorisées par NOxygen59. La PR #6 est bien fusionnée : son ancien statut « fusion autorisée / commit à relever » ci-dessous est actualisé. **GitHub Actions reste désactivé**, réglage `enabled: false` relu avant publication ; aucun workflow lancé. QA-02 : recette préparée sur `codex/qa02-recette-ipad`, pas de build ni d'essai appareil. Ne pas considérer cet instantané comme actuel sans interroger GitHub.

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

## 3. Registre des chantiers de professionnalisation

**Code de statut de cette table :** « fusionné » n'est **pas** « testé iPad » ; « à valider iPad » n'est **pas** « testé iPad ». Les tâches nouvelles ne sont que **proposées**, jamais automatiquement autorisées.

| ID | Chantier | Situation au relevé | Preuve / source | Prochaine condition de clôture |
|---|---|---|---|---|
| GOV-01 | Documentation, architecture, contribution, tests | **Fusionné** le 25/10 (commit de fusion `92a0315`) ; contrôle `Documentation` réussi sur `main` | [PR #1](https://github.com/NOxygen59/kyokasho/pull/1) ; [INDEX.md](INDEX.md) | Clos pour l'intégration ; tenir les guides à jour à chaque PR |
| GOV-02 | Plan directeur de professionnalisation (ce fichier) | **Fusionné** le 25/10 (`ee07c55`) ; contrôle `Documentation` réussi sur `main` | [PR #4](https://github.com/NOxygen59/kyokasho/pull/4) | Clos pour l'intégration ; mise à jour obligatoire à chaque PR qui fait évoluer un chantier (règle de [AGENTS.md](../AGENTS.md)) |
| GOV-03 | Consolidation : instructions des agents, publication du plan CI, contrôle des documents obligatoires | **Fusionné** le 25/10 (`f76d9f6`) ; contrôle `Documentation` réussi sur `main`. Contenu : `AGENTS.md` commence par l'état GitHub et ce plan ; `docs/CI-ROADMAP.md` publié ; `scripts/check_documentation.py` vérifie aussi les documents et renvois obligatoires | [PR #5](https://github.com/NOxygen59/kyokasho/pull/5) (branche `docs/gouvernance-ci-roadmap`) | Clos pour l'intégration |
| GOV-04 | Protocole Claude / Codex, documentation du code, gabarits de PR et d'Issue, politique « Zéro dépense » | **Fusionné le 25/10/2026** (`f83aec8`), vérifié lors de QA-02 ; revue de Codex reçue (2 remarques, traitées) : protocole dans [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex) (autorisations de NOxygen59 valables dans un chat et consignées, commentaires signés [Claude]/[Codex]), règles de documentation dans [CONTRIBUTING.md](../CONTRIBUTING.md), `CLAUDE.md` qui importe `AGENTS.md`, gabarits `.github/`, politique « Zéro dépense » et tests locaux dans [CI-ROADMAP.md](CI-ROADMAP.md) et [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | [PR #6](https://github.com/NOxygen59/kyokasho/pull/6) (branche `claude/collaboration-agents-ci-gratuite`) | Intégration close ; QA-02 reprend le gabarit de PR et fournit la preuve locale |
| DATA-01 | Reprise idempotente d'ajout de pages / PageShift | **Fusionné** le 25/10 (`a016091`) ; `Stockage Mac` réussi sur `main` après #1+#2 et après #1+#2+#3 ; **non essayé sur iPad** | [PR #2](https://github.com/NOxygen59/kyokasho/pull/2) ; [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md) ; runs `40152364389`, `40152582505` | Recette iPad sur copie : OCR concurrent, annotations, gros PDF |
| DATA-02 | Sauvegarde et restauration hors ligne | **Fusionné** le 25/10 (`c2b1b29`) ; `Sauvegarde synthétique` réussi sur `main` ; **restauration TrollStore/iPad non démontrée** | [PR #3](https://github.com/NOxygen59/kyokasho/pull/3) ; [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md) ; run `40152580509` | Qualifier extraction/restauration sur iPad avec une bibliothèque jetable avant tout usage réel |
| QA-01 | Tests de logique et stockage | Sur `main` (`c2b1b29`), GitHub Actions macOS : `Stockage Mac` et `Sauvegarde synthétique` réussis. Le bilan chiffré (156 Swift réussis, 7 ignorés, 16 Python, 20 PageShift sous ASan) reste un **rapport Codex sur assemblage local** | Runs ci-dessus ; rapports des PR #2/#3 | Relever les nombres de tests depuis les journaux des runs `main`, avec versions d'outils et liste des tests ignorés |
| CI-01 | Automatisation CI | **GitHub Actions désactivé le 25/10/2026** (décision CI-0 de NOxygen59, vérifiée via l'API : `enabled: false`). Les trois workflows (`documentation.yml`, `storage.yml`, `backup.yml`) restent versionnés mais inactifs. Politique « Zéro dépense » (GOV-04). **Tests exécutés localement** sur le Mac de NOxygen59 et documentés dans chaque PR par une fiche de preuve | [CI-ROADMAP.md](CI-ROADMAP.md) ; [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | CI-G (script local de fiche de preuve) sur accord ; réactivation d'Actions seulement par NOxygen59, après protection vérifiée et autorisation par workflow |
| QA-02 | Recette iPad par version | **Recette fusionnée avec la [PR #7](https://github.com/NOxygen59/kyokasho/pull/7) (`431f1c6`) ; retours d'usage réel suivis dans le [registre des retours iPad](RETOURS-IPAD.md) (RET-001 à RET-021, Issues #11 à #24) ; aucun retour « confirmé iPad ».** Corpus exclusivement synthétique à fabriquer, scénarios A0–A5 sur installation existante (risque de perte accepté par NOxygen59 le 25/10), garde B0–B2 inchangée, fiches de campagne/anomalie. Revue de Claude traitée : libellés exacts, égalisation automatique, diagnostic, preuves externes de build. Aucune build ni release créée | [Recette QA-02](RECETTE-IPAD-QA-02.md), [preuves locales](TESTS.md#qa-02--vérifications-de-préparation-du-25-octobre-2026) ; branche `codex/qa02-recette-ipad` | Accord pour build/installation, précautions A0 sur installation existante, puis essais de NOxygen59 par scénario ; extraction/réimport soumis à qualification et accords distincts. DATA-01/DATA-02 restent non validés iPad |
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

1. ~~**Intégration documentaire et corrections de données** : fusion #1 → #2 → #3.~~ **Fait le 25/10**, avec revérification de `main` après chaque fusion (voir § 5).
2. **Preuves sur appareil et récupération** : recette [QA-02](RECETTE-IPAD-QA-02.md) préparée ; niveau A admis sur l’installation existante avec risque de perte accepté par NOxygen59 (25/10). Construire et installer une build seulement après accord, conserver SHA source et SHA-256 du `.tipa` sans changer les numéros sans autorisation, puis tester uniquement avec des PDF synthétiques l'ajout de pages, OCR concurrent, annotations et gros PDF ; ne pas essayer une restauration incertaine sur le seul conteneur réel.
3. **CI** : GitHub Actions est désactivé (CI-0, 25/10/2026) ; politique « Zéro dépense » de [CI-ROADMAP.md](CI-ROADMAP.md). Prochain lot possible : CI-G (script local qui produit la fiche de preuve), puis CI-A. Les lots GitHub CI-B à CI-F restent gelés tant que NOxygen59 n'a pas réactivé Actions après protection vérifiée. MLX/Metal et benchmarks : toujours sur le Mac de NOxygen59, hors runner.
4. **Données / OCR / performances** : traiter les risques démontrés (DATA-03 en premier) et enrichir les tests avant de remanier les modules.
5. **Maintenabilité** : refactorisation mesurée et limitée ; aucune réécriture générale par défaut.
6. **Diagnostic guidé** : étudier après stabilisation du stockage et des tests automatiques, sans upload brut automatique de journaux.
7. **Nouvelles fonctionnalités / macOS** : uniquement par décision produit dédiée.

Les décisions SEC-01 (visibilité, protection de `main`) peuvent être prises à tout moment par le propriétaire. Une anomalie critique démontrée peut modifier cet ordre, avec justification enregistrée.

## 5. Registre des validations et limites

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
