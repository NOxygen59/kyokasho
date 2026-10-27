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
6. Le cache choisi par le lecteur en mode OCR « Auto » suit le même ordre que `OCRService.resolve` : texte PDF, NDLOCR, PP-OCRv5, Apple Vision. Un ancien cache GLM-OCR ne doit plus devancer le moteur choisi automatiquement.

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
