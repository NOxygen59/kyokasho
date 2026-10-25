<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Contribuer à Kyōkasho

Le projet sert d'abord l'iPad et les usages de NOxygen59. Professionnaliser signifie rendre les changements compréhensibles, vérifiables et réversibles ; cela n'impose pas une architecture d'entreprise ou une réécriture.

## Avant de modifier

Lire [AGENTS.md](AGENTS.md), vérifier l'état GitHub, lire [le plan directeur](docs/PLAN-DIRECTEUR.md), [la feuille de route](docs/FEUILLE-DE-ROUTE.md), puis le guide du domaine dans [l'index](docs/INDEX.md). Entre agents, suivre la [collaboration Claude / Codex](docs/GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex). Avant MLX : [IA locale](docs/IA-LOCALE.md). Identifier un comportement attendu, le scénario qui démontre le problème et les données à préserver. Inspecter les changements déjà présents ; ne pas les écraser.

Pour un changement significatif, ouvrir une branche et une PR explicite. Le lot de reprise utilise cette voie pour rendre la documentation relisible avant intégration ; cela ne révoque pas les autorisations antérieures d'envoi sur `main`. Les releases restent demandées et numérotées par NOxygen59.

## Une intervention, un objectif

1. Écrire le problème observable et le critère de fin ; nommer le périmètre exclu.
2. Localiser le responsable dans le code et chercher les tests existants. Reproduire un bug avant de le corriger ; distinguer hypothèse et cause démontrée.
3. Ajouter un test pertinent pour la correction fonctionnelle, puis faire le plus petit changement utile. Ne pas mêler refactorisation, mise à jour des dépendances et nouvelle fonction dans le même lot.
4. Exécuter les contrôles adaptés. Une modification de documents demande liens et diff ; une modification d'API ou stockage demande compilation et tests ; un changement de gestes demande recette iPad.
5. Relire le diff avec un regard critique : erreurs, annulation, concurrence, stockage, iOS 16, licences et documentation. Une seconde passe n'implique pas nécessairement un autre agent, sauf dans les cas à risque où la revue croisée est obligatoire (voir la gouvernance).
6. Commiter en français et décrire preuve et limites dans la PR. Aucune affirmation d'essai iPad sans retour réel.

## Style, noms et documentation du code

Conserver le style du module et éviter les abstractions sans second usage démontré. La documentation sert la maintenance future : elle explique le **pourquoi**, pas ce que la ligne dit déjà. Commenter chaque ligne augmente le bruit et le risque de documentation périmée.

Tout code **significatif** créé ou modifié doit respecter ces règles. Est significatif ce qui est nouveau, ce qui change un comportement, ou ce qui touche aux données, à la concurrence ou à la mémoire.

- **Noms clairs et explicites** : types, fonctions et variables disent leur rôle et leur unité (`pageIndex` et non `p`, `timeoutSeconds` et non `t`). Ne pas renommer massivement du code existant en dehors du lot.
- **Swift — DocC** : commentaire `///` pour chaque interface publique ou interne importante (type, protocole, fonction exposée par un package, point d'entrée d'un module). Résumé d'une phrase, puis selon le cas `- Parameters:`, `- Returns:`, `- Throws:` et une note sur l'acteur ou le fil attendu. Les détails évidents d'un `private` n'en demandent pas.
- **Commentaires de contexte** là où un lecteur pourrait casser le code sans le savoir :
  - **invariants** (ordre des opérations, index de page, coordonnées) ;
  - **concurrence** (acteur, `MainActor`, annulation, réentrance) ;
  - **mémoire** (cycles, `weak`/`unowned`, buffers, pics MLX) ;
  - **persistance** (schéma, migration, idempotence, fichiers annexes) ;
  - **contraintes iOS 16** et choix techniques non évidents, avec l'alternative écartée.
- **C/C++ — style Doxygen** (`/** ... */` avec `@brief`, `@param`, `@return`) pour les fonctions exposées ou les ponts vers Swift. Préciser le propriétaire de chaque pointeur, sa durée de vie, l'encodage, la gestion des nulls et la libération en cas d'erreur.
- **Tests de régression** : toute correction de comportement ajoute un test qui échoue avant le correctif et passe après. Si c'est impossible (dépend de l'iPad, d'un modèle, de Metal), le dire dans la PR et décrire le scénario de recette.
- **Guides techniques** : si un contrat, un format persistant ou une architecture change, mettre à jour le guide du domaine dans la même PR (par exemple [ARCHITECTURE-LECTURE.md](docs/ARCHITECTURE-LECTURE.md), [IA-LOCALE.md](docs/IA-LOCALE.md), [PHASE2-STOCKAGE.md](docs/PHASE2-STOCKAGE.md), [TESTS.md](docs/TESTS.md)).

Ne pas reformater tout un composant tiers pendant une correction locale. Garder copyrights et licences originaux ; utiliser les en-têtes SPDX adaptés au langage pour les nouveaux fichiers originaux. Une décision désormais fausse se corrige dans le commentaire en même temps que le code.

## Données et compatibilité

Aucun PDF personnel, poids, dictionnaire ou donnée tierce dans Git. Les exemples sont synthétiques et générés hors des sources versionnées. Ne jamais ajouter un journal brut contenant des informations personnelles ou des identifiants. Les secrets restent dans leur mécanisme local/trousseau ; on ne demande pas à NOxygen59 de les coller dans un chat ou une PR.

Une migration de base s'ajoute sans réécrire les migrations livrées. Un effacement ou un changement de cache doit décrire exactement les données touchées, surtout les OCR retouchés. Le retour arrière d'un commit ne répare pas automatiquement une donnée migrée.

Respecter iOS 16.0 minimum et les forks MLX validés. Les permissions de fichiers de l'assistant et les autorisations de l'utilisateur sont des contraintes distinctes ; ne pas contourner une restriction en lançant un autre outil.

## Contenu attendu d'une PR

Le [gabarit de PR](.github/pull_request_template.md) s'applique automatiquement. Chaque PR contient :

- un **résumé simple en français pour NOxygen59** : ce qui change pour lui, pourquoi, et ce qu'il doit décider ou essayer ;
- l'agent responsable, le chantier du plan directeur et l'Issue liée ;
- les changements techniques et les décisions nécessaires au lecteur ;
- les preuves : commandes réellement exécutées, SHA, plateforme, réussites, échecs et tests ignorés, avec la référence du run ou de la fiche locale ;
- les limites : risques de données, scénario iPad encore nécessaire, retour arrière réaliste ;
- une **passation à l'agent suivant** : état exact, pièges, prochaine étape, et ce qu'il ne doit pas refaire ;
- les documents modifiés, sans nouvelle case « confirmé » cochée par supposition.

Un changement de documentation peut être intégré sans nouveau `.tipa`. Ne pas changer `MARKETING_VERSION`, build, tags, release ou `latest.json` pour ce seul motif.
