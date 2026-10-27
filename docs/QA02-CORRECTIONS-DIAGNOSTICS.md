<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# QA02 — lot 1, diagnostics O10 / P04

## Contrat et preuves

Base : `431f1c6`, candidate rapportée sur iPad 1.3 build 40. Autorisation de NOxygen59 dans le chat
du 26 octobre 2026 : corriger les trois lots dans l'ordre, PR séparées, sans fusion ni candidate.
Objectif : consultation fiable des données disponibles, sans refonte du diagnostic ni suivi automatique.
Invariants : export et données inchangés, iOS 16, aucun modèle ni dépendance changé.

Le code initial chargeait un `@State` du parent uniquement utilisé dans la feuille, juste avant
`showLog = true`. La feuille possède maintenant son état et lit à son apparition : plus de dépendance
à cette capture initiale. Le scénario SwiftUI exact n'a pas été reproduit sur appareil ; ce mécanisme
est une hypothèse ciblée pour l'écran initial vide, pas une preuve de la cause vécue sur iPad.

Autre défaut démontrable : la rotation conserve un suffixe d'octets pouvant commencer au milieu
d'un caractère japonais. Le décodage UTF-8 strict échoue alors alors que le fichier contient encore
des lignes. Le test synthétique vérifie cet échec puis la lecture tolérante du reste. Aucune réécriture
du fichier exporté. Les écritures déjà en file sont terminées avant la lecture.

Absence de rafraîchissement : distincte du premier affichage ; ajout d'« Actualiser » manuel.
Fichier absent, fichier vide et erreur ne sont plus confondus.

P04 : les pastilles ouvrent un popover de tâches actives ; le détail n'existe que si une tâche a
un journal non vide et disparaît avec la tâche. Aucun accès au journal persistant n'existait ici.
Ajout d'un accès explicite au même lecteur, et d'un événement diagnostic d'ouverture sans contenu
personnel. Le popover et sa feuille imbriquée restent à confirmer sur iOS 16.

## Validation locale

Mac arm64, macOS 27.0.1, Xcode 27.1, Swift 6.4. Commandes :

- `swift test --package-path Packages/KyokashoKit --scratch-path <cache-local-existant> --disable-automatic-resolution` : suite réussie, deux nouveaux tests DiagnosticLogSnapshot ; 7 ignorés faute d'assets externes.
- `python3 -m unittest discover -s tests -v` : 16 tests réussis.
- `python3 scripts/check_documentation.py` et `git diff --check` : réussis.
- Résolutions des deux packages inchangées.
- Compilation Debug `generic/platform=iOS`, sans signature : résultat consigné dans la PR.

Les tests de lecture couvrent absent, vide, texte japonais, remplacement puis relecture, erreur (dossier),
et UTF-8 coupé. Ils ne testent pas la présentation SwiftUI. Pas de test UI disponible dans le projet.
Pas de simulateur, iPad, modèles MLX ni candidate. Revue croisée encore requise avant intégration.

## Fiche iPad (non exécutée)

1. Sur document synthétique, activer le diagnostic et effectuer une action OCR connue ; ouvrir le
   journal, comparer les dernières lignes à l'export. Fermer/rouvrir : texte présent dès l'ouverture.
2. Laisser le journal ouvert pendant une nouvelle action : « Actualiser » montre les nouvelles lignes.
3. Toucher une pastille IA, ouvrir le journal puis revenir au détail de la tâche ; recommencer après
   sa fin tant qu'une pastille reste visible. Vérifier qu'« Arrêter » conserve ses deux confirmations.

Noter pour chaque essai : résultat, SHA de la future candidate, orientation et périphérique.
Arrêt de ce travail avant fabrication/installation d'une candidate ; retour arrière par abandon de la PR.
