# Kyōkasho — instructions pour l'assistant de code (Codex)

Lecteur iPad de manuels japonais (PDF scannés) pour un francophone : OCR, IA locale (MLX sur iOS 16), furigana,
dictionnaires, cartes de révision. Usage personnel, jamais distribué, installé avec TrollStore sur **un** iPad Pro
12,9" M1 (8 Go) sous **iOS 16.6.1**.

**Avant toute chose, lis `docs/FEUILLE-DE-ROUTE.md` en entier** (§ 0 = passation et état réel ; § 2 = règles
obligatoires ; § 7 bis / § 8 = suite). Avant de toucher à l'IA ou à MLX : `docs/IA-LOCALE.md`.

Règles essentielles (détail au § 2 de la feuille de route) :
- Répondre à l'utilisateur **en français, court et simple** : il ne code pas ; dire ce qui change pour lui et pourquoi.
- Jamais de mot de passe, clé ou jeton demandé ou tapé. Supprimer ses fichiers : `trash`, jamais `rm`. Ne jamais
  supprimer un dépôt GitHub.
- **iOS 16.0 minimum** : ce qui manque à iOS 16 est comblé par du code équivalent, jamais en retirant la fonction ou
  en coupant un contrôle du compilateur (forks MLX `NOxygen59/mlx-swift`, `NOxygen59/mlx-swift-lm`, branche
  `ipad-ios16` ; mettre à jour l'épingle de `Package.resolved` après chaque push d'un fork).
- Pas de simulateur ni d'appareil sans la permission de l'utilisateur ; les tests sur l'iPad, c'est lui (release).
- Release seulement quand il la demande ; il donne le numéro. Procédure : § 5 de la feuille de route.
- Jamais de PDF, dictionnaire, modèle ou donnée tierce dans le dépôt. En-tête de chaque fichier :
  `// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`.
- Commits en français.

Construire (Mac, Xcode, `xcodegen`) :
- App : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Tests : `cd Packages/KyokashoKit && swift test`
- `.tipa` : `./build_ipa.sh` → `dist/Kyokasho-<version>.tipa`
