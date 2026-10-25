<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Contribuer à Kyōkasho

Le projet sert d'abord l'iPad et les usages de NOxygen59. Professionnaliser signifie rendre les changements compréhensibles, vérifiables et réversibles ; cela n'impose pas une architecture d'entreprise ou une réécriture.

## Avant de modifier

Lire [AGENTS.md](AGENTS.md), [la feuille de route](docs/FEUILLE-DE-ROUTE.md), puis le guide du domaine dans [l'index](docs/INDEX.md). Avant MLX : [IA locale](docs/IA-LOCALE.md). Identifier un comportement attendu, le scénario qui démontre le problème et les données à préserver. Inspecter les changements déjà présents ; ne pas les écraser.

Pour un changement significatif, ouvrir une branche et une PR explicite. Le lot de reprise utilise cette voie pour rendre la documentation relisible avant intégration ; cela ne révoque pas les autorisations antérieures d'envoi sur `main`. Les releases restent demandées et numérotées par NOxygen59.

## Une intervention, un objectif

1. Écrire le problème observable et le critère de fin ; nommer le périmètre exclu.
2. Localiser le responsable dans le code et chercher les tests existants. Reproduire un bug avant de le corriger ; distinguer hypothèse et cause démontrée.
3. Ajouter un test pertinent pour la correction fonctionnelle, puis faire le plus petit changement utile. Ne pas mêler refactorisation, mise à jour des dépendances et nouvelle fonction dans le même lot.
4. Exécuter les contrôles adaptés. Une modification de documents demande liens et diff ; une modification d'API ou stockage demande compilation et tests ; un changement de gestes demande recette iPad.
5. Relire le diff avec un regard critique : erreurs, annulation, concurrence, stockage, iOS 16, licences et documentation. Une seconde passe n'implique pas nécessairement un autre agent.
6. Commiter en français et décrire preuve et limites dans la PR. Aucune affirmation d'essai iPad sans retour réel.

## Style et commentaires

Conserver le style du module, choisir des noms précis et éviter les abstractions sans second usage démontré. Les commentaires expliquent surtout le **pourquoi**, les invariants et les contraintes iOS 16. Commenter chaque ligne augmente le bruit et le risque de documentation périmée.

Documenter les API significatives avec `///` en Swift ; pour C/C++, indiquer propriétaire, encodage, durée des pointeurs, gestion des nulls et libération en cas d'erreur. Ne pas reformater tout un composant tiers pendant une correction locale. Garder copyrights et licences originaux ; utiliser les en-têtes SPDX adaptés au langage pour les nouveaux fichiers originaux.

## Données et compatibilité

Aucun PDF personnel, poids, dictionnaire ou donnée tierce dans Git. Les exemples sont synthétiques et générés hors des sources versionnées. Ne jamais ajouter un journal brut contenant des informations personnelles ou des identifiants. Les secrets restent dans leur mécanisme local/trousseau ; on ne demande pas à NOxygen59 de les coller dans un chat ou une PR.

Une migration de base s'ajoute sans réécrire les migrations livrées. Un effacement ou un changement de cache doit décrire exactement les données touchées, surtout les OCR retouchés. Le retour arrière d'un commit ne répare pas automatiquement une donnée migrée.

Respecter iOS 16.0 minimum et les forks MLX validés. Les permissions de fichiers de l'assistant et les autorisations de l'utilisateur sont des contraintes distinctes ; ne pas contourner une restriction en lançant un autre outil.

## Contenu attendu d'une PR

- Problème concret et comportement obtenu, avec exemple avant/après si utile.
- Périmètre des fichiers et décisions nécessaires au lecteur.
- Commandes réellement exécutées, plateforme, succès/échecs/ignorés et référence du journal.
- Risques de données, scénario iPad encore nécessaire et retour arrière réaliste.
- Documents modifiés ; pas de nouvelles cases « confirmé » par supposition.

Un changement de documentation peut être intégré sans nouveau `.tipa`. Ne pas changer `MARKETING_VERSION`, build, tags, release ou `latest.json` pour ce seul motif.
