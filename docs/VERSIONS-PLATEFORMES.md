<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Les trois versions de Kyōkasho

Référence de ce que chaque version embarque ou non. Décidé par NOxygen59 le 04/11/2026. La priorité reste l'iPad.

## Tableau

| Élément | iPad | Mac Intel | Mac Apple Silicon |
|---|---|---|---|
| État | candidate 1.5.9 | essai 1.4.2, branche `claude/mac-intel-ia` | essai 1.4.9 validé, branche `claude/mac-m5` |
| Appareil visé | iPad Pro M1, iOS 16.6.1, TrollStore | i5 1,4 GHz, 8 Go, macOS 15.8.2 | M5 ; essais possibles sur M2 Pro |
| Langues | français, anglais | français, anglais, chinois | français, anglais, chinois |
| Lexique intérieur | FR, EN | FR, EN, zh-Hans | FR, EN, zh-Hans |
| OCR Apple Vision, MeCab, dictionnaires, cartes | oui | oui | oui |
| NDLOCR-Lite, PP-OCRv5, mise en forme, DE-GAN (ONNX) | oui | oui, tranche réétiquetée, lecture à vérifier | prévu |
| OvisOCR2 | oui, MLX | oui, moteur `llama-server` embarqué, sur processeur | prévu, MLX |
| GLM-OCR, Qwen3-VL | oui, MLX | **non** | prévu, MLX |
| Chat de l'IA, Qwen3.5 | oui, MLX | **non** | prévu, MLX |
| Icônes de l'app | oui | **non**, refusées par le système | **non** |
| Fenêtre d'ouverture en 10:9 | sans objet | oui | prévu |
| Textes « iPad » / « MacBook » | iPad | MacBook (diagnostic), reste à finir | à finir |
| Moteur `llama-server` | **non** | oui | **non** prévu |

## Ce qui garantit la séparation

- **Code :** `#if targetEnvironment(macCatalyst)` pour ce qui diffère entre iPad et Mac ; `localAIAvailable` et `canImport(MLX)` pour ce qui dépend de MLX. Le code retiré ainsi n'est pas compilé.
- **Paquet iPad :** `build_ipa.sh` retire le chinois, puis `tools/check_ipad_package.py` bloque le paquet s'il reste du chinois, le moteur `llama-server` ou un lexique manquant.
- **Paquet Mac :** `tools/package_mac_intel.sh` (branche Mac) ajoute le moteur et les trois lexiques.
- **Textes :** le catalogue de traductions est commun. Les textes réservés au Mac y restent dans le paquet iPad, sans jamais s'afficher, faute de code qui les appelle.

## Encore à trancher

Présence sur Mac de : réglages Apple Pencil et gestes tactiles, mises à jour TrollStore de l'app, Google Drive.
