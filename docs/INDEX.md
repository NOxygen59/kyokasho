<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Documentation de Kyōkasho

Ce dossier organise la reprise du projet à partir de **v1.3, build 40**. L'audit du 25 octobre 2026 porte sur le commit `16d2dd89e4cb811b0bc956ef2a225431ed83864a`, dont le code applicatif correspond à v1.3 (`7fb7362`). Ce n'est pas une nouvelle version de l'application.

## Choisir son point d'entrée

| Besoin | Document |
|---|---|
| Apprendre à utiliser l'app | [Guide utilisateur](GUIDE-UTILISATEUR.md) |
| Comprendre les capacités et les preuves disponibles | [Audit v1.3](AUDIT-V1.3.md) |
| Installer l'environnement et comprendre les modules | [Guide développeur et architecture](GUIDE-DEVELOPPEUR.md) |
| Comprendre ce qui est conservé, exporté ou effacé | [Données et sauvegardes](DONNEES-ET-SAUVEGARDES.md) |
| Vérifier une modification | [Stratégie de tests et recette iPad](TESTS.md) |
| Automatiser progressivement les contrôles | [CI et livraison](CI-ET-LIVRAISON.md) |
| Décrire un bug, lire un journal ou symboliser un crash | [Débogage](DEBOGAGE.md) |
| Chercher une corruption ou une fuite mémoire | [Mémoire, ASan, C++ et Swift](MEMOIRE-ET-SANITIZERS.md) |
| Contribuer sans casser les usages | [Contribution](../CONTRIBUTING.md) |
| Décider et suivre les chantiers | [Gouvernance et reprise](GOUVERNANCE-ET-REPRISE.md) |

## Sources conservées

- [Histoire du développement](HISTOIRE-DU-DEVELOPPEMENT.md) : récit et sources historiques, pas une preuve d'essai actuel.
- [Feuille de route](FEUILLE-DE-ROUTE.md) : consignes du propriétaire, passations, backlog historique et décisions. Les sections anciennes peuvent décrire une fonction remplacée.
- [Architecture de lecture](ARCHITECTURE-LECTURE.md) : contrats du pipeline texte et positions.
- [OCR](OCR.md) : moteurs et fonctionnement détaillé.
- [IA locale](IA-LOCALE.md) : rétroportages MLX/iOS 16, procédures et mesures datées.
- [Grammaire](GRAMMAIRE.md) : proposition, sans engagement d'implémentation.
- [Notes de v1.3](releases/v1.3.md) et autres notes dans `releases/` : périmètre de chaque livraison.

## Lire les statuts

**Implémenté** signifie visible dans le code ; **livré** signifie inclus dans une release identifiée ; **compilé** exige un résultat de compilation associé à un commit et une plateforme ; **testé sur Mac** exige un scénario exécuté ; **confirmé sur iPad** exige un retour explicite pour une version et un scénario. Aucun de ces statuts ne remplace les autres. Un test ignoré n'est pas réussi.

Les nouvelles pages décrivent l'existant et les recommandations séparément. Les instructions `AGENTS.md` et les décisions explicites de NOxygen59 restent prioritaires. Mettre à jour le document du domaine avec chaque changement ; garder l'historique historique et consigner les nouvelles preuves dans [TESTS.md](TESTS.md).
