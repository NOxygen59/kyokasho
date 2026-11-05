<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Huit univers visuels — 05/11/2026

Demande NOxygen59 : thèmes plus stylisés et uniques selon leur nom, « Très distincte et expressive ». Première ébauche à 23 styles jugée trop répétitive ; décision explicite du manager : **6 à 8 univers réellement distincts**. La livraison retient huit univers, avec des couleurs secondaires repliées.

Base `57deec9` (candidate 1.4.4), branche `codex/identite-themes`, worktree Codex réutilisé `/Users/noxygen/.codex/worktrees/kyokasho-lexique-langues/wt-rotation`. Le nom historique de ce dossier ne décrit plus sa tâche ; la branche du lexique est conservée dans Git. Aucun changement de la branche de Claude.

## Résultat

| Univers principal | Formes et typographie | Signature |
|---|---|---|
| Atelier | panneaux arrondis, SF, titres semibold | graphite, menthe, grille d'atelier |
| Wabi-Sabi | panneaux asymétriques doux, serif, titres légers | terre, argile, strates et cercle ouvert |
| Swiss Design | angles droits, titres lourds, sans ombre | blanc, rouge, composition géométrique asymétrique |
| Neo-Brutalism | angles droits, chasse fixe, bord épais et ombre dure | crème, bleu franc, aplats découpés |
| Glassmorphism | panneaux vitrés et arrondis, titres légers | base claire, volumes transparents ; matériaux disponibles sur iOS 16 |
| Synthwave | arrondis courts, titres gras et police arrondie | violet/cyan/rose, soleil rayé et perspective rétro |
| Cyberpunk | panneaux biseautés, chasse fixe et ombre dure | pétrole/jaune/cyan, circuits et signalétique ; aucun soleil rétro |
| Luxury Typography | cadres presque droits, serif, titres légers | encre et or, double filet sans ombre |

Les différences de panneaux sont réelles (`AtelierPanel`), pas seulement dessinées dans les cartes. Le fond est lié à l'univers, les couleurs restent remplaçables dans « Palette », désormais replié et compact. Les boutons et zones tactiles gardent leurs structures existantes ; ce lot ne refait pas la disposition de la bibliothèque.

## Compatibilité et invariants

- Les 23 identifiants historiques restent reconnus par `AppStyle.all`, et les 17 palettes restent disponibles. Seuls les huit univers sont présentés comme choix principaux (`featured`). Un ancien style déjà enregistré reste chargé et son nom est affiché ; aucun `UserDefaults` n'est migré ou réécrit à l'ouverture.
- Glass propose maintenant Clair ; Cyberpunk propose Lagon avec lecture jaune, japonais vert d'eau et import cyan. Cela s'applique au prochain changement de style, sans remplacement forcé d'une palette enregistrée. Pour réappliquer la palette proposée à un style déjà actif, choisir un autre univers puis revenir, ou choisir la palette directement.
- Identifiants et libellés localisés conservés ; aucune nouvelle clé d'interface. PDF, encre, repères, export et logique OCR inchangés.
- Motifs statiques, originaux, désactivables ; pas d'image tierce, nouvelle police, dépendance ou API Liquid Glass récente. Les boucles de fibres/pétales sont bornées ; pas de nouveau flou généralisé.
- Le helper d'ombre existant accepte un style et une teinte explicites pour que les aperçus représentent leur propre choix, pas le style global.

## Vérification indépendante de l'auteur

- Les sept vrais fichiers Swift de design sont vérifiés avec `swiftc -typecheck`, SDK iPhoneOS et cible `arm64-apple-ios16.0`. Deux adaptateurs hors dépôt fournissent seulement les interfaces inchangées `AppLanguagePicker` et `UIColor.hexString`. **Ce n'est pas une compilation complète ni un lien de l'app.**
- Les vrais `StyleTokensGuardTests` et `ThemeContrastTests` sont recompilés seuls dans un bundle XCTest Mac : **10 tests réussis, 0 échec**. Ils contrôlent les jetons et les contrastes AA des palettes claires, pas tous les pixels après composition des motifs ou du verre. L'unique adaptation du garde-fou autorise le nouveau consommateur du helper d'ombre.
- Planche SwiftUI Mac rendue avec les vraies vues de fond, de forme et d'aperçu, les vraies définitions de styles/palettes. Les sources Theme du rendu retirent uniquement le sélecteur et le gestionnaire iOS et adaptent la fonction CSS inutilisée. Assertion : huit choix principaux, 23 styles historiques, 17 palettes. Géométrie des trois formes contrôlée dans les rectangles normaux et minuscules, inset excessif vide.
- Planche finale inspectée : huit cartes, Cyberpunk distinct de Synthwave ; les premières planches à 23 cartes sont obsolètes et remplacées.
- `git diff --check` réussi ; contrôle documentaire local réussi. Les résultats et les PNG sont hors Git dans `/Users/noxygen/Documents/Codex/Kyokasho-Pont/REVUES/APERCUS-THEMES-2026-11-05/`.
- Copies initiales des quatre fichiers de design existants dans `/Users/noxygen/Documents/Codex/Kyokasho-Backups/2026-11-05-identite-themes/` ; base Git conservée pour le reste. Aucun nettoyage des anciens caches effectué.

**Non vérifié :** build complet de l'app iOS ou Catalyst, rendu réel iPad, performances CPU/GPU, tailles dynamiques extrêmes, VoiceOver réel, clavier et toutes les combinaisons couleur/style. Aucune candidate, fusion, version ou publication créée.

## Revue Claude ciblée

Relire le diff depuis `57deec9` sur `codex/identite-themes` :

1. `Styles.swift` / `Themes.swift` : `all` reste le catalogue de compatibilité, `featured` limite le sélecteur à huit ; aucune réécriture des choix au démarrage, comportement de fermeture des Réglages conservé. Contrôler un ancien style enregistré et les palettes personnalisées.
2. `StyledPanelShape.swift` / `Atelier.swift` : formes bornées, inset, remplissage/bordure cohérents ; ombres sur les formes, jamais sur le texte. Les valeurs par défaut du helper restent celles d'avant.
3. `ThemeBackdrop.swift` / `ThemeSignatures.swift` : motifs liés à l'univers, combinaisons de palette, option motifs désactivés, coût borné, absence d'animation.
4. `ThemePreview.swift` : vraie silhouette et style explicite, aperçu indépendant du choix global. Les styles translucides restent des matériaux iOS 16, pas une promesse de Liquid Glass natif récent.
5. Après éventuelle intégration autorisée : build iOS puis mini-recette sur les huit univers, fermeture/réouverture et persistance, fond sombre/clair, rotation, panneau OCR et bibliothèque, onglets, palette secondaire, motifs coupés. Regarder surtout les biseaux et le verre lors du défilement. Validation iPad par NOxygen59.

## Références de conception consultées

- [Bibliothèque nationale suisse — style international](https://www.nb.admin.ch/en/the-international-style-1950-1970) : grille typographique, sans serif, composition géométrique.
- [Apple — Materials](https://developer.apple.com/design/human-interface-guidelines/materials) : matériaux, hiérarchie et lisibilité. Inspiration adaptée aux matériaux classiques d'iOS 16.
- [Cyberpunk — référence graphique de CD Projekt](https://www.cdprojekt.com/pl/wp-content/uploads-pl/2016/03/20121018_CD_PROJEKT_RED.pdf) et [création HUD d'Andrei Dzemidzenka](https://www.behance.net/gallery/134977085/Sci-fi-UI-Cyberpunk-futuristic-collection-elements) : références pour distinguer signalétique jaune/cyan et rétro Synthwave. Aucun logo, asset, police ou code repris.

Skill `theme-factory` consulté pour évaluer sa pertinence, non appliqué : son processus de thèmes pour documents/présentations ne correspond pas à cette refonte native. Aucun nouveau skill nécessaire. Un guide visuel propre au projet, conservé ici, permet une reprise plus cohérente.
