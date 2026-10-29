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
| `Theme.isLight` / `colorScheme` | variante : nuit (sombre) ou clair et sépia ; mode clair ou sombre d'iOS partout (racine, lecteur, feuilles) |
| `Atelier.onAccentInk` (`Theme.onAccent`) | texte ou icône posé sur une couleur de fonction pleine |
| `Atelier.contrastInk` (`Theme.contrast`) | contraste maximal sur le fond de l'interface |
| `Atelier.shadow` (`Theme.shadowTint`) | teinte des ombres |
| `Theme.secondaryLevel`, `tertiaryLevel` | opacité de l'encre pour la légende et l'indication |

### Variantes (lot 3, planche choisie par NOxygen59 le 29/10/2026)

| Variante | Thèmes | Valeurs |
|---|---|---|
| Nuit | Atelier et les 10 autres thèmes d'origine | inchangées : encre sur accent noire, contraste blanc, ombre noire, niveaux 0,74 et 0,60 |
| Clair | `Theme.clair` | fond `#F4F2EE`, panneau `#FFFFFF`, encre `#1B2226`, teintes foncées, texte blanc sur teinte, niveaux 0,82 et 0,72 |
| Sépia | `Theme.sepia` | fond `#EFE4D0`, panneau `#F8F0E1`, encre `#3B2A1A`, teintes foncées, texte crème sur teinte, niveaux 0,82 et 0,75 |

`ThemeContrastTests` vérifie 4,5:1 pour clair et sépia, en lisant les valeurs dans `Themes.swift` : texte des trois niveaux sur les trois fonds, couleurs de fonction comme texte, texte sur couleur de fonction. Deux teintes de la planche (sépia lecture et notes) ont été foncées d'un cran pour passer sur le panneau le plus foncé.

### Style (`AppStyle`, lu par `Atelier`), depuis S1a et S1b

| Jeton | Rôle | Valeur « Atelier » |
|---|---|---|
| `AppStyle.cornerScale` / `Atelier.corner(_:)` | facteur de tous les arrondis de l'interface (0 = angles droits) ; `corner(n)` = valeur d'origine × facteur | 1 |
| `Atelier.radius`, `smallRadius` | arrondi des panneaux, des petits éléments (`corner(18)`, `corner(11)`) | 18, 11 |
| `AppStyle.shadowKind` / `.atelierShadow(opacity:radius:y:)` | ombre portée : douce (valeurs d'origine), dure et décalée, ou aucune | douce |
| `AppStyle.borderScale` / `Atelier.border(_:)` | facteur des épaisseurs de bordure de l'interface | 1 |
| `AppStyle.usesMaterials` / `Atelier.material(_:)` | matières floutées d'iOS, ou fond plein du panneau | oui |
| `AppStyle.panelFill` | fond des panneaux `AtelierPanel` : plein, ou verre flouté (plus coûteux en GPU) | plein |
| `AppStyle.panelEdge` / `.atelierGlow(_:)` | bord des panneaux : trait fin, encre pleine, ou néon de la couleur de lecture | trait fin |
| `.atelierSheet()` | fenêtre d'iOS habillée (#44) : fond du thème, coins du style (arrondis d'iOS pour Atelier) ; iOS 16.4 et plus, sinon apparence d'iOS | appliquée aux Réglages et aux feuilles du lecteur (pagination et réglages du document, recherche, IA, cartes) |
| `AppStyle.defaultTheme`, `summary` | palette proposée avec le style (remplaçable), ligne affichée dans le choix | `atelier` |
| `AppStyle.fontDesign` / `Atelier.font(_:weight:)` | famille du texte latin de l'interface (taille d'origine gardée) ; `atelierFontDesign()` l'applique aux styles de texte iOS dès iOS 16.1 | `.default` |
| `Atelier.scrim` | voile derrière une fenêtre au premier plan | noir |

### Mesures et typographie

`Atelier.gap` (14), `Atelier.panelWidth` (372) : encore fixes. `Atelier.display(_:)` et `Atelier.label` suivent `fontDesign` ; `Atelier.mono` (chasse fixe) et `Atelier.jp` (Hiragino) gardent leur famille, voulue.

Gardes automatiques (`StyleTokensGuardTests`) : aucun nouveau blanc ou noir en dur dans `App/` ; aucun arrondi en dur, sauf les 2 dessins posés sur la page (`ReaderScreen`, `Path(roundedRect:)`) ; aucune ombre ni matière en dur ; aucune épaisseur de bordure en dur, sauf le fond dessiné du thème et un trait posé sur la page.

## 2. Inventaire des valeurs directes restantes (29/10/2026, branche `claude/styles-s1`)

| Famille | Valeurs directes | Fichiers | Remarque |
|---|---|---|---|
| Couleurs `Color(hex:/red:/white:/uiColor:)` | 115 | 9 | presque toutes dans `Themes.swift` (palettes, normal) |
| Couleurs système nommées (`Color.red`, `UIColor.systemOrange`…) | 15 | 11 | surbrillances de la page (à garder), quelques états d'interface (rouge de sélection, vert « Recommandé ») à passer en jetons d'état |
| Styles iOS `.secondary` / `.primary` / `.tertiary` | 117 | 30 | suivent déjà clair ou sombre, mais pas la palette : à aligner sur `textSecondary` et `textTertiary` au cas par cas |
| Opacités en dur `.opacity(0.x)` | 80 | 23 | souvent des états (appuyé, désactivé) : jetons d'état |
| Fonds `.background(` / remplissages `.fill(` | 76 / 43 | 29 / 18 | la plupart lisent déjà un jeton de couleur ; la forme, elle, est en dur |
| Épaisseurs de bordure `lineWidth:` | ~~20~~ 14 | 2 | **lot 2b fait** : 6 de l'interface par `Atelier.border` ; restent le fond dessiné (13) et un trait sur la page |
| Ombres | ~~8~~ 0 | — | **lot 2b fait** : `atelierShadow`, mêmes valeurs |
| Matières | ~~7~~ 0 | — | **lot 2b fait** : `Atelier.material` ; `AtelierPanel` reste sans flou (batterie) |
| Arrondis en dur | ~~38~~ 2 | 1 | **lot 2a fait** : 37 passent par `Atelier.corner`, `radius` ou `smallRadius` ; restent les 2 dessins sur la page |
| Capsules et cercles | 44 | 22 | formes voulues (pastilles) : à garder, la bordure et le fond suivront les jetons |
| Marges `.padding(` en dur | 188 | 32 | |
| Espacements `spacing:` en dur | 228 | 48 | surtout 10, 6, 8, 2, 12 : une échelle de 6 à 8 crans suffit |
| Tailles `.frame(width/height:` en dur | 80 | 27 | souvent des zones de toucher et des icônes : garder 44 points minimum |
| Polices `.system(size:` | ~~93~~ 13 | 9 | **lot 2c fait** : 81 par `Atelier.font` ; restent les familles voulues (`design:`) et le texte de la page. **Taille dynamique toujours absente** : la rendre réglable change l'affichage, donc lot visuel à part, testé sur l'iPad |
| Styles de texte iOS (`.title`, `.caption`…) | 251 | 39 | suivent la taille dynamique : bonne base |
| Animations | 47 | 14 | 9 usages respectent déjà « Réduire les animations » |

Fichiers les plus chargés en valeurs directes : `LibraryView` (74), `ReaderScreen` (67), `StudyPanel` (58),
`AIModelViews` (32), `DictionaryViews` (30), `Atelier` (23), `DriveViews` (21), `ReviewScreen` (20),
`AITaskCenter` (20), `ReaderSheets` (16).

## 3. Jetons à créer (prochains lots), sans doublon

| Famille | Jetons prévus | Remplace |
|---|---|---|
| Forme | fait : `cornerScale` et `corner(_:)` (pas de jetons par taille : chaque arrondi garde sa valeur d'origine × le facteur du style) | — |
| Bordure | fait : `borderScale` ; restent à créer `focusRing` (lot 4, champs) | — |
| Relief | fait : `shadowKind`, `usesMaterials` | — |
| État | `selected`, `pressed`, `disabled`, `danger`, `success` | opacités et couleurs système d'interface |
| Espacement | échelle `space.xxs` à `space.xl` (2, 4, 6, 8, 12, 16, 24) | 188 marges, 228 espacements, à reprendre au fil des composants |
| Typographie | fait : `fontDesign`. Restent : taille dynamique (lot visuel), famille japonaise par style (Mincho ou Gothic), styles de texte iOS en iOS 16.0 | — |

Règle des lots de fondation : chaque remplacement garde **exactement** la valeur actuelle pour le style Atelier.
Les écarts d'une ou deux unités entre usages ne sont pas « arrondis » pendant la fondation : ils le seront lors de
l'harmonisation des composants (lot 4), avec une comparaison avant et après.

## 4. Styles disponibles

| Style | Formes | Bord et relief | Police | Palette proposée |
|---|---|---|---|---|
| Atelier | arrondis d'origine | trait fin, ombre douce | SF | Atelier (nuit) |
| Neo-Brutalism | angles droits | encre pleine × 2,5, ombre dure décalée, sans flou | chasse fixe | Brutal (clair) |
| Glassmorphism | arrondis × 1,2 | panneaux en verre flouté | SF | Lumière du soir (nuit) |
| Synthwave | arrondis × 0,5 | bord néon cyan, sans flou | arrondie | Synthwave (nuit) |
| Swiss Design | angles droits | trait fin, sans ombre ni flou | SF | Suisse (clair) |
| Wabi-Sabi | arrondis × 1,35 | trait fin, ombre douce | serif | Terre (clair) |

### S3 à S5 — styles ajoutés le 29/10/2026

| Famille | Styles | Différences portées par les jetons |
|---|---|---|
| Doux | Claymorphism, Neumorphism, Ethereal, Minimalism | volumes arrondis ou sobres, relief doux ou absent, verre réservé à Ethereal |
| Typographiques | Editorial Design, Luxury Typography, Victorian, Maximalism | serif, angles et bordures différenciés, palettes Clair, Encre, Sépia et Braise |
| Numériques | Cybercore, Cyberpunk, Y2K Aesthetic, Pixel Art | chasse fixe ou arrondie, néon, angles carrés, ombres dures ; verre réservé à Y2K |
| Artisanaux | Scrapbook, Conceptual Sketch, Bohemian, Surrealism | papier, serif ou chasse fixe, bordures et reliefs différenciés ; verre réservé à Surrealism |
| Structure | Bento Grid | apparence en panneaux clairs disponible ; disposition en tuiles reportée à S6 |

Les 23 choix comprennent Atelier, les cinq styles validés en S2 et les 17 styles de S3 à S5. Aucun nouveau
flou n'est utilisé hors des styles dont le principe repose sur le verre.

### Limites intentionnelles de S3 à S5

- Les cadres floraux, rubans adhésifs, traits à main levée et motifs propres à certains styles sont reportés à un
  lot d'ornements dessinés, pour ne pas mélanger leur conception avec l'enregistrement des styles.
- Pixel Art utilise la chasse fixe d'iOS. Une police pixel dessinée en code demanderait un composant séparé ; aucune
  police tierce n'est ajoutée.
- Bento Grid ne change pas encore la disposition de la bibliothèque ou des réglages. Ce changement structurel reste
  isolé dans S6.

Les palettes claires sont vérifiées par `ThemeContrastTests` (4,5:1).
