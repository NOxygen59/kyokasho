<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Plan directeur — professionnalisation de Kyōkasho

> **Point d'entrée de pilotage pour les humains et agents IA.** Ce fichier suit la transformation *technique* du projet, pas le backlog de fonctionnalités. Il n'est **pas** une autorisation d'implémenter, fusionner, publier ou modifier les données. Lire [AGENTS.md](../AGENTS.md) avant toute action.
>
> **Dernier instantané vérifié : 25 octobre 2026, après intégration.** Les PR [#1](https://github.com/NOxygen59/kyokasho/pull/1), [#2](https://github.com/NOxygen59/kyokasho/pull/2) et [#3](https://github.com/NOxygen59/kyokasho/pull/3) sont **fusionnées dans `main`**, dans cet ordre, avec l'accord explicite du propriétaire ; la PR [#4](https://github.com/NOxygen59/kyokasho/pull/4) apporte ce plan. Ne pas considérer cet instantané comme actuel sans interroger GitHub.

## 1. Utilisation par un nouvel agent (obligatoire)

1. Vérifier sur GitHub la branche `main`, son SHA, les PR, les Issues et leurs contrôles, ainsi que la présence des documents cités. Ne pas déduire l'état actuel de cet instantané.
2. Lire `AGENTS.md`, ce plan, [la feuille de route produit](FEUILLE-DE-ROUTE.md), l'[index documentaire](INDEX.md) et les documents techniques du domaine touché.
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
| GOV-02 | Plan directeur de professionnalisation (ce fichier) | PR #4 mise à jour après les fusions #1→#3 | [PR #4](https://github.com/NOxygen59/kyokasho/pull/4) | Contrôle `Documentation` vert, fusion validée par le propriétaire, puis mise à jour à chaque PR de professionnalisation |
| DATA-01 | Reprise idempotente d'ajout de pages / PageShift | **Fusionné** le 25/10 (`a016091`) ; `Stockage Mac` réussi sur `main` après #1+#2 et après #1+#2+#3 ; **non essayé sur iPad** | [PR #2](https://github.com/NOxygen59/kyokasho/pull/2) ; [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md) ; runs `40152364389`, `40152582505` | Recette iPad sur copie : OCR concurrent, annotations, gros PDF |
| DATA-02 | Sauvegarde et restauration hors ligne | **Fusionné** le 25/10 (`c2b1b29`) ; `Sauvegarde synthétique` réussi sur `main` ; **restauration TrollStore/iPad non démontrée** | [PR #3](https://github.com/NOxygen59/kyokasho/pull/3) ; [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md) ; run `40152580509` | Qualifier extraction/restauration sur iPad avec une bibliothèque jetable avant tout usage réel |
| QA-01 | Tests de logique et stockage | Sur `main` (`c2b1b29`), GitHub Actions macOS : `Stockage Mac` et `Sauvegarde synthétique` réussis. Le bilan chiffré (156 Swift réussis, 7 ignorés, 16 Python, 20 PageShift sous ASan) reste un **rapport Codex sur assemblage local** | Runs ci-dessus ; rapports des PR #2/#3 | Relever les nombres de tests depuis les journaux des runs `main`, avec versions d'outils et liste des tests ignorés |
| CI-01 | Automatisation complète macOS Apple Silicon | Trois workflows sur `main` : `documentation.yml` (PR + push `main`), `storage.yml` et `backup.yml` (PR + lancement manuel, **pas de déclenchement sur push `main`**). Pas de compilation iOS ni de MLX en CI. `docs/CI-ROADMAP.md` **toujours absent** du dépôt | `.github/workflows/` ; [CI-ET-LIVRAISON.md](CI-ET-LIVRAISON.md) | Publier et revoir le plan CI ; ajouter les jobs par petites PR, contrôler coûts, accès et protections |
| QA-02 | Recette iPad par version | **À faire** pour les changements de stockage et de sauvegarde ; statut de v1.3 partiellement confirmé seulement. Aucune nouvelle build ni release depuis v1.3 | [TESTS.md](TESTS.md) ; historique du projet | Résultats datés par build et scénario, sur documents jetables, sans conclure « tout validé » |
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
2. **Preuves sur appareil et récupération** : construire une build de test (avec l'accord du propriétaire, sans release implicite), puis tester sur une bibliothèque jetable l'ajout de pages, OCR concurrent, annotations et gros PDF ; ne pas essayer une restauration incertaine sur le seul conteneur réel.
3. **CI** : publier le plan `CI-ROADMAP.md` (toujours absent), puis qualifier runner/Swift/Xcode, tests, compilation iOS, ASan ; envisager le déclenchement de `storage.yml`/`backup.yml` sur `main` ; séparer MLX réel et actions non fiables.
4. **Données / OCR / performances** : traiter les risques démontrés (DATA-03 en premier) et enrichir les tests avant de remanier les modules.
5. **Maintenabilité** : refactorisation mesurée et limitée ; aucune réécriture générale par défaut.
6. **Diagnostic guidé** : étudier après stabilisation du stockage et des tests automatiques, sans upload brut automatique de journaux.
7. **Nouvelles fonctionnalités / macOS** : uniquement par décision produit dédiée.

Les décisions SEC-01 (visibilité, protection de `main`) peuvent être prises à tout moment par le propriétaire. Une anomalie critique démontrée peut modifier cet ordre, avec justification enregistrée.

## 5. Registre des validations et limites

- **Intégration du 25/10 (GitHub)** — fusions par commit de fusion, branches conservées :
  - PR #1 → `92a0315c2684b83674ee50eaac4cd49a8722aac7` : `Documentation` réussi sur `main`.
  - PR #2 → `a016091323b5850010334f91d7cfa61872619366` : `Documentation` réussi ; `Stockage Mac` relancé manuellement sur `main` (#1+#2) et réussi (run `40152364389`).
  - PR #3 → `c2b1b2978c3722c73b6b90681fa09c5888b4816a` : `Documentation` réussi ; `Sauvegarde synthétique` (run `40152580509`) et `Stockage Mac` (run `40152582505`) relancés sur `main` (#1+#2+#3) et réussis.
- **Résultats rapportés par Codex (25/10, assemblage local)** : 156 tests Swift réussis, 7 ignorés ; 16 Python ; 20 PageShift sous ASan ; compilation générique iOS déclarée réussie, minimum iOS 16. Ces nombres restent des **résultats de rapport**, non revérifiés dans les journaux des runs `main`.
- **Non effectué** : aucun essai sur iPad ; MLX/Metal non qualifiés pour ce lot ; restauration TrollStore non prouvée ; LSan non disponible sur la toolchain employée ; compilation iOS non exécutée en CI ; 7 essais ignorés faute de modèles ONNX/UniDic.
- **Écueils documentés** : un OCR commencé avant changement de pagination peut écrire sur la mauvaise page ; un fichier ordinaire suffixé `-wal` n'est pas forcément une annexe SQLite. Les PR #2/#3 apportent des correctifs et tests dédiés ; ne jamais les réintroduire.
- **À ne pas confondre** : `docs/CI-ROADMAP.md` sur la machine de Codex n'est ni accessible depuis un nouveau chat ni versionné tant qu'il n'est pas commité et poussé. Le fichier racine `PLAN.md` est le plan historique du produit (V1→V5), pas ce plan directeur.

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
- **Local seulement au dernier rapport** : `docs/CI-ROADMAP.md`. Le publier avant de le citer comme source versionnée.

**Résolution des contradictions** : rapporter les deux sources et leur date, vérifier le code/les runs et demander une décision si nécessaire. Ne pas effacer l'historique ni mettre à jour silencieusement les anciennes notes.

## 8. Point de reprise pour le prochain chat

**Dernier fait vérifié ici (25/10) :** PR #1, #2 et #3 fusionnées (`92a0315`, `a016091`, `c2b1b29`) ; contrôles `Documentation`, `Stockage Mac` et `Sauvegarde synthétique` réussis sur `main` à `c2b1b29`. Dépôt public, `main` non protégée. Aucune Issue ouverte. Aucune build, aucun essai iPad, aucune release depuis v1.3.

**Prochaine action conditionnelle :** préparer la recette iPad de DATA-01/DATA-02 (QA-02) : liste de scénarios sur bibliothèque jetable, puis build de test **uniquement sur demande du propriétaire**. En parallèle, le propriétaire peut trancher SEC-01. Si l'état de GitHub diffère, **replanifier à partir des preuves actuelles**, pas de cette phrase historique.

**Question standard de reprise :** « Lis `AGENTS.md` et `docs/PLAN-DIRECTEUR.md` dans `NOxygen59/kyokasho`, compare avec GitHub actuellement, puis indique en français l'état vérifié, les blocages et une seule prochaine action ; ne code ni ne fusionne sans ma demande. »

**Mise à jour à chaque PR de professionnalisation** : modifier les lignes pertinentes, associer des liens permanents vers les preuves et renouveler ce point de reprise. Ne pas transformer une intention, une checklist cochée ou un rapport IA en preuve iPad.
