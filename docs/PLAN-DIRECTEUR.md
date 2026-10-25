<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Plan directeur — professionnalisation de Kyōkasho

> **Point d'entrée de pilotage pour les humains et agents IA.** Ce fichier suit la transformation *technique* du projet, pas le backlog de fonctionnalités. Il n'est **pas** une autorisation d'implémenter, fusionner, publier ou modifier les données. Lire [AGENTS.md](../AGENTS.md) avant toute action.
>
> **Dernier instantané vérifié : 25 octobre 2026.** État relevé via GitHub : les PR [#1](https://github.com/NOxygen59/kyokasho/pull/1), [#2](https://github.com/NOxygen59/kyokasho/pull/2) et [#3](https://github.com/NOxygen59/kyokasho/pull/3) sont **ouvertes, brouillon et non fusionnées**. Ne pas considérer cet instantané comme actuel sans interroger GitHub.

## 1. Utilisation par un nouvel agent (obligatoire)

1. Vérifier sur GitHub la branche `main`, son SHA, les PR, les Issues et leurs contrôles, ainsi que la présence des documents cités. Ne pas déduire l'état actuel de cet instantané.
2. Lire `AGENTS.md`, ce plan, [la feuille de route produit](FEUILLE-DE-ROUTE.md) et les documents techniques **présents sur la branche de travail**. Les guides de la PR #1 ne sont pas encore nécessairement dans `main`.
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
- Le dépôt était **public** lors du relevé du 25/10 ; la décision de visibilité appartient au propriétaire. Ne jamais publier des PDF, secrets, logs bruts ou jeux d'essai privés.

## 3. Registre des chantiers de professionnalisation

**Code de statut de cette table :** « PR prête » n'est **pas** « fusionnée » ; « à valider iPad » n'est **pas** « testé iPad ». Les tâches nouvelles ne sont que **proposées**, jamais automatiquement autorisées.

| ID | Chantier | Situation au relevé | Preuve / source | Prochaine condition de clôture |
|---|---|---|---|---|
| GOV-01 | Documentation, architecture, contribution, tests | PR #1 revue et annoncée prête ; **non fusionnée** | [PR #1](https://github.com/NOxygen59/kyokasho/pull/1) ; `docs/INDEX.md` sur sa branche | Intégrer après validation du propriétaire ; contrôler les liens et documents sur `main` |
| DATA-01 | Reprise idempotente d'ajout de pages / PageShift | PR #2 corrigée après revue indépendante ; **non fusionnée** | [PR #2](https://github.com/NOxygen59/kyokasho/pull/2) ; `docs/PHASE2-STOCKAGE.md` sur sa branche | Intégration + tests combinés ; recette iPad sur copie : OCR concurrent, annotations, gros PDF |
| DATA-02 | Sauvegarde et restauration hors ligne | PR #3 corrigée après revue ; **non fusionnée**, pas de restauration TrollStore démontrée | [PR #3](https://github.com/NOxygen59/kyokasho/pull/3) ; `docs/PHASE2-SAUVEGARDE.md` sur sa branche | Intégration + restauration sur corpus synthétique ; qualifier extraction/restauration sur iPad avant usage réel |
| QA-01 | Tests de logique et stockage | D'après le rapport Codex : 156 tests Swift réussis, 7 ignorés ; 16 Python ; 20 PageShift sous ASan Mac **sur assemblage local**, non preuve iPad | Rapports de PR #2/#3 et compte-rendu Codex, à rapprocher des SHA/CI | Établir bilan combiné sur `main`, conserver versions des outils et liste des tests ignorés |
| CI-01 | Automatisation complète macOS Apple Silicon | Workflows de documentation/stockage/sauvegarde proposés dans PR #1/#2/#3 ; plan CI **local non commité** selon dernier rapport Codex | PR #1-#3 ; chemin annoncé local `docs/CI-ROADMAP.md` (**absent de `main` au relevé**) | Publier et revoir le plan CI ; ajouter les jobs par petites PR, contrôler coûts, accès et protections |
| QA-02 | Recette iPad par version | **À faire** pour les changements de stockage ; statut de v1.3 partiellement confirmé seulement | `docs/TESTS.md` sur branche PR #1 ; historique du projet | Résultats datés par build et scénario, sur documents jetables, sans conclure « tout validé » |
| DATA-03 | Géométrie annotations/export après égalisation | Risque identifié, **non clos** | `docs/AUDIT-V1.3.md` / `docs/GOUVERNANCE-ET-REPRISE.md` sur branche PR #1 | Tests pages tournées et tailles mixtes + validation iPad |
| QA-03 | Contrats OCR, japonais, chat et citations de pages | Tests existants, couverture supplémentaire proposée | `docs/TESTS.md`, `docs/ARCHITECTURE-LECTURE.md` | Tests ciblés des corrections manuelles, langues, invalidations et requêtes « p. 6 » |
| PERF-01 | Profilage mémoire/performance | Procédures documentées ; **pas de campagne globale iPad/MLX ou LSan réussie attestée** | `docs/MEMOIRE-ET-SANITIZERS.md` sur PR #1 | Baselines froid/chaud ; instruments compatibles ; vérifier Swift ARC, MeCab, ONNX et Metal séparément |
| MAINT-01 | Nettoyage et modularisation progressifs | Dix pistes classées dans PR #3 ; **pas de nettoyage général réalisé** | `docs/PHASE2-NETTOYAGE.md` sur PR #3 | Une correction ciblée par PR, test avant/après, preuve d'absence de régression |
| DIAG-01 | Centre de tests guidés sur iPad / Diagnostic 2.0 | **Idée proposée, non implémentée et non approuvée** | Discussion de conception ; aucun commit revendiqué | Spécification privacy-first, faisabilité, prototypes limités ; résultats humain/automate distincts |
| SEC-01 | Confidentialité, licences, visibilité, protection de `main` | Dépôt GitHub signalé public ; décisions et audit à poursuivre | État du dépôt et `docs/AUDIT-V1.3.md` sur PR #1 | Décision du propriétaire, inspection des données publiques, garde-fous et licences |
| OPS-01 | Gouvernance de PR/release, traçabilité et ADR | Guides proposés dans PR #1 ; application dans les prochaines PR à mesurer | `CONTRIBUTING.md`, `docs/GOUVERNANCE-ET-REPRISE.md` sur PR #1 | Gabarits utiles, statut sur chaque PR, liens exigences→tests→résultats |
| PORT-01 | Application macOS (.app/.dmg) | **Option de produit, non démarrée** ; packages macOS ≠ app macOS | `Packages/KyokashoKit/Package.swift`, `project.yml` | Décision produit + étude Catalyst/natif séparée, sans altérer la cible iPad |

Les chantiers n'ont **pas** d'avancement en pourcentage : cela produirait une précision trompeuse. L'ordre n'est pas une promesse de calendrier.

## 4. Dépendances et ordre suggéré

1. **Intégration documentaire et corrections de données** : revue/fusion explicite #1 → #2 → #3 ; revérifier la combinaison après chaque étape. Si conflit ou nouvel échec, suspendre.
2. **Preuves sur appareil et récupération** : tester sur une bibliothèque jetable l'ajout de pages, OCR concurrent, annotations et gros PDF ; ne pas essayer une restauration incertaine sur le seul conteneur réel.
3. **CI** : intégrer d'abord le plan `CI-ROADMAP.md` (actuellement annoncé local), puis qualifier runner/Swift/Xcode, tests, compilation iOS, ASan ; séparer MLX réel et actions non fiables.
4. **Données / OCR / performances** : traiter les risques démontrés et enrichir les tests avant de remanier les modules.
5. **Maintenabilité** : refactorisation mesurée et limitée ; aucune réécriture générale par défaut.
6. **Diagnostic guidé** : étudier après stabilisation du stockage et des tests automatiques, sans upload brut automatique de journaux.
7. **Nouvelles fonctionnalités / macOS** : uniquement par décision produit dédiée.

Une anomalie critique démontrée peut modifier cet ordre, avec justification enregistrée.

## 5. Registre des validations et limites

- **Derniers résultats rapportés par Codex (25/10)** : 156 tests Swift réussis, 7 ignorés ; 16 Python ; 20 PageShift sous ASan ; compilation générique iOS déclarée réussie, minimum iOS 16. Ces nombres restent des **résultats de rapport**, à vérifier via les runs/commits précis. Pas de validation sur iPad.
- **Limites** : absence de modèles ONNX/UniDic dans les 7 essais ignorés, test iPad non exécuté, LSan non disponible sur la toolchain employée, MLX/Metal non qualifiés pour ce lot, restauration TrollStore non prouvée.
- **Écueils documentés** : un OCR commencé avant changement de pagination peut écrire sur la mauvaise page ; un fichier ordinaire suffixé `-wal` n'est pas forcément une annexe SQLite. Les PR #2/#3 déclarent des correctifs et tests dédiés ; ne jamais les réintroduire.
- **À ne pas confondre** : `docs/CI-ROADMAP.md` sur la machine de Codex n'est ni accessible depuis un nouveau chat ni versionné tant qu'il n'est pas commité et poussé.

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
- [FEUILLE-DE-ROUTE.md](FEUILLE-DE-ROUTE.md) : backlog produit et historique.
- [HISTOIRE-DU-DEVELOPPEMENT.md](HISTOIRE-DU-DEVELOPPEMENT.md) : chronologie et décisions passées.
- **En PR #1** : `docs/INDEX.md` pour naviguer ; `docs/GOUVERNANCE-ET-REPRISE.md` pour les règles ; `docs/TESTS.md`, `docs/CI-ET-LIVRAISON.md`, `docs/MEMOIRE-ET-SANITIZERS.md`, `docs/DONNEES-ET-SAUVEGARDES.md` pour les procédures.
- **En PR #2** : `docs/PHASE2-STOCKAGE.md` ; **en PR #3** : `docs/PHASE2-SAUVEGARDE.md` et `docs/PHASE2-NETTOYAGE.md`.
- **Local seulement au dernier rapport** : `docs/CI-ROADMAP.md`. Le publier avant de le citer comme source versionnée.

**Résolution des contradictions** : rapporter les deux sources et leur date, vérifier le code/les runs et demander une décision si nécessaire. Ne pas effacer l'historique ni mettre à jour silencieusement les anciennes notes.

## 8. Point de reprise pour le prochain chat

**Dernier fait vérifié ici :** PR #1/#2/#3 ouvertes en brouillon, non fusionnées ; dépôt public. Le plan CI annoncé n'est pas sur `main`. Aucun travail applicatif, fusion ou release n'est autorisé par ce plan.

**Prochaine action conditionnelle :** si les PR sont toujours non fusionnées, faire confirmer au propriétaire l'intégration #1 → #2 → #3 après vérifications ; si elles ont été fusionnées, enregistrer leurs commits et les contrôles sur `main`, puis préparer la validation iPad. Si l'état de GitHub diffère, **replanifier à partir des preuves actuelles**, pas de cette phrase historique.

**Question standard de reprise :** « Lis `AGENTS.md` et `docs/PLAN-DIRECTEUR.md` dans `NOxygen59/kyokasho`, compare avec GitHub actuellement, puis indique en français l'état vérifié, les blocages et une seule prochaine action ; ne code ni ne fusionne sans ma demande. »

**Mise à jour à chaque PR de professionnalisation** : modifier les lignes pertinentes, associer des liens permanents vers les preuves et renouveler ce point de reprise. Ne pas transformer une intention, une checklist cochée ou un rapport IA en preuve iPad.
