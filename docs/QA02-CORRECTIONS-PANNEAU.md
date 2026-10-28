<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# QA02 — lot 3, panneau OCR O01/O05

## Contrat et portée

Base `28d8b4c`, retour rapporté sur iPad QA02 1.3 build 40. Autorisation du chat du 26/10/2026 :
corrections minimales, PR distinctes, aucune fusion/candidate. Aucun changement des modes du panneau,
des données documentaires, de PDFKit, des dépendances/forks, des versions ou d'Actions.
O05 : même géométrie avant/après relâchement ; petits gestes effectifs après rotation ; poignée accessible.
O01 : mesurer avant toute modification de routage des gestes. Pas de remplacement de WebKit.

## O05 — preuves précises et correction

Dans la base, `w` inclut déjà `resize.width`, puis la fin du geste enregistre `w + translation.width`.
Même calcul pour hauteur, `left` et `top`. Si la closure est celle du dernier rendu SwiftUI, pour
x=120 et déplacement=20 : aperçu=140, valeur enregistrée=160. La correction évite cette dépendance
à la capture en appliquant la translation une seule fois au rectangle de départ.
La capture exacte sur iOS 16 n'a pas été reproduite : ce risque arithmétique n'est pas une preuve appareil.

Un second mécanisme est déterministe, sans hypothèse sur les closures : après réduction de la zone
à 700 points, une largeur persistée de 900 donne encore 700 après un petit geste de -10
(`min(900 - 10, 700)`). Il faut parcourir 200 points avant de voir un effet : zone morte/sensation
« aimantée ». Même problème pour une position persistée hors champ. Le nouveau calcul normalise
**avant** la translation : largeur visible 700 → 690 dès -10.

`FloatingPanelGeometry` sert à l'aperçu et à la validation. Le redimensionnement garde le coin supérieur
gauche fixe et borne le coin inférieur droit à la place restante ; aucune translation implicite de
la fenêtre quand elle grandit. Les dimensions minimum s'adaptent aux zones plus petites qu'elles.
La persistance du rectangle final ne lance pas d'animation. Rotation au milieu d'un geste reste à essayer.

Conformément à la règle des gestes non testés sur iPad, un retour au comportement antérieur est
accessible : Réglages → Lecture et apparence → Fenêtre texte OCR → « Stabiliser les gestes du panneau
flottant ». Activé par défaut ; désactivation possible pour comparer, sans effacer les réglages.

## O01 — cause encore inconnue

Le contenu HTML, dimensionné à sa hauteur, est dans le ScrollView SwiftUI ; son propre scroll WebKit
reste actif pour le texte vertical, les tableaux et le zoom. Cela rend possible plusieurs chemins
de défilement, sans prouver la cause du retard de 0,5 s. Aucun routage changé au hasard.

Instrumentation en mode diagnostic : événements HTML passifs wheel/touch/scroll, temps de passage
JS→Swift, offsets natifs WebKit et position du conteneur. Limite : deux événements par seconde et
catégorie ; aucun texte, image ou HTML dans le journal. L'observation KVO est faible et invalidée au
démontage ; aucun délégué de scroll WebKit n'est remplacé. Activation/désactivation à chaud suivie.
Le délai du pont ne prouve pas un délai de dessin. Il manque l'essai doigt/pointeur sur iPad, orientation,
mode, texte court/long et zoom, avec observation visuelle synchronisée aux traces.

## Validation locale

Mac arm64, macOS 27.0.1, Xcode 27.1, Swift 6.4 : cinq tests `FloatingPanelGeometryTests` réussis :
translation unique et gestes successifs, taille/origine au bord, rotation avec valeurs persistées hors
champ, zones petites/nulles, minimum et quatre bords. Suite Swift complète réussie (7 ignorés, assets absents).
Compilation Debug générique iOS réussie, minimum 16, sans signature ni installation.
Commandes : `swift test --package-path Packages/KyokashoKit --disable-automatic-resolution` avec
cache local existant et `xcodebuild ... -destination 'generic/platform=iOS' ... CODE_SIGNING_ALLOWED=NO build`.
Tests Python/documentation/diff et résolutions : résultats dans la PR.

Pas de test automatisé d'événements UIKit/WebKit, de simulateur, d'iPad, de modèle ou de candidate.
Les tests de géométrie ne certifient ni le rendu SwiftUI ni la fluidité réelle. Revue croisée requise
pour les changements d'interaction et le cycle de vie de l'observateur avant intégration.

## Fiche iPad (non exécutée)

1. Déplacer/redimensionner doucement au centre puis aux bords ; relâcher plusieurs fois : aucun saut.
2. Rotation et Split View, puis petit geste immédiat : réaction sans zone morte, poignée toujours accessible.
   Réouvrir le lecteur : rectangle dans la place disponible. Comparer l'option de stabilisation si nécessaire.
3. Texte court puis long, modes intégré/flottant, au doigt puis au pointeur, zoom normal puis agrandi :
   noter si la barre et le HTML bougent ensemble. Refaire le cas lent avec diagnostic, relever `ocr-scroll`.
4. Vérifier zoom horizontal/tableaux/texte vertical et ouverture du dictionnaire au toucher ; onglet,
   texte et données synthétiques conservés entre modes.

Tous ces essais sont non essayés. Retour arrière : option désactivée pour O05 ou abandon de cette PR.

## Revue Claude — 27 octobre 2026

Clé du repli centralisée dans `StudyPanelMotion.stableGesturesKey`. Interrupteur conservé jusqu’au test iPad. Le script et l’observation native ne sont installés que diagnostic actif ; désactiver retire les écouteurs du document courant, le script des navigations suivantes et l’observation KVO. Le pont dictionnaire reste disponible. Installation idempotente et nettoyage après navigation pour couvrir la désactivation pendant un chargement.

Test synthétique : `node scripts/test_ocr_scroll_diagnostics.cjs` exécute le script Swift réel dans un DOM simulé : installation, absence de doublons, limitation des événements, retrait et réactivation. Ce test ne valide pas WebKit/UIKit sur iPad.
