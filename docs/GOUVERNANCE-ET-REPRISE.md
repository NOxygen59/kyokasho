<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Gouvernance, roadmap et stratégie de refactorisation

## Qui décide

NOxygen59 possède le produit, choisit les usages, les priorités et les numéros de release, et réalise les essais sur son iPad. Les assistants proposent, implémentent et apportent des preuves ; ils ne peuvent pas transformer leur propre affirmation en validation utilisateur. Un contributeur humain doit pouvoir reprendre le projet sans relire tous les chats.

**Rôles depuis le 09-10/11/2026.** NOxygen59 décide, tranche et teste sur l'iPad. Claude planifie, code (dont tout le travail sensible, niveau R2), vérifie et reprend le travail des autres agents. DeepSeek 4.1 Flash et GLM 5.3 Flash (via Hermes) analysent, relisent et peuvent coder **seulement** dans une copie de travail dédiée (branche `agents/<sujet>`), relue et testée par Claude avant reprise. Codex et Qwen sont mis de côté jusqu'à nouvel ordre ; une revue de niveau R2 faite sans Codex est notée « revue R2 sans Codex ». La méthode (plan d'attaque approuvé, niveaux R0 à R3, recette après chaque étape, avenant, analyse de dérive) est décrite au § 0 de [PLAN-DIRECTEUR.md](PLAN-DIRECTEUR.md).

La feuille de route existante conserve les règles et décisions historiques. Ce document propose l'ordre de reprise à partir de v1.3 ; il ne coche pas rétroactivement les chantiers anciens et ne lance pas la grammaire sans accord.

## Cycle de travail proportionné

Chaque tâche contient un problème observable, le bénéfice attendu, le responsable, un critère de fin, les données à préserver et les validations nécessaires. Préférer une PR courte, autonome et relisible. Une décision qui engage le stockage, les forks, la compatibilité ou la distribution mérite une note datée : contexte, choix, alternatives réellement considérées, conséquences et preuve attendue.

En cas de contradiction documentaire, regarder code et preuves datées, demander une décision produit si nécessaire, puis corriger le document courant. Garder les anciennes notes pour leur valeur historique. Exemple actuel : l'intention de dépôt privé et l'état GitHub public sont deux informations à réconcilier, sans changer la visibilité par automatisme.

## Roadmap de reprise proposée

| Lot | Contenu limité | Dépendance et critère de fin |
|---|---|---|
| D0 — documentation | Guides, audit, tests remis en état, liens | PR relue ; preuves et limites explicites ; aucune logique app modifiée |
| D1 — décision et données | Décider visibilité, inventorier le conteneur, qualifier une sauvegarde | Restauration réussie d'un corpus synthétique ; connexions et exclusions notées |
| D2 — reprise PageShift | Tests de panne sur journal/base/PDF/rapport/fichiers/cartes, puis correction ciblée | Chaque arrêt simulé aboutit à un état cohérent sans double décalage ni donnée sur une mauvaise page |
| D3 — coordonnées | Reproduire anciennes annotations/export avec égalisation | Images/repères et export vérifiés sur corpus ; recette iPad ensuite |
| D4 — qualité automatique | Qualifier runner Mac, rendre tests/compilation fiables, campagne ASan CPU | Résultats par cible, ignorés séparés ; environnement et artefacts reproductibles |
| D5 — contrats OCR/chat | Tests v1.3 et extraction ciblée des frontières App | Langue, lignes éditées, pages citées et invalidation vérifiées sans poids IA |
| D6 — mémoire/performance | Baseline iPad et Mac, répétitions, annulation, froid/chaud | Mesures reproductibles et cause identifiée avant optimisation |
| D7 — usages suivants | « Continuer », vertical/tableaux, GLM groupé ; grammaire seulement après accord | Une fonction par lot, seuil de qualité défini, pas de régression données/gestes |

Cet ordre privilégie les données et les preuves ; il n'impose pas une durée ni un numéro de version. Les retours bloquants de NOxygen59 peuvent modifier l'ordre. Qwen plus gros, nouvelle architecture générale et support d'autres appareils ne sont pas des prérequis à cette reprise.

## Refactoriser sans réécrire l'app

1. Choisir une frontière problématique démontrée, pas un fichier simplement long. Exemple : effets de fichiers testables de PageShift ou sélection des passages du chat.
2. Capturer le comportement actuel avec un test pertinent, en identifiant les bugs connus qui ne doivent pas être figés comme une spécification souhaitée.
3. Extraire une responsabilité derrière une petite interface injectée, en conservant format des données, ordre des opérations, isolation et cycle de vie.
4. Comparer avant/après : tests, fichiers produits et erreurs observables. Relire le diff pour les changements de visibilité, de capture de `self` et d'annulation.
5. Déployer le changement séparément d'une amélioration fonctionnelle ; demander la recette iPad adaptée. Conserver un retour arrière réaliste.

Pour `ReaderController`, le découpage en extensions a déjà eu lieu. Ajouter des extensions sans réduire le partage d'état peut simplement déplacer le problème. Étudier d'abord les responsabilités et flux de notifications ; extraire une logique pure testable seulement lorsqu'elle a un contrat clair. Ne pas imposer « Clean Architecture », un nouveau framework de dépendances ou un bus universel sans besoin démontré.

## Code mort et commentaires

Un nom présent une seule fois est un indice, pas une preuve : SwiftUI, délégués UIKit, Objective-C, notifications, clés persistées et ressources peuvent avoir des usages indirects. Avant suppression : recherche des appels et sélecteurs, vérification des ressources/manifestes, compilation et parcours utilisateur. Petits lots réversibles, sans suppressions massives.

Les commentaires couvrent invariants, pièges de plateforme et contrats d'API. Les lignes évidentes ne demandent pas de paraphrase. Une décision désormais fausse doit être corrigée avec le code ; préserver les crédits tiers. DocC/Doxygen peuvent aider à naviguer les API quand leurs commentaires sont fiables, mais ne remplacent ni guide d'architecture ni stratégie de tests.

## Collaboration entre agents (Claude et Codex)

> **Titre historique.** Depuis le 09-10/11/2026, Codex et Qwen sont mis de côté : Claude planifie, code (dont tout le
> travail sensible, niveau R2), vérifie et reprend ; DeepSeek 4.1 Flash et GLM 5.3 Flash (via Hermes) analysent,
> relisent et peuvent coder **seulement** dans une copie de travail dédiée (branche `agents/<sujet>`), relue et testée
> par Claude avant reprise. Une revue de niveau R2 faite sans Codex est notée « revue R2 sans Codex ». Les règles
> ci-dessous valent pour tous ces agents.

Jusqu'au 09/11/2026, Claude et Codex étaient les deux seuls agents de développement. Les agents se succèdent sans partager leurs conversations : **tout le contexte utile passe par GitHub** (Issues, PR, commits, documents versionnés). Ce qui n'est écrit que dans un chat est perdu pour l'agent suivant. NOxygen59 reste seul décideur.

### Règles

1. **Lire l'état GitHub avant toute mission** : SHA de `main`, PR ouvertes, Issues, derniers contrôles, puis [le plan directeur](PLAN-DIRECTEUR.md). Une PR ou une branche d'un autre agent encore ouverte est un travail en cours, pas un brouillon abandonné.
2. **Une tâche, une branche, un agent responsable.** Branche `claude/<sujet>`, `codex/<sujet>` ou `agents/<sujet>` (copie de travail dédiée d'un agent d'analyse) ; l'agent responsable est indiqué en tête de PR. Un autre agent ne pousse pas sur cette branche, sauf dans deux cas : l'agent responsable le demande par écrit dans la PR, ou NOxygen59 le demande explicitement, où qu'il le fasse (PR, Issue ou chat avec l'agent). L'agent qui intervient cite alors cette demande et sa date dans la PR avant de pousser, pour que la passation reste sur GitHub.
3. **Tâche définie avant de coder** : une Issue (gabarit « Tâche ») ou, pour un petit lot, le début de la PR. On y trouve l'identifiant du chantier du plan directeur, l'objectif, le périmètre exclu, le critère d'acceptation et l'autorisation de NOxygen59 (citée, avec sa date et son origine : chat, Issue ou PR).
4. **Passation écrite** : chaque PR suit le [gabarit](../.github/pull_request_template.md). Elle contient un résumé simple pour NOxygen59, les changements techniques, les preuves, les limites et une passation à l'agent suivant. Les messages de commit disent le pourquoi en français. Une décision durable (stockage, forks, compatibilité, CI) est consignée dans le guide du domaine, pas seulement dans la PR.
5. **Revue indépendante par un autre agent** lorsque le risque le justifie. Elle est obligatoire pour :
   - les données persistantes, les migrations, PageShift et la sauvegarde ;
   - la concurrence ou l'annulation ;
   - le code C/C++ ou la mémoire ;
   - les forks MLX, les dépendances ou `Package.resolved` ;
   - les workflows, les permissions ou la sécurité ;
   - toute suppression de code.

   Le relecteur commente la PR (revue GitHub ou commentaire) avec ses constats et ses preuves. Il ne réécrit pas le travail. Pour une simple modification de document, une relecture par l'agent auteur suffit.

   Depuis le 09/11/2026, Codex et Qwen sont mis de côté : une revue de niveau R2 faite sans eux est notée **« revue R2 sans Codex »** dans la PR, pour que la limite reste visible et ne se confonde pas avec une revue croisée.
6. **Justifier les changements techniques importants** : problème démontré, alternatives écartées, preuve avant et après (test, mesure, journal borné), conséquences et retour arrière.
7. **Désaccord explicite, sans modifications concurrentes.** Le relecteur écrit une section « Désaccord » dans la PR : position, preuves, risque. L'auteur répond par écrit. Sans accord, la PR reste ouverte et NOxygen59 tranche. Aucun des deux agents n'ouvre de branche concurrente sur les mêmes fichiers en attendant. Une contre-proposition se fait dans une PR distincte annoncée dans la discussion.
8. **Clore proprement** : mettre à jour [le plan directeur](PLAN-DIRECTEUR.md) (ligne du chantier, preuves, point de reprise) et les guides touchés dans la même PR ; déclarer ce qui n'a pas été vérifié.
9. **Autorisations de NOxygen59** obligatoires pour toute fusion, release, changement de version, de dépendance ou de fork, changement de réglage GitHub (visibilité, protection, Actions, facturation), activation d'une automatisation, essai sur appareil ou changement majeur d'architecture.
   - Une autorisation explicite de NOxygen59 est **valable où qu'il la donne**, y compris dans son chat avec un agent. Elle couvre seulement ce qu'elle nomme. L'agent la consigne dans la PR ou l'Issue (citation courte et date) ; il n'en invente ni n'en élargit jamais la portée.
   - Les autorisations déjà données restent valables dans leur périmètre.
   - Un commentaire ou un avis d'agent n'est **jamais** une autorisation.
10. **Signer les commentaires.** Les agents publient avec le compte GitHub de NOxygen59. Chaque commentaire, revue ou description de PR d'un agent commence donc par **[Claude]**, **[Codex]**, **[DeepSeek]** ou **[GLM]**, pour distinguer ce qu'écrit NOxygen59 de ce qu'écrit un agent.
11. **Zéro dépense.** Aucun agent n'active, n'ajoute ni ne lance d'automatisation GitHub Actions, d'artefact, de cache, de runner payant ou de service payant hors des conditions de la politique « Zéro dépense » de [CI-ROADMAP.md](CI-ROADMAP.md). Les preuves se font en local par défaut.
12. **Méthode par étapes.** Un plan d'attaque approuvé par NOxygen59 avant tout gros chantier, des niveaux de risque R0 à R3 (R0 documentation et outillage sans effet sur l'app, R1 correctif local et testé, R2 données, concurrence, mémoire, C/C++, dépendances et forks, CI, sécurité et suppressions de code, R3 changement de contrat, de données ou d'architecture), une recette après chaque étape, un avenant écrit si le périmètre change, et une analyse de dérive écrite après deux FAIL structurels. Détail au § 0 de [PLAN-DIRECTEUR.md](PLAN-DIRECTEUR.md).

### Phrases types pour NOxygen59

Une ligne suffit à lancer l'agent suivant ; le reste est sur GitHub :

- « Lis `AGENTS.md`, vérifie GitHub, puis traite l'Issue #N. Ne fusionne pas. »
- « Fais la revue indépendante de la PR #N selon `docs/GOUVERNANCE-ET-REPRISE.md`. Ne pousse rien sur sa branche. »
- « Réponds à la revue de la PR #N et corrige ce qui est justifié. »

## Définition d'un travail terminé

Le comportement demandé est présent ; le diff reste limité ; le code significatif est documenté selon [CONTRIBUTING.md](../CONTRIBUTING.md) ; la PR contient sa passation ; les données et iOS 16 sont préservés ; les contrôles adaptés ont un résultat et un environnement ; les documents du domaine sont à jour ; les tests ignorés et la recette iPad manquante sont visibles ; aucune release n'est fabriquée sans demande. Un travail peut être intégré avec une limite connue explicitement acceptée, mais ne devient pas pour autant « confirmé sur iPad ».

## Indicateurs utiles

Suivre les anomalies de perte/décalage de données, le temps pour reproduire un incident, les tests de risque disponibles, les scénarios iPad non essayés, le temps d'ouverture/lecture à froid et les pics mémoire par modèle. Éviter les objectifs de lignes commentées, nombre d'abstractions ou couverture à 100 % sans rapport avec les usages.
