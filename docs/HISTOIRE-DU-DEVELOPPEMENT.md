<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Kyōkasho — histoire du développement et dossier de transmission

**État de la recherche : 25 octobre 2026.** Source de référence : branche `main` du dépôt privé [`NOxygen59/kyokasho`](https://github.com/NOxygen59/kyokasho), au commit [`7fb7362`](https://github.com/NOxygen59/kyokasho/commit/7fb7362f184fbd5600ac8c7e1aceb1e9e394937b), tag `v1.3`. Le commit distant a été comparé au dépôt local. Le dépôt contient alors 130 commits et 40 tags de release, de `v0.1.0` à `v1.3`. Les 40 releases GitHub ont chacune un paquet `.tipa`. Aucune issue ni pull request n'était enregistrée sur le dépôt principal lors de la consultation.

## 1. À quoi sert ce document

Ce dossier rassemble le **parcours de création** de l'app : idée initiale, versions successives, changements de la feuille de route, architecture, décisions prises après les essais et problèmes encore ouverts. Il sert de source à une future documentation utilisateur. Il ne remplace ni le code, ni les notes de release, ni une vérification sur l'iPad.

**Lire les statuts avec précision :** « livré » veut dire présent dans une release ; « compilé sur Mac » ne prouve pas le comportement sur l'iPad ; « confirmé sur iPad » correspond à un retour explicite de l'utilisateur. Une mention dans une ancienne feuille de route décrit l'état **à cette date**, pas nécessairement celui de la version actuelle. Les liens vers le dépôt principal demandent un accès à ce dépôt privé.

### Sources et méthode

- [Plan initial](https://github.com/NOxygen59/kyokasho/blob/7fb7362/PLAN.md), [README](https://github.com/NOxygen59/kyokasho/blob/7fb7362/README.md), [feuille de route actuelle](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/FEUILLE-DE-ROUTE.md) et ses 99 états conservés par Git.
- [Notes de release](https://github.com/NOxygen59/kyokasho/tree/7fb7362/docs/releases), releases GitHub et historique des commits, recoupés entre eux. L'annexe A renvoie à chaque release ; l'annexe B à chaque révision de la feuille de route.
- [OCR](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/OCR.md), [architecture de lecture](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/ARCHITECTURE-LECTURE.md), [IA locale sur iOS 16](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/IA-LOCALE.md) et [proposition de grammaire](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/GRAMMAIRE.md).
- Métadonnées GitHub des dépôts liés : [`kyokasho-models`](https://github.com/NOxygen59/kyokasho-models), [`mlx-swift`](https://github.com/NOxygen59/mlx-swift), [`mlx-swift-lm`](https://github.com/NOxygen59/mlx-swift-lm). Les deux forks MLX ont pour branche par défaut `ipad-ios16` ; le dépôt de modèles et d'avis de mise à jour est distinct du dépôt privé de l'app.

## 2. Le projet en une page

Kyōkasho est un lecteur **personnel** de manuels et cours PDF en japonais, conçu pour un iPad Pro 12,9 pouces M1, 8 Go de RAM, sous iOS 16.6.1 avec TrollStore. Le cœur de l'usage est : importer un document, lire et annoter ses pages, faire reconnaître le texte des scans, obtenir des lectures de kanji, consulter un dictionnaire, créer des cartes de révision et interroger localement le contenu du manuel. L'application n'a pas été conçue ni vérifiée pour d'autres appareils ou pour une distribution publique.

L’utilisateur décide des besoins et essaie les releases sur son iPad. Le code jusqu'à `v1.1.0` a été écrit avec Claude Code ; le 23 octobre 2026, le développement, les corrections et la revue sont passés aussi à ChatGPT Codex. Claude participe au cadrage et à la feuille de route. Cette répartition est explicitée dans la [passation](https://github.com/NOxygen59/kyokasho/blob/d29208d/docs/FEUILLE-DE-ROUTE.md).

L'app est en Swift/SwiftUI. PDFKit affiche les documents, PencilKit gère le dessin, GRDB/SQLite stocke les données, Vision et des moteurs ONNX produisent l'OCR avec positions, MeCab/UniDic aide à analyser le japonais, MLX sert aux modèles IA locaux. XcodeGen génère le projet Xcode ; `build_ipa.sh` crée le paquet TrollStore sans toucher à l'iPad.

## 3. Chronologie racontée

### 20 octobre — de l'idée au premier lecteur

Le [plan initial](https://github.com/NOxygen59/kyokasho/blob/61d7354/PLAN.md) fixe cinq paliers : V1 lecteur, V2 OCR, V3 dictionnaire, V4 cartes de révision, V5 moteurs OCR supplémentaires. Il prévoit une base locale, des modules Swift séparés, des petits commits et des releases installables. La première version (`v0.1.0`) apporte bibliothèque, import Fichiers/Drive, PDFKit, annotations et « Page vers IA » ; `v0.1.1` ajoute l'animation du changement de page ; `v0.2.0` l'OCR du texte PDF et d'Apple Vision ; `v0.3.0` l'interface paysage « Atelier » ; `v0.4.0` le dictionnaire au toucher. La première [feuille de route autonome](https://github.com/NOxygen59/kyokasho/blob/e6553df/docs/FEUILLE-DE-ROUTE.md) prépare alors V4 et V5 pour un prochain chat.

### 21 octobre — dictionnaire, cartes, scans et lecteur plus riche

`v0.5.0` livre les cartes FSRS, les écrans de révision et l'export Anki. `v0.6.0` ajoute NDLOCR-Lite, PP-OCRv5 et GLM-OCR, téléchargés à la demande, ainsi que des thèmes et des optimisations. Deux correctifs ciblés suivent : la barre flottante qui gelait (`v0.6.1`) et les petits caractères des scans (`v0.6.2`). La [feuille de route à `v0.6.2`](https://github.com/NOxygen59/kyokasho/blob/2b5b690/docs/FEUILLE-DE-ROUTE.md) abandonne la simple liste V4/V5 pour des travaux A–E : performance, cohérence visuelle, précision du dictionnaire, vitesse de GLM-OCR, essais sur iPad.

Le même jour, le lecteur gagne furigana, nettoyage DE-GAN, fonds doux/sombres (`v0.7.0`), téléchargement direct du modèle et avis de mise à jour (`v0.7.1`), puis correction du mot pointé dans les PDF avec texte (`v0.7.2`). La série `v0.8.0`–`v0.8.3.1` traite les PDF photo, la double page, le texte mis en forme, les furigana, les réglages par livre, les notes flottantes, la traduction des définitions, la fusion de PDF et l'installation des mises à jour par TrollStore. La [révision de la feuille de route à `v0.8.2`](https://github.com/NOxygen59/kyokasho/blob/2654118/docs/FEUILLE-DE-ROUTE.md) fait passer les gestes/zoom, les tests réels et les finitions du japonais avant de nouvelles fonctions.

### 22 octobre — IA locale sur iOS 16 et forte accélération du projet

`v0.8.4` introduit MeCab/UniDic, l'OCR relu, la recherche de mots entiers et OvisOCR2. Plusieurs incompatibilités de MLX avec iOS 16 apparaissent ensuite **sur le vrai iPad** : plantage au lancement, calculs Metal refusés, directive du compilateur non reconnue, puis problème de Qwen. Les releases `v0.8.4.1` à `v0.8.5.3` et `v0.8.8` corrigent ces obstacles dans les forks `ipad-ios16`, avec journal de diagnostic, modèles limités en mémoire et essais Mac en Metal 3.0. La note [IA locale](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/IA-LOCALE.md) retrace les corrections et précise ce qui a réellement fonctionné sur l'iPad.

`v0.8.5` propose l'analyse d'un livre entier par plusieurs lecteurs et un vote de concordance ; `v0.8.6` apporte une mise en page fondée sur OvisOCR2 et la traduction française locale. La [nouvelle feuille de route à `v0.8.6`](https://github.com/NOxygen59/kyokasho/blob/235a89c/docs/FEUILLE-DE-ROUTE.md) remplace les petits chantiers précédents par 14 demandes V1–V14 : mémoire de l'IA, tâches persistantes, panneau détachable, scan automatique, export, ajout de pages, stockage, réglages et ménage du code.

Ces demandes sont vite intégrées : `v0.8.7` rend la mémoire des modèles plus tôt et détache le panneau d'étude ; `v0.8.8` lance la lecture IA du document et exploite son texte pour les furigana ; `v0.8.9` ajoute export, ajout de PDF à un livre, suivi du stockage et chat Qwen. Le lexique du domaine arrive dans `v0.8.9.1`. Les retours de l'iPad conduisent à **annuler** un zoom « fluide » jugé catastrophique dans `v0.8.9.2`, puis à retirer un filtre de teinte qui couvrait la page d'un aplat dans `v0.9.0`. Ce sont deux exemples documentés où un résultat qui compile sur Mac ne suffisait pas.

`v1.0.0` égalise l'affichage des pages et choisit une page en portrait, deux en paysage ; `v1.1.0` met cette préparation en cache et offre Auto/Simple/Double. À ce stade, toutes les demandes V1–V14 sont cochées dans la feuille de route, mais plusieurs attendent encore une confirmation sur l'iPad. La [passation du 23 octobre](https://github.com/NOxygen59/kyokasho/blob/d29208d/docs/FEUILLE-DE-ROUTE.md) consigne ces écarts et l'historique des essais ratés.

### 23 octobre — Codex, expérience de lecture et 1.2

À partir de `v1.1.1`, Codex améliore les onze thèmes, rend les réglages plus faciles à trouver, réserve une colonne au panneau OCR fixe et conserve le zoom lors des changements de mode. L'utilisateur confirme que ces changements fonctionnent, puis signale des transitions trop brusques : des animations réglables sont ajoutées. Un espace dictionnaire commun à la bibliothèque et au lecteur remplace « Mots de la page » ; de discrètes pastilles montrent ce que font les modèles IA.

Sur un nouveau PDF rescanné, les furigana apparaissent dans le panneau OCR mais pas sur la page. L'échantillon fourni révèle un PDF composé d'images sans couche texte. La méthode de lecture des scans est alignée sur celle du panneau ; `v1.2` regroupe ces corrections, le dictionnaire, les transitions et les indicateurs. `v1.2.1` introduit le chat du manuel à partir des pages déjà lues par OvisOCR2, avec pages citées. L'ajout de pages à un livre a également donné un retour intermittent : après plusieurs essais où le compteur semblait inchangé, l'utilisateur a constaté que les cinq pages avaient finalement été ajoutées. L'historique ne permet pas d'en déduire une cause unique ni une correction confirmée.

### 24 octobre — chat, lecture verticale et OCR plus cohérent

`v1.2.2` place le chat dans la fenêtre OCR, permet plusieurs conversations par livre, le choix entre Qwen3-VL-4B et Qwen3.5-4B et les liens vers les pages citées. Les captures utilisateur montrent ensuite une question sur « p. 6 » dont la réponse consulte des pages sans rapport ; `v1.2.3` recentre le chat sur la question, ajoute un bouton direct pour les furigana, une présentation du texte vertical et l'accès au rescan. `v1.2.4` cible explicitement une page demandée, rend les formules LaTeX **lisibles quand elles sont reconnues**, propose d'accepter les corrections Ovis pour le document entier et corrige la réservation de la colonne OCR ainsi que les gestes du trackpad.

Une autre capture montre `图` là où le manuel japonais porte `図`. `v1.3` ne crée pas une règle « japonais uniquement » qui risquerait d'effacer chiffres, latin et formules : elle ajoute le choix « Japonais / Automatique » par document et corrige **la confusion vérifiée `图` → `図`**. Les lectures IA utilisées par le chat, les furigana et la comparaison passent par une source commune. La compilation du paquet `v1.3` (build 40) a réussi sur Mac ; ces changements restent à confirmer sur l'iPad.

## 4. Comment la feuille de route a changé

| État daté | Point de départ | Priorité nouvelle | Ce que cela apprend |
|---|---|---|---|
| [Plan initial, 20/10](https://github.com/NOxygen59/kyokasho/blob/61d7354/PLAN.md) | V1 à V5 | Lecteur, OCR, dictionnaire, cartes, moteurs | Architecture et livraison progressive ; le plan prévoyait des essais simulateur alors possibles. |
| [Feuille à `v0.4.0`](https://github.com/NOxygen59/kyokasho/blob/e6553df/docs/FEUILLE-DE-ROUTE.md) | V1–V3 livrés | V4 cartes et V5 NDLOCR, en sept sessions | Première vraie passation entre chats. |
| [Feuille à `v0.6.2`](https://github.com/NOxygen59/kyokasho/blob/2b5b690/docs/FEUILLE-DE-ROUTE.md) | V4/V5 avancés | Optimisation A–E et essais iPad | Le comportement réel et la précision prennent le pas sur le calendrier. |
| [Feuille à `v0.8.2`](https://github.com/NOxygen59/kyokasho/blob/2654118/docs/FEUILLE-DE-ROUTE.md) | PDF photo, furigana, mise en page | Gestes, vertical, thème, performance | Les retours d'usage remplacent des objectifs plus abstraits. |
| [Feuille à `v0.8.6`](https://github.com/NOxygen59/kyokasho/blob/235a89c/docs/FEUILLE-DE-ROUTE.md) | IA locale fonctionnelle | 14 demandes V1–V14, mémoire, export, panneau, ajout de pages | La feuille devient aussi un journal des décisions et pièges iOS 16. |
| [Passation à `v1.1.0`](https://github.com/NOxygen59/kyokasho/blob/d29208d/docs/FEUILLE-DE-ROUTE.md) | V1–V14 cochées | Retours iPad, § 7 bis et backlog § 8 | Répartition explicite entre l’utilisateur, Claude et Codex ; état vérifié séparé du code livré. |
| [État `v1.3`](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/FEUILLE-DE-ROUTE.md) | Chat, OCR ciblé, réglages | « Continuer », grammaire, vertical, performance | Les sections historiques restent utiles, mais leurs cases ne prouvent pas toutes un essai iPad. |

Les **99 états** de `docs/FEUILLE-DE-ROUTE.md` ne sont pas 99 plans entièrement nouveaux : beaucoup sont de petites mises à jour après un commit. L'annexe B donne un lien vers chacun afin de retrouver le texte exact d'une date. `PLAN.md` a seulement trois révisions dans Git ; son calendrier du 20 octobre est un **plan historique**, pas le calendrier courant. La feuille de route contient aussi des descriptions anciennes de fonctions depuis modifiées ou annulées ; toujours recouper une décision avec la release suivante et le retour iPad.

## 5. Fonctionnement actuel, côté utilisateur

| Domaine | Parcours ou fonction livrée | Source et réserve |
|---|---|---|
| Bibliothèque | Import PDF depuis Fichiers et Google Drive, recherche, progression, fusion, export, ajout de pages à un livre | [README](https://github.com/NOxygen59/kyokasho/blob/7fb7362/README.md), [0.8.9](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9) ; l'ajout a fait l'objet d'un retour intermittent. |
| Lecture | Simple/double page, sens de lecture, navigation par pellicule, thèmes, zoom, annotations, notes flottantes | [0.8.3](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.3), [1.1.1](https://github.com/NOxygen59/kyokasho/releases/tag/v1.1.1), [1.2.4](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.4) ; gestes et panneau à revérifier sur l'appareil après les derniers correctifs. |
| Texte et japonais | OCR avec positions, OvisOCR2 pour lire une page, MeCab/UniDic, furigana de page et du panneau, dictionnaire, lexique | [OCR](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/OCR.md), [1.3](https://github.com/NOxygen59/kyokasho/releases/tag/v1.3) ; précision variable sur scans, vertical et formules. |
| Étude | Cartes FSRS, révisions et export Anki, traduction DeepL facultative ou Qwen locale, chat du livre avec références de pages | [0.5.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.5.0), [1.2.2](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.2) ; qualité des réponses à contrôler avec les pages citées. |
| Réglages et diagnostic | Réglages par livre, gestion des modèles, stockage/cache, journal de diagnostic, avis de mise à jour | [0.8.4.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4.2), [1.3](https://github.com/NOxygen59/kyokasho/releases/tag/v1.3). |

La « **fenêtre OCR** » dans les échanges avec l'utilisateur désigne le panneau d'étude du lecteur : onglets Texte, Dico, Notes, Repères et Chat. Elle peut être ancrée, libre, agrandie ou réduite. Le moteur OCR qui donne du texte **et des positions** est distinct d'OvisOCR2, qui lit une page entière et rend du Markdown. Cette distinction est essentielle pour expliquer les furigana, les corrections et le chat.

## 6. Architecture et circulation des données

1. **PDF source** : copié dans la bibliothèque de l'app, conservé comme référence visuelle. La page affichée vient du PDF ; le texte produit par l'IA ne remplace pas son image.
2. **OCR géométrique** : `OCRService` choisit texte du PDF, NDLOCR, PP-OCRv5 puis Apple Vision en mode Auto. Ses lignes et positions sont enregistrées dans SQLite par livre, page et moteur. Elles servent au toucher sur la page, à la sélection, au texte brut, aux furigana et aux comparaisons.
3. **Lecture IA** : OvisOCR2 lit l'image et produit un Markdown par page dans `Application Support/Analysis`. `DocumentAITextStore` donne aux consommateurs une lecture normalisée selon la langue ciblée, sans réécrire le résultat brut. GLM-OCR peut relire des lignes douteuses ; Qwen sert à la traduction et au chat.
4. **Analyse et correction** : l'analyse compare plusieurs lectures et enregistre un rapport de fiabilité ; l'utilisateur peut accepter des corrections sur une page ou sur le document. Une ligne corrigée à la main doit rester protégée. Un rescan invalide l'ancien rapport de la page.
5. **Affichage et apprentissage** : le panneau Texte, le dictionnaire, les notes, les cartes et le chat réutilisent ces données. Le chat sélectionne des passages des pages Ovis déjà lues et cite leurs pages ; il ne devient pas fiable par le seul fait d'utiliser un modèle plus gros.

Le schéma détaillé des producteurs, stockages et consommateurs est dans [Architecture de lecture](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/ARCHITECTURE-LECTURE.md). Les packages locaux séparent `ReaderCore`, `OCRKit`, `ONNXOCRKit`, `DictionaryKit`, `YomitanKit`, `ReviewKit` et `MorphologyKit` ; `GLMOCRKit` porte les lecteurs MLX. `App/` contient les écrans et l'intégration. Pour comprendre une fonction, partir du parcours utilisateur puis suivre ces dépendances, plutôt que supposer que « l'IA » est un seul composant.

## 7. Décisions, compromis et apprentissages

| Sujet | Décision et raison | Limite observée |
|---|---|---|
| iOS 16 | Garder l'app sur l'iPad de l'utilisateur et rétroporter MLX dans deux forks dédiés, avec calcul équivalent plutôt que désactiver les contrôles. | Le compilateur récent du Mac n'a pas reproduit tous les échecs Metal sur iPad. Le journal de l'app a été décisif. |
| Modèles sur l'appareil | Télécharger les poids à la demande ; un seul modèle MLX chargé à la fois, puis déchargé après inactivité. | Temps de lecture et mémoire importants ; Qwen3.5-4B n'avait pas de mesure de qualité/vitesse sur l'iPad à `v1.3`. |
| Fiabilité OCR | Conserver le PDF original, les sorties brutes et les retouches séparées ; montrer les différences et demander l'acceptation. | Vote de plusieurs moteurs ≠ vérité ; le japonais vertical et les formules restent difficiles. |
| Langue du livre | Japonais par défaut, Automatique pour document mixte, sans supprimer latin, chiffres, unités ou symboles. | Une consigne de langue ne garantit pas l'exactitude ; `图` → `図` est une correction ciblée, pas un dictionnaire universel de substitutions. |
| Pages et annotations | Égaliser l'affichage, conserver les repères de la page d'origine et mettre en cache les préparations coûteuses. | La feuille de route note un risque de décalage d'anciennes annotations et d'export annoté sur certaines pages redimensionnées. |
| Gestes et teintes | Annuler le zoom expérimental et le filtre global après retour iPad ; revenir à des solutions contenues dans PDFKit ou peintes par page. | Les gestes trackpad/zoom et certains modes de panneau nécessitent encore une confirmation après `v1.2.4`. |
| Échanges de développement | Petit commit, numéro de release donné par l'utilisateur, `.tipa` joint à une release privée, notes « vérifié / non vérifié ». | La vitesse des versions du 22 octobre et l'absence d'essais iPad pour plusieurs changements augmentent la dette de vérification. |

## 8. État de confiance au 25 octobre 2026

**Confirmé par retour iPad :** l'IA locale OvisOCR2, l'analyse et la vérification de double page ont fonctionné après les correctifs iOS 16 ; les gestes au doigt de `v0.8.9.2` ont été jugés bons ; les changements de thèmes/réglages/fenêtre de `v1.1.1` ont été jugés fonctionnels. Ce sont des confirmations situées dans le temps, sur le document et l'appareil utilisés, pas une validation de toutes les pages.

**Livré mais à confirmer ou à surveiller :** comportement réel de `v1.3` (langue ciblée, correction OCR, import Drive), formules et numéros dans les scans, furigana verticaux ou de légendes, qualité du chat et exactitude des pages citées, gestes du trackpad, transitions et recadrage avec panneau OCR ancré, ajout de PDF à un livre, modèle Qwen3.5-4B sur iPad. Les notes de release 1.2.2–1.3 déclarent explicitement qu'aucun simulateur ni iPad n'a été utilisé pour leur construction.

**Prévu, non livré comme fonction complète :** bandeau « Continuer » dans la bibliothèque (R), fiches de grammaire (K ; conception seulement), accord MeCab/dictionnaire pour furigana vérifiés (N), certaines améliorations de mise en page verticale et de tableaux (B5), performance (B6), GLM-OCR groupé (B7). Le backlog conserve aussi des pistes comme PP-OCRv6, meilleure gestion des photos floues et synchronisation des cartes. Une case du plan peut être cochée alors que le résultat réel sur l'iPad reste non vérifié.

## 9. Pour fabriquer ensuite une documentation utilisateur

Partir des **tâches** : importer un manuel, comprendre les deux types de texte, lire en double page, ouvrir la fenêtre OCR, choisir le moteur et la langue, corriger une ligne, relire une page, consulter un mot, créer une carte, poser une question avec référence de page, sauvegarder/exporter. Illustrer chaque tâche sur la version réellement installée et éviter de promettre une précision OCR absolue. Prévoir un court encadré « vérifier sur la page originale » pour les formules, chiffres et réponses du chat.

Le futur guide doit distinguer les options **globales**, **par document** et **par page**, expliquer où se trouvent les modèles téléchargés et ce qui survit à un effacement du cache. Les captures de `v1.3` et les essais sur l'iPad restent la dernière source pour les noms et placements visibles. Ce dossier est une source historique et technique ; il ne faut pas transformer les anciennes descriptions de menu en instructions actuelles sans les revoir sur l'app.

## Annexe A — toutes les releases GitHub

Le tableau ci-dessous est tiré du README à `v1.3` et recoupé avec la liste des releases GitHub. Les dates de publication se trouvent sur chaque page de release ; les descriptions résument ce qui était annoncé, pas un essai iPad.

<!-- INDEX_RELEASES_DEBUT -->
| Version | Paquet et publication | Résumé annoncé | Notes détaillées |
|---|---|---|---|
| `1.3` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.3) | OCR japonais mieux normalisé, langue du document choisie à l'import, réglages OCR réorganisés | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.3.md) |
| `1.2.4` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.4) | Chat sur la page demandée, corrections OCR du livre entier, formules lisibles, fenêtre OCR et trackpad améliorés | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.2.4.md) |
| `1.2.3` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.3) | Chat recentré sur les questions, texte vertical avec furigana, bascule rapide et relecture OCR accessible | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.2.3.md) |
| `1.2.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.2) | Chat dans le lecteur, conversations par livre, pages ouvrables et choix Qwen3-VL / Qwen3.5 | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.2.2.md) |
| `1.2.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.1) | Chat Qwen sur les pages lues par OvisOCR2, références aux pages du manuel | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.2.1.md) |
| `1.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2) | Transitions de la fenêtre OCR, dictionnaire partagé, activité des IA, furigana des scans | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.2.md) |
| `1.1.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.1.1) | Thèmes affinés, réglages simplifiés, fenêtre OCR et conservation du zoom, cartes de la page | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.1.1.md) |
| `1.1.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.1.0) | Pages préparées une seule fois (cache), choix Auto / Simple / Double | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.1.0.md) |
| `1.0.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v1.0.0) | Pages de même taille, portrait / paysage automatique, furigana sans fond | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v1.0.0.md) |
| `0.9.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.9.0) | Teintes préchargées, sombre intelligent, fenêtre OCR plus libre | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.9.0.md) |
| `0.8.9.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9.2) | Gestes du mode Pencil partout (retour arrière du zoom fluide), teinte des pages instantanée | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.9.2.md) |
| `0.8.9.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9.1) | Toucher sans attente, zoom fluide (premier essai), lexique du domaine, ménage du code | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.9.1.md) |
| `0.8.9` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9) | Export, ajout de pages, place prise et cache, une page par IA, chat Qwen | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.9.md) |
| `0.8.8` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.8) | Qwen réparé sur iOS 16, document lu par l'IA à l'import, furigana et doutes d'après l'IA, thèmes à fonds dessinés | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.8.md) |
| `0.8.7` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.7) | IA : mémoire rendue, tâches qui continuent (pastille, arrêt confirmé) ; panneau d'étude détachable et stable | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.7.md) |
| `0.8.6` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.6) | Mise en page IA (OvisOCR2) et traduction française hors ligne (Qwen3-VL-4B), page ou document entier | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.6.md) |
| `0.8.5.3` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.3) | Correctif IA sur iOS 16 (directive reassociate) + vue « Mise en page IA » du panneau Texte | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.5.3.md) |
| `0.8.5.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.2) | Correctif : l'IA locale compile ses calculs sur iOS 16 (remove_addrspace_t de Metal 3.1 remplacé) | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.5.2.md) |
| `0.8.5.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.1) | Correctif : plus d'arrêt pendant la lecture IA, lecture bornée, Qwen3-VL-4B optionnel | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.5.1.md) |
| `0.8.5` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5) | Analyser le document entier (OCR + OvisOCR2 + GLM-OCR + Qwen3-VL-4B, vote, fiabilité, choix conseillés), mémoire étendue | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.5.md) |
| `0.8.4.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4.2) | Correctif : IA (OvisOCR2, GLM-OCR) sur iOS 16 + mode diagnostic | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.4.2.md) |
| `0.8.4.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4.1) | Correctif : la 0.8.4 plantait au lancement sur iOS 16 | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.4.1.md) |
| `0.8.4` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4) | Furigana par MeCab, OCR relu (dictionnaire + GLM-OCR), dictionnaire au mot entier, MLX récent sur iOS 16, OvisOCR2 « Vérifier la double page », réglages des modèles réorganisés | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.4.md) |
| `0.8.3.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.3.1) | Fusion de PDF sur l'iPad (ordre au glisser, Fichiers ou bibliothèque) | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.3.1.md) |
| `0.8.3` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.3) | Furigana plus lisibles (couleur au choix), recherche dans la page, traduction française des définitions, notes flottantes ancrées, moniteur, mise à jour par TrollStore | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.3.md) |
| `0.8.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.2) | PDF photo : dictionnaire juste (pages tournées), furigana sans débordement, nettoyage des scans sans modèle ; mise en page PP-DocLayout / DocLayout-YOLO | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.2.md) |
| `0.8.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.1) | Boutons de page réparés (double page), réglages par document, furigana cliquables dans le texte extrait, modèles à part, nouvelle icône | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.1.md) |
| `0.8.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.0) | Scans fiables (dictionnaire, furigana), double page (pilules), texte mis en forme (titres, tableaux), panneau ouvert d'office | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.8.0.md) |
| `0.7.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.2) | Correctif : survol / toucher du dictionnaire sur le bon mot (PDF avec texte) | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.7.2.md) |
| `0.7.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.1) | DE-GAN téléchargé directement, avis de mise à jour dans l'app | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.7.1.md) |
| `0.7.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.0) | Furigana, netteté des scans (DE-GAN), fond doux / sombre, barre à 3 boutons, navigateur ouvert, optimisations | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.7.0.md) |
| `0.6.2` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.2) | Dictionnaire sur pages scannées : petits caractères mieux lus, toucher tolérant, bon moteur OCR | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.6.2.md) |
| `0.6.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.1) | Correctif : glisser la barre d'outils ne gèle plus l'app | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.6.1.md) |
| `0.6.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.0) | OCR NDLOCR-Lite, PP-OCRv5, GLM-OCR (téléchargés), thèmes, barre flottante, dictionnaire dans la sélection, suppression réparée, optimisation mémoire | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.6.0.md) |
| `0.5.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.5.0) | Cartes de révision FSRS, écran de révision, export Anki (.apkg, CSV, AnkiMobile), page 1, survol au curseur | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.5.0.md) |
| `0.4.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.4.0) | Dictionnaire au toucher façon Yomitan, onglet Mots, recherche, import de dictionnaires | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.4.0.md) |
| `0.3.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.3.0) | Interface « Atelier » paysage, panneau d'étude, DeepL, Drive simplifié | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.3.0.md) |
| `0.2.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.2.0) | OCR : texte du PDF / Apple Vision, lecteur de texte, comparaison, banc d'essai | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.2.0.md) |
| `0.1.1` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.1.1) | Glissement animé en double page | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.1.1.md) |
| `0.1.0` | [Release](https://github.com/NOxygen59/kyokasho/releases/tag/v0.1.0) | Lecteur, annotations, commentaires, page vers IA, Google Drive | [Notes](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/releases/v0.1.0.md) |
<!-- INDEX_RELEASES_FIN -->

## Annexe B — toutes les révisions de la feuille de route

Chaque lien pointe vers **le fichier tel qu'il était à ce commit**. Lire surtout les six jalons de la section 4 pour suivre les changements de cap ; cet index complet permet d'examiner les 99 modifications sans perdre leur contexte.

<!-- INDEX_ROUTE_DEBUT -->
| Date du commit | Feuille à ce commit | Modification annoncée dans le commit |
|---|---|---|
| 2026-10-21 | [e6553df](https://github.com/NOxygen59/kyokasho/blob/e6553df/docs/FEUILLE-DE-ROUTE.md) | Feuille de route détaillée pour reprendre dans un nouveau chat |
| 2026-10-21 | [516d727](https://github.com/NOxygen59/kyokasho/blob/516d727/docs/FEUILLE-DE-ROUTE.md) | V4-a : ReviewKit compile, tests des modèles, de FSRS et de la base |
| 2026-10-21 | [0eaf0d7](https://github.com/NOxygen59/kyokasho/blob/0eaf0d7/docs/FEUILLE-DE-ROUTE.md) | V4-b : export Anki (CSV, .apkg, AnkiMobile) + accueil, page 1, survol au curseur |
| 2026-10-21 | [2ef7f3e](https://github.com/NOxygen59/kyokasho/blob/2ef7f3e/docs/FEUILLE-DE-ROUTE.md) | V4-c : créer une carte depuis le popup, la recherche et l'onglet Mots |
| 2026-10-21 | [3691090](https://github.com/NOxygen59/kyokasho/blob/3691090/docs/FEUILLE-DE-ROUTE.md) | Version 0.5.0 (V4-d : écrans de révision, navigateur de cartes, réglages Révisions) |
| 2026-10-21 | [45e076d](https://github.com/NOxygen59/kyokasho/blob/45e076d/docs/FEUILLE-DE-ROUTE.md) | Lecteur : dictionnaire dans le menu de sélection, barre flottante, flèches clavier, thèmes |
| 2026-10-21 | [41644e4](https://github.com/NOxygen59/kyokasho/blob/41644e4/docs/FEUILLE-DE-ROUTE.md) | OCR : moteur IA GLM-OCR (MLX), modèle téléchargé à la demande |
| 2026-10-21 | [e40d700](https://github.com/NOxygen59/kyokasho/blob/e40d700/docs/FEUILLE-DE-ROUTE.md) | Optimisation mémoire et fluidité + suppression des documents réparée |
| 2026-10-21 | [9ec61e3](https://github.com/NOxygen59/kyokasho/blob/9ec61e3/docs/FEUILLE-DE-ROUTE.md) | Optimisation, 2e passe : lecteur construit hors du fil principal, bibliothèque et recherche allégées |
| 2026-10-21 | [2b5b690](https://github.com/NOxygen59/kyokasho/blob/2b5b690/docs/FEUILLE-DE-ROUTE.md) | Feuille de route réécrite pour le prochain chat (état 0.6.2, étapes A-E, carte du code, pièges) |
| 2026-10-21 | [7b4a4aa](https://github.com/NOxygen59/kyokasho/blob/7b4a4aa/docs/FEUILLE-DE-ROUTE.md) | Lecteur plus léger : moins de redessins, rangement des pages en une passe, pagination calculée une fois |
| 2026-10-21 | [3dc94f1](https://github.com/NOxygen59/kyokasho/blob/3dc94f1/docs/FEUILLE-DE-ROUTE.md) | Barre flottante à 3 boutons, navigateur ouvert à tous les sites, fond de page doux ou sombre, panneaux plus légers |
| 2026-10-21 | [00c9c33](https://github.com/NOxygen59/kyokasho/blob/00c9c33/docs/FEUILLE-DE-ROUTE.md) | Netteté des scans avec DE-GAN (modèle importé, CoreML), script de conversion, import depuis Fichiers |
| 2026-10-21 | [e3b3771](https://github.com/NOxygen59/kyokasho/blob/e3b3771/docs/FEUILLE-DE-ROUTE.md) | Furigana sur les kanji (option) : lectures par l'analyseur japonais d'iOS, posées sur le texte du PDF ou l'OCR |
| 2026-10-21 | [5d87e57](https://github.com/NOxygen59/kyokasho/blob/5d87e57/docs/FEUILLE-DE-ROUTE.md) | Optimisations : popup du dictionnaire, audio, notes, recherche de cartes, téléchargements, DE-GAN et OCR (Accelerate) |
| 2026-10-21 | [ee4b395](https://github.com/NOxygen59/kyokasho/blob/ee4b395/docs/FEUILLE-DE-ROUTE.md) | DE-GAN téléchargé directement (dépôt public kyokasho-models), avis de mise à jour dans l'app |
| 2026-10-21 | [3329b96](https://github.com/NOxygen59/kyokasho/blob/3329b96/docs/FEUILLE-DE-ROUTE.md) | Survol / toucher du dictionnaire : bon mot sur les PDF avec texte (index décalé après chaque fin de ligne) |
| 2026-10-21 | [7e15079](https://github.com/NOxygen59/kyokasho/blob/7e15079/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.0 (scans fiables, double page avec pilules, texte OCR mis en forme, panneau ouvert d'office) |
| 2026-10-21 | [30f1c98](https://github.com/NOxygen59/kyokasho/blob/30f1c98/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.1 (boutons de page, réglages par document, furigana cliquables dans le texte extrait, modèles à part, nouvelle icône) |
| 2026-10-21 | [9f8c69c](https://github.com/NOxygen59/kyokasho/blob/9f8c69c/docs/FEUILLE-DE-ROUTE.md) | Mise en page par modèle : PP-DocLayout v3 et DocLayout-YOLO (MinerU) téléchargeables, texte mis en forme par zones |
| 2026-10-21 | [b5849bf](https://github.com/NOxygen59/kyokasho/blob/b5849bf/docs/FEUILLE-DE-ROUTE.md) | Photos de pages : dictionnaire et furigana justes sur les pages tournées, furigana sans débordement, nettoyage des scans sans modèle (papier blanc) |
| 2026-10-21 | [2654118](https://github.com/NOxygen59/kyokasho/blob/2654118/docs/FEUILLE-DE-ROUTE.md) | Feuille de route réécrite pour le prochain chat (état 0.8.2 : fait et comment, étapes 1-7, carte du code, pièges) |
| 2026-10-22 | [7b07e0f](https://github.com/NOxygen59/kyokasho/blob/7b07e0f/docs/FEUILLE-DE-ROUTE.md) | Furigana de la page : taille rétablie et jamais de chevauchement ; plan de la 0.8.3 et conception de la grammaire |
| 2026-10-22 | [52eefe7](https://github.com/NOxygen59/kyokasho/blob/52eefe7/docs/FEUILLE-DE-ROUTE.md) | v0.8.3 (1-2) : moteurs OCR en icônes, choix de mise en page visible, barre d'outils regroupée, notes dans « … », recherche dans le texte de la page (kanji, kana, romaji), mot entier au toucher, traduction française des définitions anglaises (DeepL) avec avis et corrections |
| 2026-10-22 | [ea0e8a8](https://github.com/NOxygen59/kyokasho/blob/ea0e8a8/docs/FEUILLE-DE-ROUTE.md) | Retours du test : couleur des furigana au choix, traduction française dans la fiche du mot, quota DeepL dans le menu « … » |
| 2026-10-22 | [e5369a0](https://github.com/NOxygen59/kyokasho/blob/e5369a0/docs/FEUILLE-DE-ROUTE.md) | Dictionnaire sur les PDF photo : l'OCR choisi passe avant la couche texte cachée de l'appli de scan |
| 2026-10-22 | [4e07dfe](https://github.com/NOxygen59/kyokasho/blob/4e07dfe/docs/FEUILLE-DE-ROUTE.md) | v0.8.3 (4-5) : notes flottantes (texte + Pencil, redimensionnables) ancrées sur un mot de la page, moniteur de ressources ; Page vers IA : choix de la page en double page |
| 2026-10-22 | [8edbd10](https://github.com/NOxygen59/kyokasho/blob/8edbd10/docs/FEUILLE-DE-ROUTE.md) | v0.8.3 (6) : mise à jour par TrollStore — connexion GitHub (device flow), .tipa de la release téléchargé en fond, installation en un geste, nettoyage au lancement suivant |
| 2026-10-22 | [7d56eb5](https://github.com/NOxygen59/kyokasho/blob/7d56eb5/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.3 (furigana lisibles, recherche dans la page, définitions en français, notes flottantes ancrées, moniteur, mise à jour par TrollStore) |
| 2026-10-22 | [8adecfe](https://github.com/NOxygen59/kyokasho/blob/8adecfe/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.3.1 (fusion de PDF sur l'iPad : ordre au glisser, enregistrement dans Fichiers ou import dans la bibliothèque) |
| 2026-10-22 | [0d01bc5](https://github.com/NOxygen59/kyokasho/blob/0d01bc5/docs/FEUILLE-DE-ROUTE.md) | Dictionnaire sur la page : recherche depuis le début du mot (toucher un kanji d'un composé cherche le composé) ; plan de fiabilité OCR et furigana |
| 2026-10-22 | [0e8d1a7](https://github.com/NOxygen59/kyokasho/blob/0e8d1a7/docs/FEUILLE-DE-ROUTE.md) | Analyseur japonais MeCab + UniDic (téléchargé à la demande) : furigana selon le contexte sur la page et dans le panneau |
| 2026-10-22 | [8f53cd4](https://github.com/NOxygen59/kyokasho/blob/8f53cd4/docs/FEUILLE-DE-ROUTE.md) | OCR relu : caractères douteux repérés par le dictionnaire, confusions corrigées (未/末, 土/士…), lignes douteuses relues par GLM-OCR, correction à la main dans le panneau |
| 2026-10-22 | [c7317d2](https://github.com/NOxygen59/kyokasho/blob/c7317d2/docs/FEUILLE-DE-ROUTE.md) | Feuille de route : prochaine session = MLX récent rétroporté sur iOS 16 (OvisOCR2, vérification de la double page) |
| 2026-10-22 | [5d40f20](https://github.com/NOxygen59/kyokasho/blob/5d40f20/docs/FEUILLE-DE-ROUTE.md) | Balises FDR dans le code : chaque endroit à modifier pour une étape restante de la feuille de route est repérable par grep |
| 2026-10-22 | [eb102f6](https://github.com/NOxygen59/kyokasho/blob/eb102f6/docs/FEUILLE-DE-ROUTE.md) | Feuille de route : étape O en pause, état exact du rétroportage de MLX |
| 2026-10-22 | [9a607ec](https://github.com/NOxygen59/kyokasho/blob/9a607ec/docs/FEUILLE-DE-ROUTE.md) | MLX récent rétroporté sur iOS 16 (forks ipad-ios16) : GLM-OCR amont, OvisOCR2 téléchargeable, « Vérifier la double page » avec différences à accepter ou refuser |
| 2026-10-22 | [ad8755e](https://github.com/NOxygen59/kyokasho/blob/ad8755e/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.4 (furigana par MeCab, OCR relu, dictionnaire au mot entier, MLX récent sur iOS 16, OvisOCR2, réglages des modèles par usage) |
| 2026-10-22 | [64c9cc0](https://github.com/NOxygen59/kyokasho/blob/64c9cc0/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.4.1 (correctif : plantage au lancement sur iOS 16 — std::format remplacé dans le fork MLX au lieu de couper les contrôles de libc++) |
| 2026-10-22 | [12bd28c](https://github.com/NOxygen59/kyokasho/blob/12bd28c/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.4.2 (IA locale sur iOS 16 : Metal 3.0 et bfloat logiciel dans les noyaux compilés sur l'iPad ; mode diagnostic ; test OvisOCR2 sur Mac) |
| 2026-10-22 | [eae5a65](https://github.com/NOxygen59/kyokasho/blob/eae5a65/docs/FEUILLE-DE-ROUTE.md) | Analyser le document entier : OCR + OvisOCR2 + GLM-OCR + Qwen3-VL-4B, vote ligne par ligne, fiabilité et choix conseillés ; mémoire étendue ; tests Mac des modèles en Metal 3.0 |
| 2026-10-22 | [be019f1](https://github.com/NOxygen59/kyokasho/blob/be019f1/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.5 (analyse du document entier : OCR + OvisOCR2 + GLM-OCR + Qwen3-VL-4B, vote, fiabilité ; mémoire étendue) |
| 2026-10-22 | [59c4c78](https://github.com/NOxygen59/kyokasho/blob/59c4c78/docs/FEUILLE-DE-ROUTE.md) | Analyse : Qwen3-VL-4B optionnel (moins bon qu'OvisOCR2 sur le vrai manuel, 2× plus gourmand) ; test sur vraies pages (testRealSample) |
| 2026-10-22 | [e5ca7a9](https://github.com/NOxygen59/kyokasho/blob/e5ca7a9/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.5.1 (lecture IA protégée et bornée, Qwen3-VL-4B optionnel) |
| 2026-10-22 | [eff21f1](https://github.com/NOxygen59/kyokasho/blob/eff21f1/docs/FEUILLE-DE-ROUTE.md) | IA sur iOS 16 : cause du plantage trouvée par le journal (remove_addrspace_t de Metal 3.1 inconnu d'iOS 16) et corrigée dans le fork MLX |
| 2026-10-22 | [9ea2266](https://github.com/NOxygen59/kyokasho/blob/9ea2266/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.5.2 (IA locale sur iOS 16 : remove_addrspace_t de Metal 3.1 remplacé) |
| 2026-10-22 | [e58c4d0](https://github.com/NOxygen59/kyokasho/blob/e58c4d0/docs/FEUILLE-DE-ROUTE.md) | Feuille de route 0.8.6 : vue « Mise en page IA » en HTML, traduction hors ligne par Qwen3-VL, lexique du domaine (balises FDR-T/U) |
| 2026-10-22 | [bc6642b](https://github.com/NOxygen59/kyokasho/blob/bc6642b/docs/FEUILLE-DE-ROUTE.md) | Panneau Texte : vue « Mise en page IA » (Markdown d'OvisOCR2 → HTML sûr aux couleurs du thème, furigana, dictionnaire, figures en vignettes) |
| 2026-10-22 | [30e7ee5](https://github.com/NOxygen59/kyokasho/blob/30e7ee5/docs/FEUILLE-DE-ROUTE.md) | IA sur iOS 16 : directive reassociate de Metal récent remplacée (fork MLX : sans maths rapides pour ces noyaux) |
| 2026-10-22 | [9e734d4](https://github.com/NOxygen59/kyokasho/blob/9e734d4/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.5.3 (IA locale : directive reassociate remplacée pour iOS 16 ; vue « Mise en page IA ») |
| 2026-10-22 | [32a06ca](https://github.com/NOxygen59/kyokasho/blob/32a06ca/docs/FEUILLE-DE-ROUTE.md) | Traduction hors ligne par Qwen3-VL-4B : page ou document entier, structure de la mise en page gardée, glossaire du design d'intérieur |
| 2026-10-22 | [6b57ce3](https://github.com/NOxygen59/kyokasho/blob/6b57ce3/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.6 (mise en page IA, traduction française hors ligne par Qwen3-VL-4B) |
| 2026-10-22 | [235a89c](https://github.com/NOxygen59/kyokasho/blob/235a89c/docs/FEUILLE-DE-ROUTE.md) | Feuille de route réécrite pour un nouveau chat (état 0.8.6, fait et comment, plan V1-V14 détaillé) + docs/IA-LOCALE.md (IA locale sur iOS 16 de A à Z) + balises FDR-V1…V14 dans le code |
| 2026-10-22 | [5d40ad2](https://github.com/NOxygen59/kyokasho/blob/5d40ad2/docs/FEUILLE-DE-ROUTE.md) | IA : mémoire rendue quand on ne s'en sert pas (V2) — modèle MLX libéré après 90 s sans lecture, cache GPU vidé après chaque lecture, sessions ONNX fermées après 120 s |
| 2026-10-22 | [03ce999](https://github.com/NOxygen59/kyokasho/blob/03ce999/docs/FEUILLE-DE-ROUTE.md) | IA : libération plus rapide (45 s MLX, 30 s ONNX) et modèles déchargés au retour à la bibliothèque ou en arrière-plan (V12) |
| 2026-10-22 | [0198211](https://github.com/NOxygen59/kyokasho/blob/0198211/docs/FEUILLE-DE-ROUTE.md) | Tâches IA indépendantes des vues (V4) : relecture, vérification, mise en page et traduction continuent en changeant de page ou en fermant le lecteur ; pastille « IA : … » avec arrêt à double confirmation |
| 2026-10-22 | [9767c12](https://github.com/NOxygen59/kyokasho/blob/9767c12/docs/FEUILLE-DE-ROUTE.md) | Panneau de droite : ne revient plus en haut quand on glisse ou zoome dans la même page (V13) |
| 2026-10-22 | [9858bc0](https://github.com/NOxygen59/kyokasho/blob/9858bc0/docs/FEUILLE-DE-ROUTE.md) | Panneau d'étude détachable (V1) : fenêtre déplaçable et redimensionnable, plein écran, réduit en pastille ou ancré à droite ; mode gardé |
| 2026-10-22 | [c186fa8](https://github.com/NOxygen59/kyokasho/blob/c186fa8/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.7 (IA : mémoire rendue, tâches qui continuent ; panneau d'étude détachable et stable) |
| 2026-10-22 | [26c0496](https://github.com/NOxygen59/kyokasho/blob/26c0496/docs/FEUILLE-DE-ROUTE.md) | Double page : la page choisie dans le panneau reste tant que la planche est affichée, même zoomé sur l'autre page (retour 0.8.7) |
| 2026-10-22 | [ca9cece](https://github.com/NOxygen59/kyokasho/blob/ca9cece/docs/FEUILLE-DE-ROUTE.md) | Thèmes à fonds dessinés (V6) : Washi, Architecte, Intérieur, Lumière du soir, Encre et or, Sakura ; aperçu réel dans le choix ; couleurs du thème dans le dictionnaire et les cartes (B4) |
| 2026-10-22 | [fa0ec04](https://github.com/NOxygen59/kyokasho/blob/fa0ec04/docs/FEUILLE-DE-ROUTE.md) | Lecture IA du document à l'import et à l'ouverture, furigana d'après le texte de l'IA (V3) |
| 2026-10-22 | [e8f7330](https://github.com/NOxygen59/kyokasho/blob/e8f7330/docs/FEUILLE-DE-ROUTE.md) | Qwen sur iOS 16 : fork MLX corrigé (simdgroup_matrix<bool> du masque d'attention) ; caractères douteux revérifiés à chaque OCR et comparés au texte de l'IA (V5) |
| 2026-10-22 | [b61ae12](https://github.com/NOxygen59/kyokasho/blob/b61ae12/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.8 (Qwen réparé sur iOS 16, document lu par l'IA, furigana et doutes d'après l'IA, thèmes) |
| 2026-10-22 | [1a426ef](https://github.com/NOxygen59/kyokasho/blob/1a426ef/docs/FEUILLE-DE-ROUTE.md) | Export d'un document (V8 : PDF d'origine ou annoté, Markdown, PNG, cartes) ; fenêtre OCR : texte IA déplaçable ; vérification qui réutilise la lecture IA déjà faite ; mesures de vitesse de l'IA |
| 2026-10-22 | [4883954](https://github.com/NOxygen59/kyokasho/blob/4883954/docs/FEUILLE-DE-ROUTE.md) | Réglages : place prise par l'app, par catégorie, en graphique (V10) |
| 2026-10-22 | [f2adff5](https://github.com/NOxygen59/kyokasho/blob/f2adff5/docs/FEUILLE-DE-ROUTE.md) | Réglages : effacer le cache sans rien perdre d'important (V11) |
| 2026-10-22 | [5c1c2ed](https://github.com/NOxygen59/kyokasho/blob/5c1c2ed/docs/FEUILLE-DE-ROUTE.md) | Ajouter des pages à un document (V14) : fusion dans l'ordre choisi, tout ce qui est rangé par page décalé (base, fichiers IA, rapport, cartes), reprise sûre si l'app s'arrête au milieu |
| 2026-10-22 | [559acbf](https://github.com/NOxygen59/kyokasho/blob/559acbf/docs/FEUILLE-DE-ROUTE.md) | Réglages : une page par IA (état, mémoire, décharger, réglages, dernières tâches) et chat Qwen3-VL aidé par les lectures MeCab et le glossaire (V7) |
| 2026-10-22 | [2384a94](https://github.com/NOxygen59/kyokasho/blob/2384a94/docs/FEUILLE-DE-ROUTE.md) | Version 0.8.9 (export, ajout de pages, place prise et cache, une page par IA, chat Qwen) |
| 2026-10-22 | [1e2defd](https://github.com/NOxygen59/kyokasho/blob/1e2defd/docs/FEUILLE-DE-ROUTE.md) | Ménage (V9) : ReaderController découpé par thème (affichage, navigation, OCR, vérification, annotations, mise en page, recherche), code déplacé tel quel |
| 2026-10-22 | [8131e0f](https://github.com/NOxygen59/kyokasho/blob/8131e0f/docs/FEUILLE-DE-ROUTE.md) | Lexique du domaine modifiable (S) : termes connus pour la relecture et l'analyse, glossaire des traductions, aide du chat |
| 2026-10-22 | [6b94d28](https://github.com/NOxygen59/kyokasho/blob/6b94d28/docs/FEUILLE-DE-ROUTE.md) | Gestes : zoom fluide en page par page (pincer et déplacer à la façon d'iOS, tour par planche), interrupteur dans Affichage ; toucher sans attente |
| 2026-10-22 | [0728ee8](https://github.com/NOxygen59/kyokasho/blob/0728ee8/docs/FEUILLE-DE-ROUTE.md) | Gestes du mode Pencil en mode normal (PDFKit en mode annotation, sélection au doigt maison) ; teinte des pages par filtre sur la vue (instantanée, sans flash) ; version 0.8.9.2 |
| 2026-10-22 | [4510a7b](https://github.com/NOxygen59/kyokasho/blob/4510a7b/docs/FEUILLE-DE-ROUTE.md) | Version 0.9.0 : teintes préchargées (planche affichée, précédente, suivante) au lieu du filtre sur la vue, sombre intelligent (expérimental), fenêtre OCR à déplacement libre et zoom 1-5× |
| 2026-10-22 | [e673b14](https://github.com/NOxygen59/kyokasho/blob/e673b14/docs/FEUILLE-DE-ROUTE.md) | Feuille de route : idées de la v1.0 (portrait = une page, double page de même taille, cartes de la page, reprendre) |
| 2026-10-22 | [ab418f1](https://github.com/NOxygen59/kyokasho/blob/ab418f1/docs/FEUILLE-DE-ROUTE.md) | Version 1.0.0 : pages de même taille (hauteur commune, OCR et furigana suivent), portrait = une page / paysage = double page, furigana sans fond |
| 2026-10-22 | [9d317c4](https://github.com/NOxygen59/kyokasho/blob/9d317c4/docs/FEUILLE-DE-ROUTE.md) | Version 1.1.0 : pages égalisées préparées une seule fois (cache disque), pagination Auto / Simple / Double |
| 2026-10-23 | [d29208d](https://github.com/NOxygen59/kyokasho/blob/d29208d/docs/FEUILLE-DE-ROUTE.md) | Passation vers ChatGPT Codex : AGENTS.md, feuille de route à jour (état v1.1.0, leçons, à vérifier, suite), outils propres à Claude retirés |
| 2026-10-23 | [9c3d2ac](https://github.com/NOxygen59/kyokasho/blob/9c3d2ac/docs/FEUILLE-DE-ROUTE.md) | Créer les cartes du lexique depuis la page du manuel |
| 2026-10-23 | [56cb029](https://github.com/NOxygen59/kyokasho/blob/56cb029/docs/FEUILLE-DE-ROUTE.md) | Affiner les onze thèmes et améliorer leur lisibilité |
| 2026-10-23 | [5efd2ca](https://github.com/NOxygen59/kyokasho/blob/5efd2ca/docs/FEUILLE-DE-ROUTE.md) | Simplifier les réglages et préserver la vue du lecteur avec le panneau OCR |
| 2026-10-23 | [79982f5](https://github.com/NOxygen59/kyokasho/blob/79982f5/docs/FEUILLE-DE-ROUTE.md) | Version 1.1.1 : thèmes, réglages et fenêtre OCR |
| 2026-10-23 | [2b3b053](https://github.com/NOxygen59/kyokasho/blob/2b3b053/docs/FEUILLE-DE-ROUTE.md) | Rétablir des transitions douces pour la fenêtre OCR |
| 2026-10-23 | [a353195](https://github.com/NOxygen59/kyokasho/blob/a353195/docs/FEUILLE-DE-ROUTE.md) | Créer un dictionnaire partagé pour la bibliothèque et la lecture |
| 2026-10-23 | [e08e8f4](https://github.com/NOxygen59/kyokasho/blob/e08e8f4/docs/FEUILLE-DE-ROUTE.md) | Afficher des pastilles discrètes pour l’activité des IA |
| 2026-10-23 | [c28caf5](https://github.com/NOxygen59/kyokasho/blob/c28caf5/docs/FEUILLE-DE-ROUTE.md) | Rétablir les furigana sur les PDF rescannés |
| 2026-10-23 | [054f0ff](https://github.com/NOxygen59/kyokasho/blob/054f0ff/docs/FEUILLE-DE-ROUTE.md) | Aligner les furigana des scans sur le panneau OCR |
| 2026-10-23 | [568684e](https://github.com/NOxygen59/kyokasho/blob/568684e/docs/FEUILLE-DE-ROUTE.md) | Version 1.2 : dictionnaire et lecture |
| 2026-10-23 | [263a780](https://github.com/NOxygen59/kyokasho/blob/263a780/docs/FEUILLE-DE-ROUTE.md) | Version 1.2.1 (chat du manuel avec Qwen) |
| 2026-10-24 | [0f1934f](https://github.com/NOxygen59/kyokasho/blob/0f1934f/docs/FEUILLE-DE-ROUTE.md) | Ajouter le chat au lecteur et séparer les conversations |
| 2026-10-24 | [a07c755](https://github.com/NOxygen59/kyokasho/blob/a07c755/docs/FEUILLE-DE-ROUTE.md) | Version 1.2.2 : améliorer le chat du livre |
| 2026-10-24 | [12bba25](https://github.com/NOxygen59/kyokasho/blob/12bba25/docs/FEUILLE-DE-ROUTE.md) | Améliore le chat du livre et la relecture OCR |
| 2026-10-24 | [f79affd](https://github.com/NOxygen59/kyokasho/blob/f79affd/docs/FEUILLE-DE-ROUTE.md) | Version 1.2.3 : chat et relecture OCR |
| 2026-10-24 | [26e6458](https://github.com/NOxygen59/kyokasho/blob/26e6458/docs/FEUILLE-DE-ROUTE.md) | Corrige le chat ciblé, les gestes et la lecture OCR du document |
| 2026-10-24 | [d5c9036](https://github.com/NOxygen59/kyokasho/blob/d5c9036/docs/FEUILLE-DE-ROUTE.md) | Version 1.2.4 : corriger lecture et navigation |
| 2026-10-24 | [d8d7b39](https://github.com/NOxygen59/kyokasho/blob/d8d7b39/docs/FEUILLE-DE-ROUTE.md) | Corriger les caractères OCR japonais et organiser la lecture IA |
| 2026-10-24 | [20afe29](https://github.com/NOxygen59/kyokasho/blob/20afe29/docs/FEUILLE-DE-ROUTE.md) | Clarifier les réglages OCR et harmoniser l'import Drive |
| 2026-10-24 | [7fb7362](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/FEUILLE-DE-ROUTE.md) | Version 1.3 : améliorer l'OCR japonais et ses réglages |
<!-- INDEX_ROUTE_FIN -->

## Annexe C — autres points d'entrée

- [Toutes les versions du plan initial](https://github.com/NOxygen59/kyokasho/commits/main/PLAN.md) (trois révisions dans l'historique local).
- [Historique des commits du projet](https://github.com/NOxygen59/kyokasho/commits/main/) et [releases publiées](https://github.com/NOxygen59/kyokasho/releases).
- [Documents OCR](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/OCR.md), [IA locale](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/IA-LOCALE.md), [circulation du texte](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/ARCHITECTURE-LECTURE.md), [projet de grammaire](https://github.com/NOxygen59/kyokasho/blob/7fb7362/docs/GRAMMAIRE.md).
- [Avis de mise à jour `latest.json`](https://github.com/NOxygen59/kyokasho-models/blob/main/latest.json) dans le dépôt public auxiliaire ; les forks [MLX](https://github.com/NOxygen59/mlx-swift/tree/ipad-ios16) et [MLX LM](https://github.com/NOxygen59/mlx-swift-lm/tree/ipad-ios16) servent au maintien d'iOS 16.
