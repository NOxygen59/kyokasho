> [!WARNING]
> **Projet personnel « vibecodé ».** Le code initial a été écrit par **Claude** (Anthropic, via Claude Code), puis **ChatGPT Codex** a rejoint le développement, à la demande de [@NOxygen59](https://github.com/NOxygen59), pour **son appareil précis** :
>
> **iPad Pro 12,9" 5ᵉ génération (puce M1) — 512 Go de stockage, 8 Go de RAM — iOS 16.6.1, jailbreak Dopamine (rootless) + TrollStore.**
>
> Rien n'est testé ni prévu pour un autre appareil. Dépôt privé de travail personnel, sans distribution publique ni support pour d'autres appareils.

# Kyōkasho

Lecteur **personnel** de cours et de manuels PDF pour iPad : lecture, annotations,
commentaires, page vers IA, Google Drive et OCR japonais (voir [docs/OCR.md](docs/OCR.md)).
Dictionnaires Yomitan, fiches de mots et de kanji, et cartes de révision FSRS intégrés.
Plan complet : [PLAN.md](PLAN.md).

**Usage strictement personnel, jamais distribué.** Aucun PDF, dictionnaire ni donnée tierce dans
ce dépôt (`*.pdf` est ignoré par Git).

**Licence :** code original sous MIT ([LICENSE](LICENSE)). Le code qui sera porté de projets GPL
(Yomitan, Aidoku, Hoshi Reader, jiten…) gardera sa licence d'origine, dans un module séparé.
Textes des licences : [LICENSES/](LICENSES/) ; attributions : [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Versions

| Version | Release | Contenu |
|---|---|---|
| **1.2.1** | [v1.2.1](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2.1) | Chat Qwen sur les pages lues par OvisOCR2, références aux pages du manuel |
| **1.2** | [v1.2](https://github.com/NOxygen59/kyokasho/releases/tag/v1.2) | Transitions de la fenêtre OCR, dictionnaire partagé, activité des IA, furigana des scans |
| **1.1.1** | [v1.1.1](https://github.com/NOxygen59/kyokasho/releases/tag/v1.1.1) | Thèmes affinés, réglages simplifiés, fenêtre OCR et conservation du zoom, cartes de la page |
| **1.1.0** | [v1.1.0](https://github.com/NOxygen59/kyokasho/releases/tag/v1.1.0) | Pages préparées une seule fois (cache), choix Auto / Simple / Double |
| **1.0.0** | [v1.0.0](https://github.com/NOxygen59/kyokasho/releases/tag/v1.0.0) | Pages de même taille, portrait / paysage automatique, furigana sans fond |
| **0.9.0** | [v0.9.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.9.0) | Teintes préchargées, sombre intelligent, fenêtre OCR plus libre |
| **0.8.9.2** | [v0.8.9.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9.2) | Gestes du mode Pencil partout (retour arrière du zoom fluide), teinte des pages instantanée |
| **0.8.9.1** | [v0.8.9.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9.1) | Toucher sans attente, zoom fluide (premier essai), lexique du domaine, ménage du code |
| **0.8.9** | [v0.8.9](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.9) | Export, ajout de pages, place prise et cache, une page par IA, chat Qwen |
| **0.8.8** | [v0.8.8](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.8) | Qwen réparé sur iOS 16, document lu par l'IA à l'import, furigana et doutes d'après l'IA, thèmes à fonds dessinés |
| **0.8.7** | [v0.8.7](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.7) | IA : mémoire rendue, tâches qui continuent (pastille, arrêt confirmé) ; panneau d'étude détachable et stable |
| **0.8.6** | [v0.8.6](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.6) | Mise en page IA (OvisOCR2) et traduction française hors ligne (Qwen3-VL-4B), page ou document entier |
| **0.8.5.3** | [v0.8.5.3](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.3) | Correctif IA sur iOS 16 (directive reassociate) + vue « Mise en page IA » du panneau Texte |
| **0.8.5.2** | [v0.8.5.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.2) | Correctif : l'IA locale compile ses calculs sur iOS 16 (remove_addrspace_t de Metal 3.1 remplacé) |
| **0.8.5.1** | [v0.8.5.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5.1) | Correctif : plus d'arrêt pendant la lecture IA, lecture bornée, Qwen3-VL-4B optionnel |
| **0.8.5** | [v0.8.5](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.5) | Analyser le document entier (OCR + OvisOCR2 + GLM-OCR + Qwen3-VL-4B, vote, fiabilité, choix conseillés), mémoire étendue |
| **0.8.4.2** | [v0.8.4.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4.2) | Correctif : IA (OvisOCR2, GLM-OCR) sur iOS 16 + mode diagnostic |
| **0.8.4.1** | [v0.8.4.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4.1) | Correctif : la 0.8.4 plantait au lancement sur iOS 16 |
| **0.8.4** | [v0.8.4](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.4) | Furigana par MeCab, OCR relu (dictionnaire + GLM-OCR), dictionnaire au mot entier, MLX récent sur iOS 16, OvisOCR2 « Vérifier la double page », réglages des modèles réorganisés |
| **0.8.3.1** | [v0.8.3.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.3.1) | Fusion de PDF sur l'iPad (ordre au glisser, Fichiers ou bibliothèque) |
| **0.8.3** | [v0.8.3](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.3) | Furigana plus lisibles (couleur au choix), recherche dans la page, traduction française des définitions, notes flottantes ancrées, moniteur, mise à jour par TrollStore |
| **0.8.2** | [v0.8.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.2) | PDF photo : dictionnaire juste (pages tournées), furigana sans débordement, nettoyage des scans sans modèle ; mise en page PP-DocLayout / DocLayout-YOLO |
| **0.8.1** | [v0.8.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.1) | Boutons de page réparés (double page), réglages par document, furigana cliquables dans le texte extrait, modèles à part, nouvelle icône |
| **0.8.0** | [v0.8.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.8.0) | Scans fiables (dictionnaire, furigana), double page (pilules), texte mis en forme (titres, tableaux), panneau ouvert d'office |
| **0.7.2** | [v0.7.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.2) | Correctif : survol / toucher du dictionnaire sur le bon mot (PDF avec texte) |
| **0.7.1** | [v0.7.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.1) | DE-GAN téléchargé directement, avis de mise à jour dans l'app |
| **0.7.0** | [v0.7.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.7.0) | Furigana, netteté des scans (DE-GAN), fond doux / sombre, barre à 3 boutons, navigateur ouvert, optimisations |
| **0.6.2** | [v0.6.2](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.2) | Dictionnaire sur pages scannées : petits caractères mieux lus, toucher tolérant, bon moteur OCR |
| **0.6.1** | [v0.6.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.1) | Correctif : glisser la barre d'outils ne gèle plus l'app |
| **0.6.0** (V5) | [v0.6.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.6.0) | OCR NDLOCR-Lite, PP-OCRv5, GLM-OCR (téléchargés), thèmes, barre flottante, dictionnaire dans la sélection, suppression réparée, optimisation mémoire |
| **0.5.0** (V4) | [v0.5.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.5.0) | Cartes de révision FSRS, écran de révision, export Anki (.apkg, CSV, AnkiMobile), page 1, survol au curseur |
| **0.4.0** (V3) | [v0.4.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.4.0) | Dictionnaire au toucher façon Yomitan, onglet Mots, recherche, import de dictionnaires |
| **0.3.0** | [v0.3.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.3.0) | Interface « Atelier » paysage, panneau d'étude, DeepL, Drive simplifié |
| **0.2.0** (V2) | [v0.2.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.2.0) | OCR : texte du PDF / Apple Vision, lecteur de texte, comparaison, banc d'essai |
| **0.1.1** | [v0.1.1](https://github.com/NOxygen59/kyokasho/releases/tag/v0.1.1) | Glissement animé en double page |
| **0.1.0** (V1) | [v0.1.0](https://github.com/NOxygen59/kyokasho/releases/tag/v0.1.0) | Lecteur, annotations, commentaires, page vers IA, Google Drive |

Les `.tipa` sont joints aux [Releases](https://github.com/NOxygen59/kyokasho/releases).

## Fonctions (V1)

- **Bibliothèque** : import depuis Fichiers (y compris Google Drive via l'app Drive : le fichier
  est téléchargé puis copié dans l'app), identification par empreinte SHA-256 (pas de doublon),
  miniatures, dernière page lue, reprise automatique, recherche, renommer, supprimer.
- **Lecteur** (PDFKit) : page simple ou double, paginé ou continu, gauche → droite ou droite →
  gauche, première page seule, rognage automatique des marges, découpe des scans de double page,
  rotation et découpe page par page, couleur de fond, transition, zones de tap (avec inversion),
  double tap pour zoomer, barres masquées en tournant les pages, barre de pages avec aperçu.
  Réglages par document, avec valeurs par défaut globales.
- **Annotations** (le PDF original n'est jamais modifié, tout est en base) : surlignage en 5
  couleurs, dessin à l'Apple Pencil (PencilKit, le doigt fait défiler ; option « dessiner au
  doigt »), signets, sommaire du PDF, recherche plein texte.
- **Commentaires** : plusieurs par page, liste du document, export Markdown.
- **Page vers IA** : copier la page en image, prompts prédéfinis modifiables, panneau claude.ai à
  côté du PDF (+ « Ouvrir dans Safari »).
- **Google Drive direct** (après configuration, voir plus bas) : parcourir Mon Drive / Partagés,
  importer des PDF (et des Google Slides/Docs exportés en PDF), mettre à jour un cours modifié sur
  Drive en gardant toutes les annotations.
- **Réglages** façon Aidoku, thème sombre par défaut, rubrique OCR prête pour la V2.

## Compiler et installer sur l'iPad

Prérequis sur le Mac : Xcode (testé avec Xcode 27.1), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
et [ldid](https://github.com/ProcursusTeam/ldid) : `brew install xcodegen ldid`.

```bash
./build_ipa.sh
```

Le script :
1. génère le projet Xcode depuis `project.yml` (XcodeGen) ;
2. compile une archive **Release** pour iOS, **sans signature** ;
3. copie `Kyokasho.app` dans un dossier `Payload/` ;
4. pseudo-signe l'app avec `ldid` et les entitlements de `packaging/entitlements-trollstore.plist` ;
5. zippe le tout en `dist/Kyokasho-<version>.tipa`.

Sur l'iPad : ouvrir le `.tipa` avec **TrollStore** → Installer.

### Développement

```bash
xcodegen generate                       # crée Kyokasho.xcodeproj
open Kyokasho.xcodeproj                 # puis lancer sur un simulateur iPad
cd Packages/KyokashoKit && swift test   # tests unitaires du cœur (sur le Mac)
swift scripts/make_sample_pdf.swift build/samples/test.pdf   # PDF de test (texte original)
```

## Google Drive : configuration (une seule fois)

L'import via l'app **Fichiers** marche sans rien configurer (si l'app Google Drive est installée).
Pour l'accès **direct** dans Kyōkasho, il faut un identifiant client OAuth (gratuit) :

1. Ouvrir <https://console.cloud.google.com/> avec ton compte Google → **Nouveau projet**
   (ex. « Kyokasho »).
2. **API et services → Bibliothèque** → chercher **Google Drive API** → **Activer**.
3. **Écran de consentement OAuth** : type **Externe**, nom « Kyokasho », ton e-mail. Champs
   d'application : ajouter `.../auth/drive.readonly`. Utilisateurs test : ton adresse.
   Puis **Publier l'application** (état « En production ») : sinon Google déconnecte l'app tous
   les 7 jours. L'app n'étant pas vérifiée, Google affichera un avertissement à la connexion :
   « Paramètres avancés → Accéder à Kyokasho ».
4. **Identifiants → Créer des identifiants → ID client OAuth** → type **iOS**, ID de bundle
   `fr.noxygen59.kyokasho` → **Créer**. Copier l'**ID client** (`xxxx.apps.googleusercontent.com`).
5. Dans l'app : *Google Drive* → assistant → coller l'identifiant. Pas besoin de recompiler.
   (Option développeur : `App/Config/Local.xcconfig` avec `GOOGLE_CLIENT_ID = …`.)

Accès en **lecture seule** ; le jeton est stocké dans le Trousseau de l'iPad ; seules les requêtes
que tu déclenches partent vers Google.

## Organisation du code

```
App/                    écrans SwiftUI, lecteur PDFKit, dessin PencilKit, Google Drive (MIT)
Packages/KyokashoKit/   cœur testable : modèles, base GRDB, import, logique pure (MIT)
packaging/              entitlements TrollStore
scripts/                icône et PDF de test générés en code
```

## État de la V1 (honnête)

Voir les notes de la release v0.1.0 : ce qui est testé dans le simulateur, ce qui ne l'est pas
(Apple Pencil, Google Drive réel, iOS 16 réel, gros manuels) et ce qui reste fragile.
