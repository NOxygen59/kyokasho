# Composants tiers

## Dépendances (Swift Package Manager)

| Composant | Auteur | Licence | Source |
|---|---|---|---|
| GRDB.swift 7.x | Gwendal Roué | MIT | https://github.com/groue/GRDB.swift |

## Code porté

Aucun pour l'instant (V1–V2 = code original uniquement). Chaque portage futur sera listé ici avec
l'URL du dépôt, le commit source et la licence, et gardera l'en-tête de copyright d'origine.

## Inspirations (comportement seulement, aucun code repris en V1)

- Aidoku (GPL-3.0) — https://github.com/Aidoku/Aidoku : réglages du lecteur.
- Yomitan (GPL-3.0) — https://github.com/yomidevs/yomitan : prévu pour la V3.

## Code porté (V3)

| Fichier(s) | Source | Commit | Licence |
|---|---|---|---|
| `Packages/KyokashoKit/Sources/YomitanKit/JapaneseText.swift` | yomidevs/yomitan `ext/js/language/ja/japanese.js` | `876253ca12e38aa6b0be3617e84827db5d9782b3` | GPL-3.0-or-later |
| `Packages/KyokashoKit/Sources/YomitanKit/LanguageTransformer.swift` | yomidevs/yomitan `ext/js/language/language-transformer.js` | idem | GPL-3.0-or-later |
| `Packages/KyokashoKit/Sources/YomitanKit/Resources/japanese-transforms.json` | données exportées de yomidevs/yomitan `ext/js/language/ja/japanese-transforms.js` (script `scripts/export_yomitan_transforms.mjs`) | idem | GPL-3.0-or-later |

Copyright (C) 2024-2026 Yomitan Authors, (C) 2020-2022 Yomichan Authors. https://github.com/yomidevs/yomitan

## Dépendances ajoutées (V3)

| Composant | Auteur | Licence | Source |
|---|---|---|---|
| ZIPFoundation 0.9.x | Thomas Zoechling | MIT | https://github.com/weichsel/ZIPFoundation |

## Dépendances ajoutées (V4)

| Composant | Auteur | Licence | Source |
|---|---|---|---|
| swift-fsrs (main, commit 4fbaf20) | Ben Smiley | MIT | https://github.com/open-spaced-repetition/swift-fsrs |

## Format seulement (V4)

| Composant | Auteur | Licence | Usage |
|---|---|---|---|
| genanki (commit 73f1debf) | Kerrick Staley | MIT | Description du format `.apkg` d'Anki. **Format seulement, aucun code copié** : l'export est réécrit en Swift. |

## OCR (V5)

| Composant | Auteur | Licence | Usage |
|---|---|---|---|
| ONNX Runtime (onnxruntime-swift-package-manager 1.24.2) | Microsoft | MIT | Exécution des modèles OCR sur l'iPad |
| Modèles PP-OCRv5 mobile (det + rec, ONNX) | PaddlePaddle ; conversion RapidAI/RapidOCR | Apache-2.0 | **Téléchargés à la demande**, jamais dans le dépôt |
| Dictionnaire `ppocrv5_dict.txt` | PaddlePaddle | Apache-2.0 | Téléchargé avec le modèle |
| NDLOCR-Lite (modèles DEIM + PARSeq, `NDLmoji.yaml`) | National Diet Library (Japon) | CC-BY-4.0 | **Téléchargés à la demande** ; crédit dans « À propos » |
| PaddleOCR, RapidOCR, NDLOCR-Lite (code Python) | idem | Apache-2.0 / CC-BY-4.0 | **Comportement seulement** : prétraitement et décodage réécrits en Swift, aucun code copié |
