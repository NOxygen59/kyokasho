<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Relecture finale de la PR documentaire #1

Relecture du 25 octobre 2026, base `16d2dd8`, proposition initiale `44e450f`.

- Le diff de `App/`, des sources des packages, des manifestes, du paquetage et de `project.yml` est vide. Les seules modifications Swift sont deux références d'assertions de test, `.pages` vers `.results`, correspondant au tuple réel de `AppDatabase.ocrCacheStats`. Aucun comportement applicatif n'est modifié.
- Le workflow documentaire de la PR est réussi : [exécution 40113740121](https://github.com/NOxygen59/kyokasho/actions/runs/40113740121). Les liens locaux sont vérifiés à nouveau ; les contrôles des futurs commits doivent être observés séparément.
- Les responsabilités des manifestes, les chemins de données (`AppModel`, `ReviewModel`, `DocumentAITextStore`, `AIModelViews`) et le contrat OCR correspondent aux guides. La reprise PageShift n'est pas annoncée comme sûre : les fenêtres d'interruption restent des risques identifiés, à reproduire dans une PR fonctionnelle distincte.
- Les sept essais ignorés ne prouvent pas le fonctionnement des modèles ONNX ou d'UniDic. La compilation complète iOS, l'interface sur iPad, le rendu/les gestes, Qwen3.5 sur l'appareil, la restauration intégrale et les campagnes mémoire du produit restent non testés par cette PR.
- Le dépôt public observé et l'intention historique de dépôt privé restent explicitement distingués. Aucune permission n'est changée.

La PR #1 reste en brouillon, sans fusion automatique. Les corrections de données et les outils de sauvegarde de la phase 2 seront proposés séparément, avec leurs propres preuves. Les statuts de l'audit v1.3 décrivent sa base historique et ne doivent pas être réécrits comme si les correctifs suivants y avaient déjà été livrés.
