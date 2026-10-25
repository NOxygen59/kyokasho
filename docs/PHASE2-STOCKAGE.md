<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Phase 2 — correction ciblée de la reprise d'ajout de pages

Base : `16d2dd8` (code v1.3). Référence documentaire : PR #1, conservée séparément et non fusionnée. Aucun numéro de version, dépendance, fork MLX ou schéma SQLite n'est changé par ce lot.

## Défauts reproduits avant correction

Le commit de tests `4bb2afc` compile le véritable fichier `App/Library/PageShift.swift` dans une cible de tests Mac, via un lien symbolique. Seule la composition UI est doublée ; PDFKit, AppDatabase, ReviewStore et DocumentAnalysis sont ceux du projet. Trois tests échouent sur le protocole ancien :

1. Un journal `cards` ambigu est supprimé sans prouver que les cartes ont été déplacées.
2. Un journal `report` peut poursuivre jusqu'à sa suppression alors que le rapport est encore sur les anciens numéros.
3. Un journal `files` après installation des fichiers peut décaler une seconde fois les noms Markdown.

Ces mécanismes sont démontrés, mais ne sont pas déclarés comme la cause du retour intermittent historique de l'utilisateur.

## Correction réalisée

Avant toute mutation active : validation des PDF et des comptes de pages, copie du PDF original et fusionné, préparation d'un dossier de lectures IA aux noms finaux, préparation du rapport final, capture des pages finales des cartes. Une intention v2 est ensuite enregistrée atomiquement dans `page-shift.json`. Les échecs d'écriture ne sont plus ignorés.

La reprise réexécute les installations finales :

- La transaction AppDatabase ne décale que si le compte de pages est encore celui de départ ; le compte final dans la même transaction empêche de rejouer l'effet après un arrêt. Un compte inattendu bloque la reprise.
- Le PDF est identifié par son empreinte avant/après, pas seulement par son nombre de pages ; les copies restent disponibles.
- Le rapport et le dossier IA sont installés à partir de copies préparées immuables, jamais à partir des noms déjà déplacés. Les textes, traductions et retouches ne sont pas recalculés.
- Les cartes reçoivent leurs positions finales par identifiant dans une transaction. La planification FSRS, les champs et l'historique ne sont pas réécrits.
- Les caches sont invalidés et le journal n'est retiré qu'après réussite de l'ensemble. En cas d'erreur, il reste présent ; l'interface propose de réessayer au lieu de laisser l'utilisateur travailler sur un état partiel.
- Une base de secours en mémoire n'est pas acceptée pour cette opération. Les tâches IA sont revérifiées après l'attente de fusion, avant le commit synchrone.

Les copies `Application Support/Kyokasho/PageShift/<UUID>/` sont conservées après succès comme secours dans cette première phase. Elles occupent du stockage et ne sont pas des caches jetables. Aucune purge automatique n'est introduite avant qualification de la restauration. Une erreur avant l'écriture du journal peut laisser une copie préparatoire orpheline, sans changement des originaux.

## Compatibilité avec les opérations déjà interrompues

Le décodage reconnaît les anciens champs. Si le PDF est encore ancien et le compte de base permet une annulation certaine, l'ancien décalage SQL est annulé une fois. Pour les étapes `report`, `files`, `cards`, un PDF déjà nouveau ou un journal corrompu, l'ancien format ne contient pas assez d'information pour deviner l'état antérieur : journal et copies restent conservés, avec blocage explicite et réparation sur copie à préparer. Aucun ancien fichier n'est supprimé pour masquer l'incertitude.

Il faut terminer ou analyser une opération en cours avant de revenir à l'ancien binaire : l'ancien code ne sait pas reprendre un journal v2. Les schémas SQLite restent compatibles, mais cela ne rend pas le nouveau journal compatible avec l'ancien orchestrateur.

## Preuves exécutées sur Mac le 25 octobre 2026

- 15 tests PageShift, dont une matrice de 12 points d'arrêt avec reprises répétées et réouverture des vrais pools SQLite.
- Quatre sous-processus XCTest réellement tués par SIGKILL après commit de base, installation PDF, déplacement de l'ancien dossier IA et mise à jour des cartes ; nouvelle ouverture puis trois reprises par cas.
- Échecs SQLite injectés par triggers, erreur réelle d'écriture du rapport, journal initial non écrit, journal corrompu, copie PDF préparée manquante, repli en mémoire, ajout sans décalage et fusion incomplète.
- Vérification des coordonnées/contenus des notes et dessins, surlignages, repères, transformations, OCR conservé octet pour octet, rapports, Markdown/traductions, cartes FSRS et historique ; le second document reste inchangé.
- Le premier runner GitHub (Xcode 16.4 / Swift 6.1.2) a révélé une conversion implicite de tuple CGFloat/Double que Swift 6.4 accepte. Une conversion explicite de ces deux valeurs, sans changer le calcul, permet de compiler sur les deux toolchains ; les tests géométriques existants restent exécutés.
- Suite complète : 157 tests comptabilisés, 150 exécutés sans échec et 7 ignorés (modèles ONNX/UniDic absents).
- ASan : les 15 tests de reprise passent dans une compilation distincte instrumentée. Le premier lancement des sous-processus instrumentés avait échoué car le runtime était chargé trop tard ; le harnais précharge désormais le runtime livré dans son bundle de test, avant son chargement. Un témoin C++ indépendant confirme la détection d'un accès après libération.
- Apple Clang de ce Mac refuse `-fsanitize=leak` sur `arm64-apple-darwin27.0.0` : aucune campagne LeakSanitizer n'est revendiquée.
- Compilation complète Debug pour destination générique iOS, minimum iOS 16, sans signature : réussie, avec les résolutions versionnées. Aucun appareil, simulateur, archive de release ou `.tipa` n'est créé.

Les journaux complets restent locaux : ils peuvent contenir des chemins de machine. Le workflow `storage.yml` exécute les tests sur un runner Mac sans modèles et contrôle que les résolutions restent inchangées ; son résultat distant est à lire sur la PR, séparément des preuves locales.

## Procédure mémoire reproductible

```sh
swift test --package-path Packages/KyokashoKit --disable-automatic-resolution \
  --scratch-path .build-asan --sanitize address --filter PageShiftRecoveryTests
```

Le répertoire de compilation est séparé, et l'ASan couvre uniquement les chemins CPU instrumentés réellement exercés. MeCabC est compilé, mais l'analyse contextuelle avec UniDic n'est pas validée sans dictionnaire. Les bibliothèques binaires ONNX, les kernels GPU Metal, l'inférence MLX et la mémoire de l'iPad ne sont pas validés par ces tests. Pour Swift : compléter plus tard par Memory Graph et durées de vie des tâches ; pour C/C++ : harness et vrais assets autorisés ; pour MLX/Metal : mesures de chargement, génération, déchargement et ressources GPU sur un scénario fixe. ASan du paquet TrollStore reste à qualifier séparément.

## Limites avant intégration

### Complément de revue indépendante — 25 octobre 2026

Un test utilisant le vrai `OCRService` a reproduit une écriture tardive sur la page 0 après insertion de deux pages avant le livre : l'appelant annulé n'arrêtait pas le moteur détaché, et le résultat était enregistré avec l'ancien index. L'ajout attend désormais les OCR déjà démarrés du document, interdit les nouveaux calculs et écritures durant le changement, puis vérifie à nouveau cet état juste avant la sauvegarde d'un résultat. Une erreur avant journal rouvre l'OCR ; si un journal durable reste en attente, la reprise doit réussir avant de le rouvrir. Les tâches IA suivies par l'interface sont revérifiées après cette attente.

`PDFPool.release` attend un verrou partagé avec les rendus. Cet appel a été déplacé hors du fil principal et avant la mutation des fichiers, dans le même intervalle où les nouveaux OCR sont interdits. Un compteur de génération rejette aussi les réponses de l'ancien PDF qui seraient reprises par l'acteur OCR après la fin du déplacement. Un test retient le verrou deux secondes et vérifie que le fil de l'interface continue à répondre. Les tests supplémentaires couvrent le résultat tardif, la concurrence, les écritures manuelles, l'annulation, l'erreur préalable et la reprise. Les journaux des nouvelles exécutions sont conservés hors du dépôt, dans le rapport de revue.

Cette correction ferme le chemin `OCRService` exercé par les tests. Les autres écritures différées de l'application, les grands PDF sur iPad, la coupure d'alimentation et les réparations d'anciens journaux ambigus restent à qualifier sur une copie.

Sur cette branche corrigée : 20 tests PageShift passent, dont cinq nouvelles régressions ; la suite KyokashoKit compte 162 tests, 7 ignorés et aucun échec. Les 20 tests PageShift passent également sous ASan Mac après la dernière modification du service OCR. Ces preuves ne comprennent pas un essai sur iPad.

La résistance à une coupure d'alimentation ou à une corruption physique du stockage n'est pas démontrée par SIGKILL. Les écritures atomiques ne constituent pas à elles seules une garantie de durabilité matérielle. Les erreurs pendant la fusion avant le commit ne doivent toucher que les temporaires : un PDF fusionné incomplet est refusé par l'orchestrateur, mais tous les chemins UIKit de sélection/partage ne sont pas automatisés ici.

La nouvelle interface de reprise et les grandes bibliothèques restent à essayer sur iPad : espace disque nécessaire, temps des copies/hachages, présentation du blocage et réessai. Le protocole privilégie les données ; il peut conserver des copies importantes et effectue encore ces opérations synchrones comme l'orchestrateur précédent. Toute optimisation devra préserver les tests d'interruption. Aucune promesse de fonctionnement iPad n'est faite.
