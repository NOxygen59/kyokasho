# OCR

## Moteurs

| Moteur | Quand | Boîtes par caractère |
|---|---|---|
| **Texte du PDF** (`pdfText`) | PDF numérique (texte intégré) : exact, instantané | exactes (PDFKit `characterBounds`) |
| **Apple Vision** (`vision`) | pages scannées / images | voir ci-dessous |
| **NDLOCR** (`ndlocr`) | scan japonais, si le modèle est installé | mesurées avec PP-OCRv5 si disponible |
| **PP-OCRv5** (`ppocr5`) | repli après NDLOCR, si installé | estimées ou mesurées |
| **GLM-OCR** (`glmocr`) | choix manuel ou comparaison de l'analyse | selon le résultat du moteur |
| **Auto** | texte du PDF si la page en a ; sinon NDLOCR → PP-OCRv5 → Vision | selon le moteur choisi |

Le choix se fait dans *Réglages → OCR* et peut être remplacé par document (*⋯ → Réglages du
document*). Le moteur utilisé s'affiche dans la barre du bas du lecteur.

La lecture de la page entière par OvisOCR2 est distincte de cet OCR avec positions. Elle produit du Markdown
pour le panneau, les furigana, l'analyse et le chat. La langue de cette lecture est choisie avant l'import depuis
Fichiers ou dans l'écran d'analyse du document : **Japonais** par défaut, ou **Automatique** pour les documents
mixtes. Le réglage guide le modèle ; les nombres, lettres latines et formules sont conservés. Voir
[`ARCHITECTURE-LECTURE.md`](ARCHITECTURE-LECTURE.md) pour les liens entre composants.

## Stratégie pour toucher un caractère précis (Vision)

Mesures faites sur le Mac (Vision de macOS 27 / iOS 27) avec une image de test :

- `.fast` **ne lit pas le japonais** (langues : en, fr, it, de, es, pt) : la seconde passe
  « rapide » prévue au plan est donc impossible.
- `.accurate` + `boundingBox(for:)` donne **une boîte par caractère** pour le japonais
  horizontal (largeurs différentes par caractère, positions croissantes).
- Le **japonais vertical** n'est pas reconnu (lu caractère par caractère comme du bruit) → V5
  (NDLOCR-Lite).

Donc :
1. Vision `.accurate` (japonais + anglais) sur la page rendue à ~2 400 px de haut, en gris.
2. Pour chaque ligne, boîtes par caractère de Vision **gardées si cohérentes** (une par
   caractère, non vides, pas toutes identiques, rangées dans le sens de lecture).
3. Sinon **découpe proportionnelle** de la boîte de ligne : pleine chasse = 1, demi-chasse = 0,5.
   L'app l'indique (« boîtes de caractères estimées »).

À vérifier sur l'iPad (iOS 16.6.1) : le comportement de `boundingBox(for:)` peut différer de
celui d'iOS 27.

## Cache

Table `ocrResult`, clé **(document, page source, moteur)** : changer de moteur n'efface rien.
Coordonnées normalisées dans la `cropBox` d'origine de la page (valables quel que soit le
rognage, la découpe ou la rotation de l'affichage). Chaque résultat porte une version : un
résultat d'une version plus ancienne est refait automatiquement.

## Banc d'essai

*Réglages → OCR → Banc d'essai* : images + texte de référence → taux d'erreur de caractères
(distance de Levenshtein / longueur de la référence, espaces ignorés) et durée, par moteur.
Ajout depuis Photos, Fichiers, ou depuis le lecteur (*Texte → icône jauge*).
