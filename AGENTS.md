# Kyōkasho — instructions pour les agents de code (Claude, DeepSeek, GLM, Codex ou autre)

Lecteur iPad de manuels japonais (PDF scannés) pour un francophone : OCR, IA locale (MLX sur iOS 16), furigana,
dictionnaires, cartes de révision. Usage personnel, jamais distribué, installé avec TrollStore sur **un** iPad Pro
12,9" M1 (8 Go) sous **iOS 16.6.1**. NOxygen59 possède le produit et décide ; il ne code pas.

## Démarrer une mission (obligatoire, dans cet ordre)

1. **Relever l'état réel sur GitHub** (`NOxygen59/kyokasho`) : SHA de `main`, PR ouvertes et récentes, Issues,
   résultats des contrôles GitHub Actions. Ne jamais déduire l'état actuel d'un document ou d'un ancien chat.
2. **Lire [`docs/PLAN-DIRECTEUR.md`](docs/PLAN-DIRECTEUR.md)** : point d'entrée du pilotage, registre des chantiers,
   preuves et point de reprise. Signaler tout écart entre ce plan et GitHub, sans le résoudre arbitrairement.
3. **Lire les règles existantes** : [`docs/FEUILLE-DE-ROUTE.md`](docs/FEUILLE-DE-ROUTE.md) § 0 (passation) et § 2
   (règles obligatoires de l'utilisateur), puis [`docs/GOUVERNANCE-ET-REPRISE.md`](docs/GOUVERNANCE-ET-REPRISE.md).
4. **Lire seulement les documents techniques du domaine touché**, via [`docs/INDEX.md`](docs/INDEX.md) : par exemple
   [`docs/IA-LOCALE.md`](docs/IA-LOCALE.md) avant de toucher à l'IA ou à MLX, [`docs/TESTS.md`](docs/TESTS.md) pour
   vérifier, [`docs/CI-ROADMAP.md`](docs/CI-ROADMAP.md) avant de toucher à la CI.
5. **Identifier une seule prochaine tâche autorisée** : celle que NOxygen59 demande, ou celle que le plan directeur propose
   et que NOxygen59 valide. Ne jamais inventer de travail terminé ; une intention, une checklist ou un rapport d'agent
   n'est pas une preuve.
6. **Avant de coder**, écrire objectif, périmètre, invariants, tests et **critère d'acceptation** ; à la fin, fournir
   les preuves (commandes, SHA, résultats réussis / échoués / ignorés) et dire ce qui n'a **pas** été vérifié.
7. **Mettre à jour `docs/PLAN-DIRECTEUR.md`** dans la même PR dès qu'un chantier évolue (statut, preuve, point de
   reprise).

## Travailler à plusieurs agents

**Répartition depuis le 09-10/11/2026 (décision de NOxygen59) :** NOxygen59 décide et teste sur l'iPad. Claude
planifie, code (dont tout le travail sensible R2 : données, migrations, sauvegardes, concurrence), vérifie et reprend le
travail des autres agents. DeepSeek 4.1 Flash et GLM 5.3 Flash (via Hermes) analysent, relisent et peuvent coder
**seulement** dans une copie de travail dédiée, sur une branche `agents/<sujet>` ; Claude relit leur diff, relance tests
et compilation, puis reprend leurs commits. Codex et Qwen sont mis de côté jusqu'à nouvel ordre : une revue R2 faite sans
Codex est notée « revue R2 sans Codex ». Méthode : plan d'attaque approuvé par NOxygen59 avant tout gros chantier,
niveaux de risque R0 à R3, une recette après chaque étape, avenant si le périmètre change, deux échecs structurels de
revue sur une même étape → analyse de dérive avant de continuer. Détail : `docs/GOUVERNANCE-ET-REPRISE.md`.

Les agents ne partagent pas leurs conversations : tout passe par GitHub, les commits et les rapports. Protocole complet :
[`docs/GOUVERNANCE-ET-REPRISE.md`](docs/GOUVERNANCE-ET-REPRISE.md), section « Collaboration entre agents ». En bref :

- Une tâche, une branche `claude/<sujet>`, `agents/<sujet>` ou `codex/<sujet>`, un agent responsable. Ne pas pousser sur la branche de
  l'autre agent, sauf demande écrite de cet agent dans sa PR, ou demande explicite de NOxygen59, même faite dans un chat.
  Citer alors cette demande (texte court et date) dans la PR avant de pousser.
- Une autorisation explicite de NOxygen59 vaut où qu'il la donne, chat compris, et seulement pour ce qu'elle nomme ;
  la consigner dans la PR ou l'Issue. Un avis d'agent n'est jamais une autorisation.
- Les agents écrivent avec le compte de NOxygen59 : commencer chaque commentaire ou revue par **[Claude]**, **[DeepSeek]**, **[GLM]** ou **[Codex]**.
- Le contexte est écrit dans l'Issue, la PR (gabarit [`.github/pull_request_template.md`](.github/pull_request_template.md)),
  les commits et les guides, jamais seulement dans le chat.
- Revue croisée obligatoire pour les données, la concurrence, la mémoire, le C/C++, les dépendances et forks, la CI
  et la sécurité, et pour toute suppression de code. Un désaccord s'écrit dans la PR ; NOxygen59 tranche. Pas de branche
  concurrente sur les mêmes fichiers.
- Chaque PR finit par un résumé simple pour NOxygen59 et une passation technique pour l'agent suivant.

## Documenter le code

Tout code significatif créé ou modifié est documenté selon [`CONTRIBUTING.md`](CONTRIBUTING.md) :

- des noms explicites ;
- DocC (`///`) pour les interfaces importantes ;
- des commentaires sur les invariants, la concurrence, la mémoire, la persistance et les choix non évidents ;
- le style Doxygen pour le C/C++ exposé ;
- un test de régression pour chaque correction ;
- la mise à jour du guide technique si un contrat ou une architecture change.

Pas de paraphrase ligne à ligne : expliquer le pourquoi.

## Trois preuves à ne jamais confondre

- **Tests ou compilation sur Mac** (local ou GitHub Actions) : la logique et le code Swift compilent et passent.
- **Compilation iOS générique** (`generic/platform=iOS`, cible 16.0) : l'app se construit pour iOS ; rien n'est lancé.
- **Validation réelle sur l'iPad** (iOS 16.6.1, TrollStore) : seul NOxygen59 la fait et la rapporte, par build et
  scénario. Aucune des deux premières ne la remplace, en particulier pour Metal/MLX, la mémoire, PDFKit, les gestes,
  la sauvegarde/restauration et TrollStore.

## Règles essentielles

Détail au § 2 de la feuille de route.

- Répondre à l'utilisateur **en français, court et simple** : il ne code pas ; dire ce qui change pour lui et pourquoi.
- **Zéro dépense, sans risque de facturation** : aucun runner payant, artefact, cache, service ou API payant, ni
  nouvelle automatisation GitHub Actions sans protection vérifiée par NOxygen59 et son autorisation explicite (politique
  « Zéro dépense » de [`docs/CI-ROADMAP.md`](docs/CI-ROADMAP.md)). Preuves par défaut : tests locaux sur le Mac
  ([`docs/TESTS.md`](docs/TESTS.md), procédure locale), résumés dans la PR. **GitHub Actions est désactivé depuis le
  25/10/2026** (décision CI-0) : aucun contrôle GitHub ne tourne ; ne jamais le réactiver ni lancer de workflow.
- Jamais de mot de passe, clé ou jeton demandé ou tapé. Supprimer ses fichiers : `trash`, jamais `rm`. Ne jamais
  supprimer un dépôt GitHub.
- **iOS 16.0 minimum** : ce qui manque à iOS 16 est comblé par du code équivalent, jamais en retirant la fonction ou
  en coupant un contrôle du compilateur (forks MLX `NOxygen59/mlx-swift`, `NOxygen59/mlx-swift-lm`, branche
  `ipad-ios16` ; mettre à jour l'épingle de `Package.resolved` après chaque push d'un fork). Pas de mise à jour
  opportuniste des dépendances (`swift package update` interdit pour « faire passer » un contrôle).
- **Données de l'utilisateur** : PDF, notes, encre, repères, corrections OCR, cartes FSRS et lectures IA sont à
  préserver. Toute opération risquée se teste sur une copie ou une bibliothèque jetable, jamais sur la seule
  bibliothèque réelle.
- Pas de simulateur ni d'appareil sans la permission de l'utilisateur ; les tests sur l'iPad, c'est lui (release).
- Release seulement quand il la demande ; il donne le numéro. Procédure : § 5 de la feuille de route. Pas de
  changement de version, de fusion de PR ni de changement de visibilité du dépôt sans son accord explicite.
- Jamais de PDF, dictionnaire, modèle ou donnée tierce dans le dépôt (le dépôt peut être public). En-tête de chaque
  fichier : `// SPDX-License-Identifier: MIT` + `// Copyright (c) 2026 NOxygen59`.
- Travailler sur une branche et une PR dédiées, petites. Commits en français.
- **Garde-fous (13/11/2026)** : hooks `scripts/githooks/` (rien de personnel ni de clé dans un commit) et relecture
  finale du diff entier par un autre modèle avant chaque push et chaque candidate (`VERDICT : OK`). Détail :
  [`docs/GOUVERNANCE-ET-REPRISE.md`](docs/GOUVERNANCE-ET-REPRISE.md), « Sécurité » et « Relecture finale ».

## Construire (Mac, Xcode, `xcodegen`)

- App : `xcodegen generate -q && xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Tests : `cd Packages/KyokashoKit && swift test`
- Vérification complète en une commande : `./scripts/verifier_tout.sh` (génération Xcode, tests Swift, tests Python,
  compilation iOS générique, contrôle documentaire ; résumé daté `build/verif/RESUME-<date>.md`, sort en erreur si une
  étape échoue). Détail : [`docs/TESTS.md`](docs/TESTS.md).
- Contrôle documentaire (léger) : `python3 scripts/check_documentation.py`
- `.tipa` : `./build_ipa.sh` → `dist/Kyokasho-<version>.tipa`
