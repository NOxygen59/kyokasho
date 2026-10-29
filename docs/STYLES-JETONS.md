<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Styles de l'app : jetons et inventaire

Référence du chantier des styles (plan local `PLAN-THEMES-STYLES.md`, décisions de NOxygen59 du 29/10/2026).
Un **jeton** est une valeur visuelle nommée par son rôle (« texte sur couleur de fonction »), jamais par sa valeur
(« noir »). Les vues lisent les jetons ; seuls `Themes.swift` (palettes) et `Styles.swift` (styles) contiennent des
valeurs. **Avant d'ajouter un jeton, vérifier ici qu'aucun ne joue déjà ce rôle.**

Ce qui ne dépend jamais du style : les pages du manuel (PDF, papier, fond de page choisi), l'encre des notes et des
dessins, les furigana dessinés sur la page, les fichiers exportés.

## 1. Catalogue des jetons

### Couleurs de palette (`Theme`, lues par `Atelier`)

| Jeton | Rôle |
|---|---|
| `Atelier.canvas` | fond de l'app |
| `Atelier.surface` | panneaux |
| `Atelier.surfaceHigh` | éléments posés sur un panneau |
| `Atelier.hairline` | séparateurs fins |
| `Atelier.textPrimary`, `textSecondary`, `textTertiary` | texte principal, légende, indication |
| `Atelier.Tint.read`, `annotate`, `japanese`, `ai`, `cloud` | une couleur par fonction : lecture, annotation, japonais, IA, import |

### Style (`AppStyle`, lu par `Atelier`), depuis S1a et S1b

| Jeton | Rôle | Valeur « Atelier » |
|---|---|---|
| `AppStyle.isLight` / `colorScheme` | interface claire ou sombre d'iOS (menus, alertes, clavier) | sombre |
| `AppStyle.cornerScale` / `Atelier.corner(_:)` | facteur de tous les arrondis de l'interface (0 = angles droits) ; `corner(n)` = valeur d'origine × facteur | 1 |
| `Atelier.radius`, `smallRadius` | arrondi des panneaux, des petits éléments (`corner(18)`, `corner(11)`) | 18, 11 |
| `Atelier.onAccentInk` | texte ou icône posé sur une couleur de fonction pleine | noir (opacité propre à chaque usage) |
| `Atelier.shadow` | ombre portée | noir |
| `Atelier.scrim` | voile derrière une fenêtre au premier plan | noir |
| `Atelier.contrastInk` | contraste maximal sur le fond de l'interface | blanc |

### Mesures et typographie (existants, encore fixes)

`Atelier.gap` (14), `Atelier.panelWidth` (372), `Atelier.display(_:)`, `Atelier.label`, `Atelier.mono`, `Atelier.jp`.

Gardes automatiques (`StyleTokensGuardTests`) : aucun nouveau blanc ou noir en dur dans `App/` ; aucun arrondi en dur, sauf les 2 dessins posés sur la page (`ReaderScreen`, `Path(roundedRect:)`).

## 2. Inventaire des valeurs directes restantes (29/10/2026, branche `claude/styles-s1`)

| Famille | Valeurs directes | Fichiers | Remarque |
|---|---|---|---|
| Couleurs `Color(hex:/red:/white:/uiColor:)` | 115 | 9 | presque toutes dans `Themes.swift` (palettes, normal) |
| Couleurs système nommées (`Color.red`, `UIColor.systemOrange`…) | 15 | 11 | surbrillances de la page (à garder), quelques états d'interface (rouge de sélection, vert « Recommandé ») à passer en jetons d'état |
| Styles iOS `.secondary` / `.primary` / `.tertiary` | 117 | 30 | suivent déjà clair ou sombre, mais pas la palette : à aligner sur `textSecondary` et `textTertiary` au cas par cas |
| Opacités en dur `.opacity(0.x)` | 80 | 23 | souvent des états (appuyé, désactivé) : jetons d'état |
| Fonds `.background(` / remplissages `.fill(` | 76 / 43 | 29 / 18 | la plupart lisent déjà un jeton de couleur ; la forme, elle, est en dur |
| Bordures `.stroke` / `.strokeBorder`, épaisseurs `lineWidth:` | 25 / 20 | 10 / 6 | aucun jeton de bordure aujourd'hui |
| Ombres `.shadow(` | 8 | 8 | couleur en jeton (S1b), rayon et décalage en dur |
| Matières (`.regularMaterial`, `.thinMaterial`…) | 7 | 5 | pilules et fenêtres d'avertissement ; `AtelierPanel` sans flou (batterie) |
| Arrondis en dur | ~~38~~ 2 | 1 | **lot 2a fait** : 37 passent par `Atelier.corner`, `radius` ou `smallRadius` ; restent les 2 dessins sur la page |
| Capsules et cercles | 44 | 22 | formes voulues (pastilles) : à garder, la bordure et le fond suivront les jetons |
| Marges `.padding(` en dur | 188 | 32 | |
| Espacements `spacing:` en dur | 228 | 48 | surtout 10, 6, 8, 2, 12 : une échelle de 6 à 8 crans suffit |
| Tailles `.frame(width/height:` en dur | 80 | 27 | souvent des zones de toucher et des icônes : garder 44 points minimum |
| Polices à taille fixe `.system(size:` | 93 | 29 | **ne suivent pas la taille dynamique du texte** (accessibilité) |
| Styles de texte iOS (`.title`, `.caption`…) | 251 | 39 | suivent la taille dynamique : bonne base |
| Animations | 47 | 14 | 9 usages respectent déjà « Réduire les animations » |

Fichiers les plus chargés en valeurs directes : `LibraryView` (74), `ReaderScreen` (67), `StudyPanel` (58),
`AIModelViews` (32), `DictionaryViews` (30), `Atelier` (23), `DriveViews` (21), `ReviewScreen` (20),
`AITaskCenter` (20), `ReaderSheets` (16).

## 3. Jetons à créer (prochains lots), sans doublon

| Famille | Jetons prévus | Remplace |
|---|---|---|
| Forme | fait : `cornerScale` et `corner(_:)` (pas de jetons par taille : chaque arrondi garde sa valeur d'origine × le facteur du style) | — |
| Bordure | `borderWidth`, `borderColor`, `focusRing` | 25 bordures et 20 épaisseurs |
| Relief | `panelShadow` (rayon, décalage, opacité), `panelMaterial` (aucun, verre) | 8 ombres, 7 matières |
| État | `selected`, `pressed`, `disabled`, `danger`, `success` | opacités et couleurs système d'interface |
| Espacement | échelle `space.xxs` à `space.xl` (2, 4, 6, 8, 12, 16, 24) | 188 marges, 228 espacements, à reprendre au fil des composants |
| Typographie | rôles (`title`, `body`, `caption`, `label`, `mono`, `jp`) fondés sur les styles de texte iOS, pour garder la taille dynamique | 93 tailles fixes |

Règle des lots de fondation : chaque remplacement garde **exactement** la valeur actuelle pour le style Atelier.
Les écarts d'une ou deux unités entre usages ne sont pas « arrondis » pendant la fondation : ils le seront lors de
l'harmonisation des composants (lot 4), avec une comparaison avant et après.
