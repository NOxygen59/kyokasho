<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Lecture d'un document : qui produit quoi ?

Le PDF importé reste la source visuelle. Les textes calculés et les corrections sont des données dérivées ; aucune lecture IA ne remplace les pixels de la page.

| Donnée | Responsable | Stockage | Consommateurs |
|---|---|---|---|
| Pages du PDF | `DocumentImporter`, `DocumentStorage` | PDF de la bibliothèque | lecteur, moteurs OCR, OvisOCR2 |
| OCR avec positions | `OCRService` | SQLite `ocrResult`, par document/page/moteur | sélection sur la page, texte brut, recherche, vote, furigana |
| Lecture IA d'une page | `DocumentScan`, mise en page ou analyse, via `DocumentAITextStore` | `Analysis/<id>/<lecteur>-<page>.md` | mise en page, vérification, furigana, chat, vote |
| Rapport de comparaison | `DocumentAnalysisService` | `Analysis/<id>.json` | propositions de correction et fiabilité |
| Corrections acceptées | `OCRService.store` | SQLite `ocrResult` | mêmes vues que l'OCR ; les lignes retouchées à la main sont marquées `edited` |

## Règles de circulation

1. `OCRTargetLanguage` garde le choix par document. Japonais est le défaut ; Automatique laisse les écritures reconnues telles quelles. Le choix est fait avant l'import depuis Fichiers et reste accessible avant l'analyse complète.
2. OvisOCR2 reçoit une consigne adaptée à cette langue. Même en japonais, il doit conserver chiffres, lettres latines, unités et formules. Cette consigne améliore la lecture, sans la garantir.
3. `JapaneseOCRText` corrige la confusion constatée `图` → `図` lorsque le document est réglé sur Japonais. `OCRService` l'applique aux résultats nouveaux et aux caches existants à la lecture. Les lignes `edited` restent intactes.
4. `DocumentAITextStore.read` donne la même forme corrigée aux consommateurs des lectures IA. Le Markdown brut reste enregistré sans modification, pour permettre de comparer la sortie du modèle à la page.
5. Relire une page peut changer ses textes dérivés : le rapport de comparaison de cette page doit alors être invalidé, puis refait avant de servir de preuve de fiabilité.
   `DocumentAITextStore.write` retire aussi l'ancienne traduction française de cette page quand OvisOCR2 la relit.
6. **OCR retenu d'une page** (décisions D1, D2 et D7 de NOxygen59, 07/11/2026). Dans le lecteur, une seule règle, `OCRSelectionPolicy`, choisit la lecture d'une page : moteur choisi pour la page dans le panneau Texte, sinon moteur réglé ; en Auto, une lecture **déjà faite** passe avant une nouvelle lecture, dans l'ordre texte PDF, NDLOCR, PP-OCRv5, GLM-OCR, Apple Vision. Une version corrigée à la main passe **toujours** d'abord, même face au moteur réglé ou choisi dans le panneau, texte du PDF corrigé compris (décision F4 de NOxygen59) ; plusieurs corrigées : le moteur choisi d'abord, puis l'ordre ci-dessus. Une nouvelle lecture en Auto prend le premier modèle japonais installé, sinon Apple Vision. L'ordre exprime une politique, pas une qualité garantie.
7. **Adoption unique** (revue Codex de `d87e048`). `OCRPageSelection` date chaque intention par page (choix du menu, « Relancer », rotation, nouveau réglage). Lire le cache ne change rien ; `adoptOCR` change ensemble moteur retenu, zones, furigana, panneau et pastille, et refuse une lecture demandée avant une intention plus récente. `showOCR` ne rafraîchit que le moteur déjà retenu ; un appelant refusé ne touche pas au panneau. Un résultat refusé reste en cache. Le moteur **dessiné** est suivi à part du moteur demandé : passer d'un moteur à un autre (texte du PDF compris) retire les furigana de l'ancien. Si le moteur demandé échoue, la lecture **affichée** redevient explicitement l'OCR retenu (jamais une intention annulée ni non dessinée). Corriger ou annuler n'est possible que sur l'OCR retenu, pour que panneau et zones changent ensemble. Les corrections restent attachées à leur moteur ; une correction acceptée sur un autre moteur devient l'OCR retenu tout de suite. Sur une page corrigée, choisir un autre moteur dans le panneau ne remplace pas la version corrigée : le choix reste noté et reprend la main si les corrections sont annulées.
   Si le moteur demandé échoue, le choix du panneau rétabli est le dernier qui a été affiché pour la page, même après une rotation ; une intention restée sans affichage n'est jamais rétablie.
   Limites connues : un contenu plus ancien du même moteur peut encore remplacer un plus récent (étape 2). Les furigana du texte du PDF sont calculés sur la couche texte du fichier, pas sur sa version corrigée. Un texte PDF corrigé sur un scan (couche OCR invisible ajoutée par le scanner) est retenu, mais sa page n'a pas de furigana.
   Pas encore couvert : cartes, recherche dans le document, OCR du document entier, analyse et export gardent leur propre ordre (étapes 3 à 5) ; les versions de contenu d'un même moteur et l'écriture après PageShift relèvent de l'étape 2.

## Limites connues

- Une langue ciblée ne peut pas garantir une transcription exacte. Les formules et les numéros de figures demandent encore une vérification visuelle ; aucune correction automatique de chiffres n'est appliquée.
- La lecture déjà enregistrée n'est pas relancée quand la langue change. « Relire cette page » dans le lecteur permet une nouvelle lecture avec le réglage courant.
- La correction `图` → `図` est volontairement limitée à la confusion confirmée par la page fournie ; les autres caractères suspects ne sont pas remplacés par conjecture.

## Corrections et lecteur déjà ouvert (QA02)

Après un `OCRService.store` réussi, `cacheUpdated` annonce document, page source et moteur,
sans texte. Le lecteur ne recharge que son document, sa page de travail et son moteur ; il vérifie
à nouveau page et état après l'attente. Une écriture échouée ne déclenche pas de faux succès.
Cela inclut les corrections depuis l'analyse, qui ne passent pas par `AITaskCenter.finished`.
Le cache des débuts de mots est invalidé quand le résultat affiché change. Le stockage et le
marquage `edited` restent inchangés. [Preuves et limites](QA02-CORRECTIONS-OCR-DICTIONNAIRE.md).

« Garder tel quel » dans l'analyse accepte désormais explicitement le texte de base dans le cache OCR
avant de clôturer le désaccord, selon les mêmes contrôles que choisir une autre variante.
