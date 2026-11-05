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
| Modèle DE-GAN « binarisation » (poids Keras convertis en ONNX par `tools/degan_to_onnx.py`) | M. A. Souibgui, Y. Kessentini | GPL-3.0 | **Téléchargé à la demande** depuis le dépôt public NOxygen59/kyokasho-models (avec sa licence), jamais dans ce dépôt ; netteté des scans |
| Modèles de mise en page PP-DocLayout v3 (Apache-2.0, PaddlePaddle) et DocLayout-YOLO DocStructBench (AGPL-3.0, OpenDataLab), versions ONNX de RapidAI/RapidLayout (Apache-2.0) ; pré/post-traitement repris de RapidLayout | PaddlePaddle ; OpenDataLab ; RapidAI | Apache-2.0 / AGPL-3.0 | **Téléchargés à la demande**, jamais dans le dépôt ; texte mis en forme |
| Dictionnaire `ppocrv5_dict.txt` | PaddlePaddle | Apache-2.0 | Téléchargé avec le modèle |
| NDLOCR-Lite (modèles DEIM + PARSeq, `NDLmoji.yaml`) | National Diet Library (Japon) | CC-BY-4.0 | **Téléchargés à la demande** ; crédit dans « À propos » |
| PaddleOCR, RapidOCR, NDLOCR-Lite (code Python) | idem | Apache-2.0 / CC-BY-4.0 | **Comportement seulement** : prétraitement et décodage réécrits en Swift, aucun code copié |
| MLX Swift 0.29.1, mlx-swift-lm 2.29.3 | ml-explore (Apple) | MIT | Exécution du modèle IA GLM-OCR |
| `Packages/GLMOCRKit/Sources/GLMOCRKit/GlmOcr.swift`, `QwenVLHelpers.swift` | ml-explore (mlx-swift-lm 2.31.3 / 2.29.3), d'après mlx-vlm (Prince Canuma) | MIT | **Code copié et adapté** (iOS 16) ; Copyright (c) 2024 ml-explore, licence MIT conservée |
| swift-transformers 1.1.9 | Hugging Face | Apache-2.0 | Tokenizer de GLM-OCR (dépendance de mlx-swift-lm) |
| Modèle GLM-OCR 4 bits (mlx-community/GLM-OCR-4bit) | Zhipu AI ; conversion mlx-community | MIT | **Téléchargé à la demande**, jamais dans le dépôt |

## Analyseur japonais (0.8.4)

- **MeCab 0.996** — Taku Kudo, Nippon Telegraph and Telephone Corporation. Licence triple GPL / LGPL / **BSD** :
  BSD choisie. Code source copié sans changement dans `Packages/KyokashoKit/Sources/MeCabC` (sauf `config.h`,
  écrit pour iOS) ; texte de la licence dans `Sources/MeCabC/LICENSE-BSD`. https://github.com/taku910/mecab
- **UniDic 2.1.2** (via **unidic-lite 1.0.8**, Paul McCann, MIT) — UniDic Consortium, licence triple GPL / LGPL /
  **BSD** : BSD choisie. **Pas dans le dépôt ni dans l'app** : téléchargé à la demande depuis PyPI
  (`unidic-lite-1.0.8.tar.gz`, SHA-256 vérifié). https://github.com/polm/unidic-lite

## MLX récent sur iOS 16 + OvisOCR2 (0.8.4)

- **mlx-swift 0.32.3** et **mlx-swift-lm 3.32.3** (Apple, MIT) — utilisés via les forks
  `NOxygen59/mlx-swift` et `NOxygen59/mlx-swift-lm`, branche `ipad-ios16` (rétroportage iOS 16 : bfloat logiciel
  dans les noyaux Metal, voir leur `IPAD-IOS16.md`). GLM-OCR vient désormais de mlx-swift-lm (notre copie retirée).
- **swift-transformers 1.3.5** (Hugging Face, Apache-2.0) — tokenizers (et ses dépendances swift-jinja,
  swift-huggingface, swift-collections, swift-crypto, yyjson : Apache-2.0 / MIT).
- **OvisOCR2** (ATH-MaaS, Apache-2.0), conversion MLX 8 bits par tokimoa (Apache-2.0). **Pas dans le dépôt ni
  dans l'app** : téléchargé à la demande depuis Hugging Face (`tokimoa/ovisocr2-mlx-8bit`, SHA-256 vérifié).
- **Qwen3.5-4B** (Alibaba Qwen, Apache-2.0), conversion MLX 4 bits par mlx-community. **Pas dans le dépôt ni
  dans l'app** : téléchargé à la demande depuis Hugging Face (`mlx-community/Qwen3.5-4B-4bit`, commit
  `0e7ffd5c629ef7719d4cbc04069232580bfa9d9c` ; poids et tokenizer vérifiés par SHA-256).

## Batterie du lecteur (05/11/2026)

- **DuoBar** (Mike Li, MIT, https://github.com/Mikeli7666/DuoBar) — géométrie de l'anneau de l'iPhone Duo, proportions
  (trait, ouverture, éclair) et règle de couleur reprises et réécrites pour iPadOS dans `DuoBatteryRing.swift` et
  `ReaderStatusBadge.swift`. Licence : `LICENSES/MIT.txt`, Copyright (c) 2026 Mike Li.
