<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Organisation des réglages

L'accueil des Réglages est organisé par usage. La recherche interroge le même catalogue : un réglage reste
accessible directement même lorsqu'il se trouve dans une sous-page.

| Catégorie | Pages |
|---|---|
| **Général** | Thèmes et couleurs · Icône de l'app · Visite guidée et nouveautés |
| **Lecture** | Pages et gestes · Fenêtre texte OCR · Apple Pencil et annotations |
| **IA et texte des pages** | IA et outils hors ligne · Reconnaître le texte des pages · Traduction en ligne |
| **Japonais et révision** | Dictionnaires · Lexique personnel · Cartes de révision |
| **Données** | Sauvegarde · Espace de stockage · Google Drive |
| **Aide** | Aide au diagnostic · À propos et mises à jour |

## Icône de l'app

Quatre icônes originales sont fournies : **Ivoire** (principale), **Bleu nuit**, **Jade** et **Anthracite**.
Le choix se fait dans `Réglages → Général → Icône de l'app`. iPadOS affiche sa propre confirmation ;
le changement ne touche ni les documents ni les préférences de lecture.

Les trois variantes sont déclarées comme icônes alternatives iOS. La version Mac pourra reprendre le même
catalogue visuel, mais le changement dynamique n'est prouvé ici que pour la cible iPad.

## Limites de la candidate 73

- Le rangement et le sélecteur compilent pour iOS 16, mais le changement réel d'icône doit être essayé sur
  l'iPad Pro M1 avec TrollStore.
- La candidate 73 reprend tout le code de la 72. Au moment de sa construction, la recette iPad 72 et la revue Qwen
  de ses changements ne sont pas encore remises au dossier.
