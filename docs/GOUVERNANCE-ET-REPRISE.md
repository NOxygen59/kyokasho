<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Gouvernance, roadmap et stratégie de refactorisation

## Qui décide

NOxygen59 possède le produit, choisit les usages, les priorités et les numéros de release, et réalise les essais sur son iPad. Les assistants proposent, implémentent et apportent des preuves ; ils ne peuvent pas transformer leur propre affirmation en validation utilisateur. Un contributeur humain doit pouvoir reprendre le projet sans relire tous les chats.

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

Claude et Codex sont les deux seuls agents de développement. Ils se succèdent sans partager leurs conversations : **tout le contexte utile passe par GitHub** (Issues, PR, commits, documents versionnés). Ce qui n'est écrit que dans un chat est perdu pour l'autre agent. NOxygen59 reste seul décideur.

### Règles

1. **Lire l'état GitHub avant toute mission** : SHA de `main`, PR ouvertes, Issues, derniers contrôles, puis [le plan directeur](PLAN-DIRECTEUR.md). Une PR ou une branche d'un autre agent encore ouverte est un travail en cours, pas un brouillon abandonné.
2. **Une tâche, une branche, un agent responsable.** Branche `claude/<sujet>` ou `codex/<sujet>` ; l'agent responsable est indiqué en tête de PR. L'autre agent ne pousse pas sur cette branche, sauf demande écrite dans la PR par l'agent responsable ou par NOxygen59.
3. **Tâche définie avant de coder** : une Issue (gabarit « Tâche ») ou, pour un petit lot, le début de la PR. On y trouve l'identifiant du chantier du plan directeur, l'objectif, le périmètre exclu, le critère d'acceptation et l'autorisation de NOxygen59 (citée, avec sa date).
4. **Passation écrite** : chaque PR suit le [gabarit](../.github/pull_request_template.md). Elle contient un résumé simple pour NOxygen59, les changements techniques, les preuves, les limites et une passation à l'agent suivant. Les messages de commit disent le pourquoi en français. Une décision durable (stockage, forks, compatibilité, CI) est consignée dans le guide du domaine, pas seulement dans la PR.
5. **Revue indépendante par l'autre agent** lorsque le risque le justifie. Elle est obligatoire pour :
   - les données persistantes, les migrations, PageShift et la sauvegarde ;
   - la concurrence ou l'annulation ;
   - le code C/C++ ou la mémoire ;
   - les forks MLX, les dépendances ou `Package.resolved` ;
   - les workflows, les permissions ou la sécurité ;
   - toute suppression de code.

   Le relecteur commente la PR (revue GitHub ou commentaire) avec ses constats et ses preuves. Il ne réécrit pas le travail. Pour une simple modification de document, une relecture par l'agent auteur suffit.
6. **Justifier les changements techniques importants** : problème démontré, alternatives écartées, preuve avant et après (test, mesure, journal borné), conséquences et retour arrière.
7. **Désaccord explicite, sans modifications concurrentes.** Le relecteur écrit une section « Désaccord » dans la PR : position, preuves, risque. L'auteur répond par écrit. Sans accord, la PR reste ouverte et NOxygen59 tranche. Aucun des deux agents n'ouvre de branche concurrente sur les mêmes fichiers en attendant. Une contre-proposition se fait dans une PR distincte annoncée dans la discussion.
8. **Clore proprement** : mettre à jour [le plan directeur](PLAN-DIRECTEUR.md) (ligne du chantier, preuves, point de reprise) et les guides touchés dans la même PR ; déclarer ce qui n'a pas été vérifié.
9. **Autorisations de NOxygen59** obligatoires pour toute fusion, release, changement de version, de dépendance ou de fork, changement de réglage GitHub (visibilité, protection, Actions, facturation), essai sur appareil ou changement majeur d'architecture. Un commentaire d'agent n'est pas une autorisation.

### Phrases types pour NOxygen59

Une ligne suffit à lancer l'agent suivant ; le reste est sur GitHub :

- « Lis `AGENTS.md`, vérifie GitHub, puis traite l'Issue #N. Ne fusionne pas. »
- « Fais la revue indépendante de la PR #N selon `docs/GOUVERNANCE-ET-REPRISE.md`. Ne pousse rien sur sa branche. »
- « Réponds à la revue de la PR #N et corrige ce qui est justifié. »

## Définition d'un travail terminé

Le comportement demandé est présent ; le diff reste limité ; le code significatif est documenté selon [CONTRIBUTING.md](../CONTRIBUTING.md) ; la PR contient sa passation ; les données et iOS 16 sont préservés ; les contrôles adaptés ont un résultat et un environnement ; les documents du domaine sont à jour ; les tests ignorés et la recette iPad manquante sont visibles ; aucune release n'est fabriquée sans demande. Un travail peut être intégré avec une limite connue explicitement acceptée, mais ne devient pas pour autant « confirmé sur iPad ».

## Indicateurs utiles

Suivre les anomalies de perte/décalage de données, le temps pour reproduire un incident, les tests de risque disponibles, les scénarios iPad non essayés, le temps d'ouverture/lecture à froid et les pics mémoire par modèle. Éviter les objectifs de lignes commentées, nombre d'abstractions ou couverture à 100 % sans rapport avec les usages.
