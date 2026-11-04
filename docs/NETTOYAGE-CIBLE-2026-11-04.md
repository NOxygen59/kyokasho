<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Nettoyage ciblé — 4 novembre 2026

## Autorisation, base et périmètre

NOxygen59 autorise le 04/11 le lot préparé par Codex, avec copie préalable des fichiers et mise à la Corbeille des copies seulement après validation. Base : `a7ee0e8`, candidate locale 1.4.1 ; branche de travail indépendante `codex/nettoyage-cible`. Ce lot ne produit pas de candidate et ne change ni version, dépendances, formats enregistrés ou lexique. Aucun push ni fusion.

Trois changements seulement :

1. Les tests des variables de traduction reconnaissent réellement `%@`, `%lld`, `%llu`, `%d`, les largeurs/précisions, les positions et `%%`. Des cas négatifs rejettent type remplacé, variable manquante ou ajoutée, position zéro/hors limites et mélange de positions implicites/explicites. Les permutations et omissions explicitement positionnées, nécessaires au chinois, restent autorisées. La regex du contrôle des accords anglais est corrigée aussi. Le catalogue n'est pas modifié.
2. L'ancien dialogue « Corriger cette ligne » capture l'OCR, sa page source et l'indice à l'ouverture. Il utilise la garde déjà en place dans l'éditeur complet avant toute écriture et signale un refus par l'erreur visible du lecteur. Le nouvel éditeur, la propagation Ovis et les fonctions d'annulation restent inchangés.
3. La seule méthode interne `DocumentAnalysisService.shiftReport`, sans appel de production, est retirée. Le décalage actuel de PageShift et `reloadAfterPageShift` restent en place. La méthode homonyme des adaptateurs de tests est conservée : elle appartient à un autre type.

`TapZones`, ses tests, les clés Codable historiques et les API publiques testées sont conservés. Aucune modification du worktree de Claude.

## Preuves et limites

- Avant correction : les deux cas de reconnaissance des formats échouent (`[]` au lieu des variables) ; les trois contrôles de câblage du dialogue échouent sur l'ancien code.
- Après correction : `python3 -B -m unittest discover -s tests -v` : **61 tests réussis**.
- `swift test --package-path Packages/KyokashoKit --disable-automatic-resolution` : **436 tests comptabilisés, 429 réussis, 7 ignorés, zéro échec**, dans neuf cibles. Les ignorés demandent des assets externes et ne constituent pas une validation des moteurs réels.
- Compilation iOS Release générique, sans signature : **BUILD SUCCEEDED**, code de sortie 0. Commande : `xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/codex-validation/DerivedData -clonedSourcePackagesDirPath build/codex-validation/SourcePackages -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`.
- Contrôle documentaire : **161 liens, zéro erreur** ; `git diff --check` propre. `project.yml`, les deux `Package.resolved` et le catalogue de traductions sont inchangés par rapport à la base.
- Les trois contrôles Python du dialogue vérifient le câblage dans les sources ; ils ne simulent pas SwiftUI ni une interaction sur iPad. Les essais matériels restent non effectués.

Les journaux complets restent locaux, dans `build/codex-validation/` du worktree (ignoré par Git). Les dépendances sont utilisées depuis les révisions figées, sans mise à jour.

Environnement : Mac arm64, Xcode 27.2 (`27B52`), Swift 6.4.2 ; compilation de l'app pour iOS générique, minimum iOS 16.0. Le premier lancement Swift sous sandbox a été refusé par `sandbox-exec` avant les tests ; la relance autorisée avec accès aux caches a réussi.

## Mini-recette à réaliser sur une future candidate autorisée

Utiliser un PDF synthétique et préciser la version réellement installée ; ne pas annoncer ces essais comme faits.

| Cas | Attendu | État |
|---|---|---|
| Texte brut, menu « Corriger cette ligne », modification puis Garder, fermeture/réouverture | Correction conservée sur la bonne ligne | Non essayé iPad |
| Même dialogue, Annuler | Texte et corrections inchangés | Non essayé iPad |
| Ouvrir le dialogue pendant un OCR lent, attendre qu'il remplace le texte, puis Garder | Refus visible, nouvelle lecture non écrasée par un ancien indice | Non essayé iPad |
| Ouvrir le nouvel éditeur, corriger et annuler une correction Ovis | Comportement de la base 1.4.1 conservé | Non essayé iPad |

Si le menu contextuel n'est pas accessible sur l'appareil, noter ce scénario non essayé ; le bouton dédié reste utilisable. Aucun simulateur ni installation automatique n'est autorisé par cette fiche.

## Sauvegarde et reprise

Les six fichiers existants à modifier sont copiés et comparés octet pour octet avant édition, hors dépôt. Les nouveaux fichiers sont identifiés par le diff Git. Conserver les copies si un contrôle échoue ; après validation Mac/iOS et commit local, les placer à la Corbeille conformément à la demande du manager, avec résultat consigné dans le pont. Le commit de base reste accessible pour comparer/revenir au code initial ; un retour arrière du code ne doit jamais être assimilé à une restauration des données.

Avant intégration, Claude relit le diff final depuis `a7ee0e8`, en particulier le chemin de correction OCR. Si sa branche a avancé, comparer les fichiers concernés avant toute intégration ; ne pas remplacer ses fichiers par une copie complète. Fusion uniquement sur accord précis du manager.
