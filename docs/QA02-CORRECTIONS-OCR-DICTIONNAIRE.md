<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# QA02 — lot 2, OCR et dictionnaire

## Contrat

O03 : après enregistrement d'une correction, le lecteur ouvert reflète le cache concerné ; les lignes
acceptées ne redeviennent pas douteuses et les lignes non acceptées restent à revoir.
O07 : établir la frontière qui cesse de répondre, sans présumer d'une cause commune avec O02.
Base indépendante `431f1c6`. Autorisation du chat du 26/10/2026 : correction et PR, aucune fusion/candidate.
Invariants : corrections manuelles conservées, pas de migration ni changement des moteurs, iOS 16 maintenu.

## O03 — preuve et correction

`DocumentAnalysisService.apply` et `applyOvisToDocument` enregistrent via `OCRService.store`, sans
événement destiné au lecteur. Celui-ci n'écoute que les fins de `AITaskCenter` et les lectures IA.
Son `ocrPage` reste donc périmé après cette voie de correction. Le test de notification échoue sur la
base (expiration de l'attente) puis passe après ajout d'un événement post-enregistrement.
Le lecteur filtre document/page/moteur et réutilise sa relecture existante, qui vérifie encore l'état
au retour de l'attente. Un compteur de requêtes empêche un ancien rechargement de publier
après une notification plus récente (deux corrections rapides). Aucun texte OCR n'est transporté par l'événement. Pas d'événement sur échec SQL.

Le chemin « Vérifier » appelait déjà `showOCR` après enregistrement et `corrected` pose `edited=true`,
`doubt=[]`. Nous ne changeons pas cette règle et ne masquons pas les autres lignes peu sûres.
Le test de réouverture SQLite conserve une ligne acceptée de faible confiance, la soumet au dictionnaire
et à une référence différente : elle reste intacte ; la ligne non acceptée reste signalée.
Cela n'établit pas quel chemin exact NOxygen59 avait utilisé : une alerte persistante après réouverture
réelle ou uniquement dans « Vérifier » demande encore un exemple synthétique précis.

## O07 et O02 — limites et instrumentation

Le survol de la page PDF utilise `UIHoverGestureRecognizer`, puis les caractères PDF/OCR, puis
`LookupSession`, puis une `WKWebView` pour les définitions. `RubyWebView` dans le panneau réagit aux
clics ; ce n'est pas le même trajet. Aucun mécanisme prouvé n'explique encore la panne durable rapportée.

Mode diagnostic seulement : activation du survol ; réception, recherche et présentation (bornées à
un événement par étape/seconde) ; absence de cache/caractère ; début et nombre de résultats de recherche ;
création/destruction web, fin/échec de navigation, réception de messages, arrêt du processus web.
Aucun texte cherché, titre, chemin ou contenu HTML ajouté aux traces. Aucun redémarrage web automatique.
O02 (miniatures) reste un indice ; aucun changement du sélecteur de pages.

## Preuves locales et limites

Mac arm64, macOS 27.0.1 / Xcode 27.1 / Swift 6.4 :

- Suite KyokashoKit complète après notification : réussie, 7 ignorés faute d'assets externes.
- Trois tests `OCRCorrectionNotificationTests` : réussis (notification après persistance et portée,
  absence sur échec, réouverture SQLite / ligne acceptée / doute résiduel / autre document).
- AddressSanitizer ciblé : les trois tests réussis, sans erreur détectée.
- Compilation Debug générique iOS sans signature : réussie.
- Tests Python : 16 réussis ; documentation : 141 liens, zéro erreur ; diff propre et résolutions inchangées.

Commandes : `swift test --package-path Packages/KyokashoKit --disable-automatic-resolution`
avec `--scratch-path` local ; ciblage `--filter OCRCorrectionNotificationTests`, puis `--sanitize address`.
Pas de simulateur, iPad, essai MLX ni candidate. Les tests ne pilotent pas UIKit/SwiftUI.
Revue croisée requise pour les notifications et la concurrence avant intégration.

## Fiche iPad (non exécutée)

1. Document synthétique : depuis l'analyse, accepter une correction en laissant le lecteur ouvert.
   Revenir au texte : correction visible, alerte réduite aux autres lignes. Réouvrir page puis app : identique.
2. Refaire depuis « Vérifier », puis avec une correction manuelle. Une relecture ne doit pas les remplacer.
3. Diagnostic activé : survol → correction → mode intégré/flottant → autre page/document → survol.
   Si panne : noter doigt/souris/trackpad/Pencil, dernière étape et traces `lookup` / `lookup-web`.
   Désactiver/réactiver le survol et relever le résultat avant tout redémarrage.
4. Noter séparément l'état des miniatures avant/après, sans conclure qu'il s'agit du même défaut.

État de tous ces essais : non essayés. Retour arrière : abandonner la PR ; aucune migration à inverser.
