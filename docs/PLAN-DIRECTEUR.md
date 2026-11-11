<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Plan directeur — professionnalisation de Kyōkasho

**Cartes E1 — écran « Cartes de ce document » — 11/11.** PLAN-CARTES-001 (approuvé le 11/11, tout A), branche `claude/ipad-tableau-mesures`, local. Index additif `v2-card-source` de la base des révisions (testé sur une base v1 peuplée), `cards(sourceDocumentId:query:)` sans limite, `saveEdited` (mot/lecture modifiables, clé anti-doublon suivie, seules les colonnes éditées écrites : FSRS jamais réécrit), écran par document ouvert depuis l'accueil et le lecteur, export Anki par `onDismiss`. Revue DeepSeek D-07 (`DEEPSEEK-D07-CARTES-E1-980f316.md`, PARTIAL) traitée. Preuves Mac seulement ; recette iPad à faire ; E2 (mots de la page) non commencée.

**T5 E2 — dossiers sur l'accueil — 11/11.** PLAN-T5-001 (approuvé le 10/11). Dossiers en tête, ouvrir, « Déplacer vers… », sélection → « Déplacer », nouveau / renommer / supprimer ; base : espace réel relu, sortie du dossier au changement d'espace, création + rangement en une transaction, fusion Drive garde le dossier. Revue DeepSeek D-07 (`DEEPSEEK-D07-T5-E2-b8fa03e.md`, PARTIAL, données sans défaut) traitée à `f847c72`. Preuves Mac seulement ; recette iPad à faire.

**Lot 1.5.6 (retours de la recette 1.5.5 + travail de Fable) — 11/11.** Branche `claude/ipad-tableau-mesures`, local, non poussé. Recette 1.5.5 : 41/46 (rapport `patchs-en-attente/recettes/rapports/RESULTATS-RECETTE-IPAD-1.5.5.md`). Correctifs de Claude : notes de version 1.5.5/1.5.6 et garde `build_ipa.sh` + `tests/test_release_notes_version.py` (une candidate sans notes est refusée) ; chat du livre fermé seulement par « Fermer » (10.3) ; garde Pencil réappliquée à chaque page créée pendant le dessin + trace « gestes » (1.1) ; défilement de « Cartes de la page » (5.8). Repris de Fable (demande de NOxygen59 du 11/11, relus par Claude, revue DeepSeek D-07) : BUG-001 à 005 et 007, Lexique E2/E3, étoile et « Mes mots », aide des gestes, rappel de luminosité. Preuves Mac seulement ; rien d'essayé sur l'iPad ; Drive 8.1-8.4 à recetter.

**Rappel de luminosité — 11/11.** Lot local sur `agents/fable-luminosite`, base `67b48fd` (choix de NOxygen59 du 11/11). Dans le lecteur, sur batterie et au-dessus de 90 % de luminosité, une bannière rappelle le coût mesuré sur le relevé de l'iPad (36 points par heure contre 13 à 60 % ou moins). « OK » la ferme jusqu'au prochain lancement, « Ne plus afficher » éteint le réglage (Réglages → Pages et gestes → Batterie). Aucun réglage de luminosité modifié. Preuves Mac seulement (`BrightnessReminderTests`, compilation iOS générique) ; recette iPad à faire. Ni fusion ni candidate.

**Aide aux gestes du lecteur — 11/11.** Lot local sur `agents/fable-aide-gestes`, base `67b48fd` (demande de NOxygen59 du 11/11). Dans le lecteur, menu « … » → « Aide : gestes de lecture » ouvre une feuille qui décrit les gestes réellement branchés (tourner la page, barres, zoom, sélection, dictionnaire, surligneur, dessin), selon le document et ses réglages. Aucun geste modifié, rien d'enregistré. Preuves Mac seulement (`ReaderGestureHelpTests`, compilation iOS générique) ; recette iPad à faire, revue de Claude avant toute intégration. Ni fusion ni candidate.

**Lexique : étoile, carte et « Mes mots » — 11/11.** Lot local sur `agents/fable-lexique-etoile`, au-dessus de `agents/fable-lexique` (`01c4e20`, E2 et E3 non relues) ; choix de NOxygen59 du 11/11, hors du plan PLAN-LEX-001 (qui excluait les favoris propres au Lexique : ici ce sont les mots enregistrés du dictionnaire, la même liste). Chaque ligne du Lexique porte une étoile et « + carte » ; un filtre « Mes mots » ne garde que les mots enregistrés présents dans les dictionnaires actifs. Lecture seule côté dictionnaires ; la carte passe par le chemin existant. Preuves Mac seulement (`LexiconSavedWordsTests`, compilation iOS générique) ; recette iPad à faire. Ni fusion ni candidate.

**Lexique E2 et E3 — 10/11.** Lot local sur `agents/fable-lexique`, base `f912b88` (plan PLAN-LEX-001 approuvé le 10/11). Dans Livres & Manuels, l'entrée « Lexique » ouvre la liste paginée des mots des dictionnaires installés et actifs (forme, lecture au-dessus des kanji, sens français et anglais, « — » si absent) ; toucher un mot ouvre la fiche du dictionnaire, un champ cherche par début de mot. Lecture seule, aucune migration. Preuves Mac seulement (tests `LexiconFeedTests`, `LexiconSearchTests`, compilation iOS générique) ; recette iPad E2 et E3 à faire, revue D-07 à faire, E4 non commencée. Ni fusion ni candidate.

**Accueil iPad et thèmes — 06/11.** Lot local sur `codex/accueil-themes`, base `0bfd81b`. Dans Réglages → Thèmes, la pilule Kyōkasho | Manga affiche les cartes de l’espace choisi. La palette suit le document dans le lecteur, puis l’espace affiché au retour. L’accueil garde une carte repère par espace et fond un cliché de la fenêtre lors de la bascule. Recette iPad et revue Claude à faire.

**Accueil personnel iPad — 05/11.** Lot local `codex/accueil-ipad` sur `7a3d742`. Réglages → Thèmes propose une palette indépendante pour chaque espace, avec la palette générale comme repli. Le fond de la bibliothèque fait un fondu, sauf avec Réduire les animations. La rangée compacte montre les couvertures, types et pages de reprise des documents ouverts dans les deux espaces. Elle est désactivable. Mac et iPhone gardent leur présentation. Vérifications locales : 17 tests Swift ciblés, 30 contrôles Python, 167 liens et compilation iOS Release générique réussis. Recette iPad à faire : choisir deux palettes dont une claire, alterner vite en portrait et paysage, revenir après ouverture d’un document de l’autre espace, fermer un onglet, relancer et vérifier les préférences. GitHub `main` observé à `398721d`, distinct de la base locale de ce lot.

**05/11 — refonte visuelle demandée par NOxygen59 :** huit univers distincts sur branche locale `codex/identite-themes`, base `57deec9`. Identifiants historiques conservés ; [preuves, limites et revue Claude ciblée](REFONTE-THEMES-2026-11-05.md). Aucun accord de fusion, candidate ou validation iPad déduit.

> **Lot local lexique du 04/11/2026 :** [livraison multilingue et revue ciblée](LEXIQUE-LANGUES-REPRISE.md), `codex/lexique-langues`, base `15f18a3`. Archives EN et chinois court hors dépôt, 3 836 entrées chacune ; anglais 8 121/8 121 textes. Vrai import/réouverture et filtre vérifiés, 432 Swift réussis / 7 ignorés, 67 Python, compilation iOS Release générique réussie. Revue Claude, raccordement au paquet Mac et recettes Mac/iPad restent à faire. Aucune fusion/push/version/candidate autorisée par cette note.

> **Lot local du 04/11/2026 — MAINT-01 / QA-03 :** [nettoyage ciblé](NETTOYAGE-CIBLE-2026-11-04.md) sur `codex/nettoyage-cible`, base `a7ee0e8` : test des variables de traduction réparé, ancien dialogue OCR protégé, seule méthode interne `shiftReport` sans appel retirée. Lot autorisé par NOxygen59, vérification et revue séparées ; aucune fusion, nouvelle candidate ou preuve iPad ne découle de cette note. Les états historiques ci-dessous sont conservés.

> **Point d'entrée de pilotage pour les humains et agents IA.** Ce fichier suit la transformation *technique* du projet, pas le backlog de fonctionnalités. Il n'est **pas** une autorisation d'implémenter, fusionner, publier ou modifier les données. Lire [AGENTS.md](../AGENTS.md) avant toute action.
>
> **Dernier instantané vérifié : 27 octobre 2026, après la recette 1.3.2.** `main` à `738dceb7fd09ccfcb1b9feb454c1d695d2658d9d` (fusion de #59), avant la fusion de cette mise à jour (#62). Les PR #8 à #10, #25, #27 à #33 et #56 à #59 sont fusionnées. Le [registre des retours iPad](RETOURS-IPAD.md) contient **RET-001 à RET-042** et fait foi. La build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e` a été validée par NOxygen59 **avec limites** : RET-010, RET-011 et RET-012 **confirmés iPad** (Issues #13, #14, #15 fermées) ; deux nouveaux retours ouverts, RET-041/[#60](https://github.com/NOxygen59/kyokasho/issues/60) et RET-042/[#61](https://github.com/NOxygen59/kyokasho/issues/61). **Aucune release publiée.** **GitHub Actions reste désactivé** (CI-0). Ne pas considérer cet instantané comme actuel sans interroger GitHub.

## 0. Rôles et méthode au 10/11/2026

**Qui fait quoi.** NOxygen59 décide, tranche et fait les essais sur l'iPad ; il ne code pas. **Claude** planifie,
code (dont tout le travail sensible, niveau R2), vérifie et reprend le travail des autres agents. **DeepSeek 4.1 Flash**
et **GLM 5.3 Flash** (via Hermes) analysent, relisent et peuvent coder **seulement** dans une copie de travail dédiée
(branche `agents/<sujet>`), relue et testée par Claude avant reprise. **Codex** et **Qwen** sont mis de côté jusqu'à
nouvel ordre ; une revue de niveau R2 faite sans Codex est notée « revue R2 sans Codex ».

**Méthode.** Plan d'attaque approuvé par NOxygen59 avant tout gros chantier ; niveaux de risque R0 à R3 (R0
documentation et outillage sans effet sur l'app, R1 correctif local et testé, R2 données, concurrence, mémoire,
C/C++, dépendances et forks, CI, sécurité et suppressions de code, R3 changement de contrat, de données ou
d'architecture) ; une recette après chaque étape ; avenant écrit si le périmètre change ; deux FAIL structurels
déclenchent une analyse de dérive écrite avant de continuer.

**Écart à signaler, non résolu ici.** Le lot décrit au § 3 bis est la pointe `76cd371` de la branche locale
`claude/ipad-tableau-mesures` ; `main` lu sur le Mac de travail est à `48fff3a`. Aucun push ni fusion de ce lot n'est
constaté par cette note : la pointe locale n'est pas `main`.

## 1. Utilisation par un nouvel agent (obligatoire)

1. Vérifier sur GitHub la branche `main`, son SHA, les PR, les Issues et leurs contrôles, ainsi que la présence des documents cités. Ne pas déduire l'état actuel de cet instantané.
2. Lire `AGENTS.md` (Claude Code le charge via `CLAUDE.md`), ce plan, la [collaboration entre agents](GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex), [la feuille de route produit](FEUILLE-DE-ROUTE.md), l'[index documentaire](INDEX.md) et les documents techniques du domaine touché.
3. Comparer chaque statut ci-dessous aux preuves GitHub et aux retours d'essais iPad. Documenter les divergences, sans les résoudre arbitrairement.
4. Choisir **une seule tâche débloquée** par mission. Avant de coder, préciser objectif, périmètre, dépendances, invariants, tests, critère d'acceptation et autorisation requise.
5. Travailler sur branche/PR dédiée ; ne pas fusionner, changer la visibilité, créer une release ou toucher aux données personnelles sans accord explicite.
6. À la fin : mettre à jour les lignes touchées, leurs preuves (PR/commit/tests) et ce « point de reprise » ; déclarer les contrôles **non exécutés**.

**Hiérarchie des preuves :** état GitHub actuel et code au SHA étudié pour l'implémentation ; tests et artefacts datés pour la vérification ; essais documentés sur l'iPad pour l'expérience réelle ; guides et historiques pour les intentions. Une affirmation d'agent ne suffit pas.

**Statuts par axe** : préparation (`prévu / en cours / bloqué`), intégration (`PR / fusionné`), validation (`Mac vérifié / iOS compilé / iPad confirmé / non essayé`). Ne jamais compresser tous ces axes en un unique « terminé ».

## 2. Contrat produit à préserver

- Application personnelle de lecture et d'étude de PDF japonais ; cible concrète : **iPad Pro M1, iOS 16.6.1, TrollStore**. Déploiement déclaré : iOS 16.0 minimum.
- PDF et données originales à préserver ; éviter toute modification destructive, surtout notes, encre, repères, corrections OCR, cartes FSRS et lectures IA.
- Les tests Mac, une compilation générique iOS et les retours iPad **ne sont pas interchangeables**.
- MLX/Metal : forks `ipad-ios16` et dépendances épinglées ; pas de remplacement opportuniste.
- Pas de simulateur, installation appareil, modification de version, release ou fusion implicite.
- Le dépôt est **public** au relevé du 25/10 (alors que [la feuille de route](FEUILLE-DE-ROUTE.md) § 0 le dit « privé ») ; la décision de visibilité appartient au propriétaire. Ne jamais publier des PDF, secrets, logs bruts ou jeux d'essai privés.

## État actuel au 27 octobre 2026

| Niveau | Éléments |
|---|---|
| **Terminé et confirmé** | Socle documentaire et gouvernance fusionnés ; PR #8 à #10, #25, #27 à #33 et #56 à #59 fusionnées ; RET-008 et RET-009 confirmés iPad (1.3.1 (41), puis sans régression en 1.3.2 (42)) ; RET-010, RET-011 et RET-012 confirmés iPad en 1.3.2 (42) |
| **En validation** | RET-001, RET-002, RET-003 et RET-006 : correctifs présents dans les builds locales, sans scénario dédié dans les recettes 1.3.1 et 1.3.2 |
| **Ouvert** | Retours marqués « rapporté » dans [RETOURS-IPAD.md](RETOURS-IPAD.md), ainsi que DATA-01, DATA-02, DATA-03, QA-03, PERF-01, MAINT-01 et SEC-01 selon leurs preuves manquantes |
| **Conception seulement** | RET-034 (suppression de pages), RET-036 (cloud), RET-040 et PORT-01 (version Mac), DIAG-01 ; aucune implémentation autorisée par ce classement |

Le registre iPad porte le détail par retour. Cette vue indique seulement le niveau de maturité et ne remplace ni les Issues ni les preuves.

## 3. Registre des chantiers de professionnalisation

**Code de statut de cette table :** « fusionné » n'est **pas** « testé iPad » ; « à valider iPad » n'est **pas** « testé iPad ». Les tâches nouvelles ne sont que **proposées**, jamais automatiquement autorisées.

| ID | Chantier | Situation au relevé | Preuve / source | Prochaine condition de clôture |
|---|---|---|---|---|
| GOV-01 | Documentation, architecture, contribution, tests | **Fusionné** le 25/10 (commit de fusion `92a0315`) ; contrôle `Documentation` réussi sur `main` | [PR #1](https://github.com/NOxygen59/kyokasho/pull/1) ; [INDEX.md](INDEX.md) | Clos pour l'intégration ; tenir les guides à jour à chaque PR |
| GOV-02 | Plan directeur de professionnalisation (ce fichier) | **Fusionné** le 25/10 (`ee07c55`) ; mise à niveau au 27/10 préparée dans une PR documentaire séparée, sans changement applicatif | [PR #4](https://github.com/NOxygen59/kyokasho/pull/4) ; ce fichier | Fusionner la mise à niveau seulement après relecture ; continuer à actualiser le plan quand un chantier évolue |
| GOV-03 | Consolidation : instructions des agents, publication du plan CI, contrôle des documents obligatoires | **Fusionné** le 25/10 (`f76d9f6`) ; contrôle `Documentation` réussi sur `main`. Contenu : `AGENTS.md` commence par l'état GitHub et ce plan ; `docs/CI-ROADMAP.md` publié ; `scripts/check_documentation.py` vérifie aussi les documents et renvois obligatoires | [PR #5](https://github.com/NOxygen59/kyokasho/pull/5) (branche `docs/gouvernance-ci-roadmap`) | Clos pour l'intégration |
| GOV-04 | Protocole Claude / Codex, documentation du code, gabarits de PR et d'Issue, politique « Zéro dépense » | **Fusionné le 25/10/2026** (`f83aec8`), vérifié lors de QA-02 ; revue de Codex reçue (2 remarques, traitées) : protocole dans [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md#collaboration-entre-agents-claude-et-codex) (autorisations de NOxygen59 valables dans un chat et consignées, commentaires signés [Claude]/[Codex]), règles de documentation dans [CONTRIBUTING.md](../CONTRIBUTING.md), `CLAUDE.md` qui importe `AGENTS.md`, gabarits `.github/`, politique « Zéro dépense » et tests locaux dans [CI-ROADMAP.md](CI-ROADMAP.md) et [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | [PR #6](https://github.com/NOxygen59/kyokasho/pull/6) (branche `claude/collaboration-agents-ci-gratuite`) | Intégration close ; QA-02 reprend le gabarit de PR et fournit la preuve locale |
| DATA-01 | Reprise idempotente d'ajout de pages / PageShift | **Fusionné** le 25/10 (`a016091`) ; `Stockage Mac` réussi sur `main` après #1+#2 et après #1+#2+#3 ; le 27/10, 17 tests de sécurité et de reprise ajoutés (cadrage #73, PR #75, revue Codex favorable) : 39 tests PageShift verts, ASan propre, défaut RET-048 (#74) trouvé puis corrigé par la PR #77 (en revue) ; **non essayé sur iPad** | [PR #2](https://github.com/NOxygen59/kyokasho/pull/2) ; [PR #75](https://github.com/NOxygen59/kyokasho/pull/75) ; [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md) ; [TESTS.md](TESTS.md) ; runs `40152364389`, `40152582505` | Recette iPad sur copie : OCR concurrent, annotations, gros PDF |
| DATA-02 | Sauvegarde et restauration hors ligne | **Fusionné** le 25/10 (`c2b1b29`) ; `Sauvegarde synthétique` réussi sur `main` ; **restauration TrollStore/iPad non démontrée** ; le 28/10, tests synthétiques renforcés (cadrage #83 : inventaire, noms Unicode, SIGKILL, schéma ancien), sans correctif | [PR #3](https://github.com/NOxygen59/kyokasho/pull/3) ; [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md) ; run `40152580509` | Qualifier extraction/restauration sur iPad avec une bibliothèque jetable avant tout usage réel |
| QA-01 | Tests de logique et stockage | Socle de stockage fusionné et testé sur Mac ; les PR récentes documentent leurs preuves locales séparément. Preuve déclarée sur l'assemblage local des trois PR #31 → #32 → #57 (`aeb8d01`) : 188 tests Swift réussis, 7 ignorés, 16 Python, documentation sans erreur et compilation iOS générique réussie. **Ce résultat ne valide ni l'iPad, ni MLX/Metal.** | PR #2/#3 ; [TESTS.md](TESTS.md) ; preuves des PR #31/#32/#57 | Maintenir les tests ciblés par correction ; relever explicitement les ignorés et réserver les scénarios matériels à l'iPad réel |
| CI-01 | Automatisation CI | **GitHub Actions désactivé le 25/10/2026** (décision CI-0 de NOxygen59, vérifiée via l'API : `enabled: false`). Les trois workflows (`documentation.yml`, `storage.yml`, `backup.yml`) restent versionnés mais inactifs. Politique « Zéro dépense » (GOV-04). **Tests exécutés localement** sur le Mac de NOxygen59 et documentés dans chaque PR par une fiche de preuve | [CI-ROADMAP.md](CI-ROADMAP.md) ; [TESTS.md](TESTS.md#procédure-locale-standard-avant-une-pr) | CI-G (script local de fiche de preuve) sur accord ; réactivation d'Actions seulement par NOxygen59, après protection vérifiée et autorisation par workflow |
| QA-02 | Recette iPad par version | Recette fusionnée avec la [PR #7](https://github.com/NOxygen59/kyokasho/pull/7) (`431f1c6`). Registre **RET-001 à RET-042**. Build locale 1.3.1 (41) : RET-008/009 confirmés. Build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e` : RET-010/011/012 **confirmés iPad**, régressions rapides OK, nouveaux RET-041 et RET-042. DATA-01/DATA-02/DATA-03/PERF-01 restent sans validation appareil complète. | [RETOURS-IPAD.md](RETOURS-IPAD.md) ; [RECETTE-IPAD-QA-02.md](RECETTE-IPAD-QA-02.md) ; Issues [#60](https://github.com/NOxygen59/kyokasho/issues/60), [#61](https://github.com/NOxygen59/kyokasho/issues/61) | Prochaine candidate seulement pour un nouveau lot autorisé ; ne fermer les Issues qu'après résultat consigné |
| DATA-03 | Géométrie annotations/export après égalisation | Risque identifié, **non clos** | [AUDIT-V1.3.md](AUDIT-V1.3.md) ; [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) | Tests pages tournées et tailles mixtes + validation iPad |
| QA-03 | Contrats OCR, japonais, chat et citations de pages | Tests existants, couverture supplémentaire proposée | [TESTS.md](TESTS.md), [ARCHITECTURE-LECTURE.md](ARCHITECTURE-LECTURE.md) | Tests ciblés des corrections manuelles, langues, invalidations et requêtes « p. 6 » |
| PERF-01 | Profilage mémoire/performance | Procédures documentées ; **pas de campagne globale iPad/MLX ou LSan réussie attestée** | [MEMOIRE-ET-SANITIZERS.md](MEMOIRE-ET-SANITIZERS.md) | Baselines froid/chaud ; instruments compatibles ; vérifier Swift ARC, MeCab, ONNX et Metal séparément |
| MAINT-01 | Nettoyage et modularisation progressifs | Dix pistes classées, désormais sur `main` ; **pas de nettoyage général réalisé** | [PHASE2-NETTOYAGE.md](PHASE2-NETTOYAGE.md) | Une correction ciblée par PR, test avant/après, preuve d'absence de régression |
| DIAG-01 | Centre de tests guidés sur iPad / Diagnostic 2.0 | **Idée proposée, non implémentée et non approuvée** | Discussion de conception ; aucun commit revendiqué | Spécification privacy-first, faisabilité, prototypes limités ; résultats humain/automate distincts |
| SEC-01 | Confidentialité, licences, visibilité, protection de `main` | Dépôt **public** ; `main` **sans protection de branche** ; divergence avec la feuille de route (« privé ») | État GitHub au 25/10 ; [AUDIT-V1.3.md](AUDIT-V1.3.md) | Décision du propriétaire sur la visibilité et la protection, inspection des données publiques, garde-fous et licences |
| OPS-01 | Gouvernance de PR/release, traçabilité et ADR | Guides fusionnés avec #1 ; fusions #1→#3 faites PR par PR avec revérification de `main` | [CONTRIBUTING.md](../CONTRIBUTING.md), [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) | Gabarits utiles, statut sur chaque PR, liens exigences→tests→résultats |
| PORT-01 | Application macOS (.app/.dmg) | **Option de produit, non démarrée** ; packages macOS ≠ app macOS | `Packages/KyokashoKit/Package.swift`, `project.yml` | Décision produit + étude Catalyst/natif séparée, sans altérer la cible iPad |
| C2 | Remplacement d'un cours Drive : OCR relu et rognage auto remis à zéro (DEC-C1 = A), cartes suivies (DEC-C2 = A), brouillons et lectures IA suivis, puis, après revue R2, langue OCR, historique des ajouts, temps de lecture, refus des plans et journaux altérés, conflits mis de côté et affichés dans le rapport ; **DEC-C3 (10/11/2026) et finitions de la contre-revue R2** : corrections manuelles mises de côté avant l'effacement du cache OCR et remises à l'enregistrement du nouveau résultat (`Corrections-remplacement/`), encre du survivant en fusion mise de côté (`Conflits-remplacement/Encre/`), relance de la lecture IA après la levée de la réservation, messages de refus au catalogue (FR/EN/zh-Hans), journal refusé mis de côté (l'app démarre), taille illisible ≠ PDF illisible, nettoyage du temporaire de téléchargement, compte des mises de côté sur le disque (`cote.json`) | Lot C2.1–C2.3, corrections de la revue R2 (n°1 à n°10) puis DEC-C3 et n°1 à n°4, n°6 à n°8 de la contre-revue sur la branche `agents/c2-drive` (1fcb781 + commits du 10/11/2026, dont `631e03c`, `9a6b1d9`, `460eb19`, `2b4be3d`, `d40dedb`, `0e8a349`, `79c0090`, `8b65cd0`) ; **non fusionné dans `main`**, jamais essayé sur iPad | Chiffres de tests (Swift complet, Python, compilation iOS générique) consignés dans le rapport de passation GLM `Kyokasho-Pont/REVUES/GLM-CODE-C2-DRIVE-REPRISE2-c03712a.md` et la PR de la branche | Revue croisée, fusion après accord de NOxygen59, puis recette iPad sur bibliothèque jetable (Metal/MLX, PDFKit, gestes, TrollStore : validation de NOxygen59 seulement) ; interface « Données mises de côté » (N5) restée en dehors de cette reprise |

Les chantiers n'ont **pas** d'avancement en pourcentage : cela produirait une précision trompeuse. L'ordre n'est pas une promesse de calendrier.

## 3 bis. Chantiers en cours au 10/11/2026 (base `76cd371`)

Relevé fait en lisant uniquement les messages de `git log f85d0c0..76cd371` sur la branche locale
`claude/ipad-tableau-mesures`. Tous ces lots sont **hors `main`, sans fusion ni push constatés, non testés iPad**.
Les chiffres cités sont ceux qu'annoncent les commits, pas un rejeu de cette note ; les preuves rejouables sont
décrites aux § 5 et dans [TESTS.md](TESTS.md).

| Chantier | Ce que les commits établissent | Preuve annoncée dans le commit |
|---|---|---|
| T1 — Pencil en page seule (`15e3a6d`) | avec la transition « Glissement », le défilement du contrôleur de pages prenait le Pencil pour un doigt ; pendant le dessin, les défilements sous la vue PDF refusent le Pencil, doigt et trackpad tournent toujours la page ; règle `PencilPageTurnGuard` en `ReaderCore` | 3 tests |
| T2 — chat du livre (`8bae17b`, corrections de la revue D-07 en `1bccd65`) | consigne déplacée dans `ReaderCore/BookChatPrompt` : extraits utilisés s'ils répondent, sinon réponse générale signalée « Explication générale, pas tirée du manuel. » ; « Pages consultées » ne liste que les pages citées | 4 tests `BookChatPromptTests` ; 2 tests ajoutés par la revue D-07 |
| T3 — navigateur intégré (`9477599`, `28431ac`, `1bccd65`) | la connexion Google s'ouvre dans une vraie fenêtre (WKWebView fille en feuille, fermée par la page) ; liens `target="_blank"` dans la même vue ; recherche Brave dans la barre d'adresse | 3 tests `WebPopupPolicyTests` ; 1 test pour la logique `WebAddress` |
| C1 — correctifs des audits du 09/11 (`c03494d`, puis `cf5428a`, `619c745`, `d422f07`, `0e6a75a`, `65a3704`) | C1.1 à C1.9 : traduction de définition gardée avec sa source et son avis 👍/👎, `ToneCache.clear()` libère le PDF gardé ouvert, lecture OCR annulée affichée comme repos et plus comme échec, message clair quand les cartes de l'export ont disparu, garde `StyleTokensGuardTests` alignée sur l'annulation | `TranslationFreshness`, `EqualizedBoxes`, `OCRCancellation` ; des gardes de câblage Python pour les correctifs qui touchent l'app (export des cartes, annulation OCR, `ToneCache`, avis de traduction) ; `swift test` complet vu à 627 tests dont 1 échec, celui de la garde, corrigé ensuite |
| C2 — gardes de suppression et de sauvegarde (`e137502` à `ba261c5`) | lectures IA et analyse arrêtées avant l'effacement d'un document, nouvelles tâches IA refusées pendant l'effacement, écritures du panneau OCR avec la génération attendue, refus de correction OCR publié au lieu d'être perdu, garde réciproque sauvegarde / remplacement Drive, journal altéré refusé sans plantage | tests Python de câblage par point ; `swift test` complet à 628 exécutés, 10 ignorés, 0 échec et `xcodebuild` sans occurrence de « error: » annoncés en `e5cd68f` |
| C3 — panneau et export (`c03494d`, `8365b78`) | C3.1 : la traduction suit le texte de la page, une réponse tardive ne s'affiche pas pour un nouveau texte ; C3.2 : « Cartes de la page » part du texte affiché | test de câblage `tests/test_study_panel_translation.py` (3 cas) |
| T6 — conversion chinoise des lectures (`c4bb22d`) | relevé sur le manuel complet : 68 caractères non japonais restants, 62 paires ajoutées à la table `JapaneseOCRText`, 6 cas écartés faute de cible sûre | un test par paire, texte japonais correct inchangé, boîtes des lignes conservées |
| Lexique E1 — lecture paginée (`c39baa8`) | `DictionaryDatabase.lexiconPage` : pages triées (lecture, forme, entrée), aucune coupure au milieu d'un mot, une ligne par mot, sens absent = `nil`, index imposé `term_reading` / `term_expression` | 8 tests (10 000 entrées sans doublon ni trou, mot à cheval, homographes…) |
| Lexique — termes relevés dans le manuel (`bfb3b79`) | l'outil accepte un `.jsonl` hors dépôt (`--extra`) et ajoute ces termes avec l'étiquette « man », la page et la confiance, en français comme en anglais | 3836 → 4866 entrées, 1030 termes ajoutés par langue ; 107 tests Python réussis |
| T5 E1 — dossiers de l'accueil (`76cd371`) | migration additive `v6-folders` (table `folder`, colonne `document.folderId`, clé étrangère `ON DELETE SET NULL`), API `AppDatabase+Folders` (créer, renommer, supprimer, ranger), appartenance hors de `LibraryDocument`, `folderId` ni exporté ni accepté dans un paquet `.kyokasho` | 7 tests (migration d'une base d'avant v6, cycle complet, espace, invariant d'enregistrement, ordre, paquets, publication) |

**Ce qui manque pour clore ces lots** : la recette iPad de NOxygen59 (aucun essai constaté ici), la revue de Claude
pour ce qui est de niveau R2, et la mise à jour de ce tableau au moment d'une fusion.


## 4. Dépendances et ordre suggéré

1. ~~**Vérifier le lot intégré et faire la recette iPad**~~ : **fait le 27/10** — `main` `242be8f` vérifié (188 Swift, 16 Python, 2 JS, documentation, iOS générique), candidate locale 1.3.2 (42), recette de NOxygen59 validée avec limites.
2. **Retours ouverts du lot** : RET-041 (#60, clignotement en haut à gauche au changement de page) et RET-042 (#61, fiabilité du survol avec Maj) à cadrer avec leurs informations manquantes, puis à prioriser avec le reste du registre ; aucun correctif autorisé par cette ligne.
3. **Données avant refactorisation** : exécuter sur corpus synthétique les recettes DATA-01 (PageShift), DATA-02 (sauvegarde/restauration TrollStore) et DATA-03 (géométrie annotations/export). Aucun essai de restauration sur l'unique bibliothèque réelle.
4. **Performance et énergie** : mesurer PERF-01 et RET-017 avant de proposer une optimisation MLX/Metal. Les procédures ASan/diagnostic restent distinctes des preuves iPad.
5. **Maintenabilité** : une correction ou extraction ciblée par PR, avec test avant/après ; aucune réécriture générale.
6. **Backlog produit** : les 40 retours restent priorisés dans le registre et leurs Issues. Les fonctions, le cloud et la version Mac ne deviennent pas autorisés par leur seule présence.
7. **CI et sécurité** : Actions reste désactivé au titre de CI-0. SEC-01 (visibilité et protection de `main`) demeure une décision du propriétaire.

Une anomalie critique démontrée peut modifier cet ordre, avec justification enregistrée. Les chantiers n'ont pas de pourcentage d'avancement : intégration, tests Mac, compilation iOS et validation iPad restent des axes séparés.

## 5. Registre des validations et limites

- **État GitHub du 27/10, après recette 1.3.2** : `main` `738dceb7fd09ccfcb1b9feb454c1d695d2658d9d` (fusion de #59), avant la fusion de #62. Issues #11 à #15 fermées après confirmation iPad ; #60 et #61 ouvertes.
- **Contrôles du `main` fusionné `242be8f`** (Mac arm64, Xcode 27.1, Swift 6.4) : 188 tests Swift réussis, 0 échec, 7 ignorés ; 16 Python ; 2 JS ; documentation 0 erreur ; compilation iOS générique avec dépendances figées réussie ; `Package.resolved` inchangés.
- **Candidate locale 1.3.2 (42), recette NOxygen59 du 27/10** : Build locale **1.3.2 (42)**, non publiée, source `bfd4312` (= `main` `242be8f` + version/build), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e`. Installation et données OK ; RET-010, RET-011 et RET-012 confirmés ; régressions rapides OK ; résultat général « validée avec limites » ; nouveaux retours RET-041 et RET-042. Aucune release publiée.
- **Build locale 1.3.1 (41), recette NOxygen59 du 27/10** : candidate non publiée, source locale `e3232d5` (`main` `ec51cb8` + version/build), SHA-256 `c5b31ced0e89ee30cac80c0ff55cd3f21e4dcef712469b9a61397e6946bf9016`. Installation/version/données observées OK ; RET-008 et RET-009 confirmés ; RET-011 partiel ; RET-012 précisé vers un stockage par document.
- **Preuves avant fusion** (historique) : assemblage local #31 → #32 → #57 à `aeb8d01` : 188 Swift, 7 ignorés, 16 Python, documentation et iOS générique réussies ; correction finale #57 `68274a1` : 184 Swift, 16 Python, 2 JS, documentation et iOS générique réussies.
- **Suivi produit** : [RETOURS-IPAD.md](RETOURS-IPAD.md) contient RET-001 à RET-042 et la matrice O01–O13 / P01–P10. Les Issues et PR liées portent le détail ; le plan directeur conserve seulement l'état des chantiers.


- **Reprise de la PR #7 après revue (25/10)** : [revue de Claude](https://github.com/NOxygen59/kyokasho/pull/7#issuecomment-6397411518) validée par NOxygen59 ; instructions corrigées contre le code au SHA `f83aec8`. Aucune logique ni configuration changée. Contrôles documentaires locaux consignés en réponse dans la PR ; aucun nouvel essai de sauvegarde, Swift ou iPad.

- **Préparation QA-02 (25/10, base `f83aec8`)** : 16 tests Python synthétiques locaux réussis (0 échec/ignoré), inventaire de 20 tests PageShift et 1 test Swift de restauration vérifié dans les sources ; aucune nouvelle exécution Swift/ASan. Contrôles documentaires et diff consignés dans la PR dédiée. [Recette](RECETTE-IPAD-QA-02.md) et fiches GitHub prêtes ; corpus PDF à fabriquer hors dépôt ; aucun résultat iPad revendiqué.

- **Intégration du 25/10 (GitHub)** — fusions par commit de fusion, branches conservées :
  - PR #1 → `92a0315c2684b83674ee50eaac4cd49a8722aac7` : `Documentation` réussi sur `main`.
  - PR #2 → `a016091323b5850010334f91d7cfa61872619366` : `Documentation` réussi ; `Stockage Mac` relancé manuellement sur `main` (#1+#2) et réussi (run `40152364389`).
  - PR #3 → `c2b1b2978c3722c73b6b90681fa09c5888b4816a` : `Documentation` réussi ; `Sauvegarde synthétique` (run `40152580509`) et `Stockage Mac` (run `40152582505`) relancés sur `main` (#1+#2+#3) et réussis.
- **Résultats rapportés par Codex (25/10, assemblage local)** : 156 tests Swift réussis, 7 ignorés ; 16 Python ; 20 PageShift sous ASan ; compilation générique iOS déclarée réussie, minimum iOS 16. Ces nombres restent des **résultats de rapport**, non revérifiés dans les journaux des runs `main`.
- **Non effectué** : aucun essai sur iPad ; MLX/Metal non qualifiés pour ce lot ; restauration TrollStore non prouvée ; LSan non disponible sur la toolchain employée ; compilation iOS non exécutée en CI ; 7 essais ignorés faute de modèles ONNX/UniDic.
- **Écueils documentés** : un OCR commencé avant changement de pagination peut écrire sur la mauvaise page ; un fichier ordinaire suffixé `-wal` n'est pas forcément une annexe SQLite. Les PR #2/#3 apportent des correctifs et tests dédiés ; ne jamais les réintroduire.
- **Plan CI** : `docs/CI-ROADMAP.md` provient d'un fichier local non suivi de Codex (audit du 25/10 sur `edd09b2`, arbre identique à `c2b1b29`). Sa partie workflows a été revérifiée contre `main` ; ses tarifs, labels de runners, versions Xcode/XcodeGen et sources externes **ne l'ont pas été**.
- **Contrôle documentaire** : `scripts/check_documentation.py` vérifie les liens locaux et, depuis GOV-03, la présence des documents de pilotage et leurs renvois. Sur un push groupant plusieurs commits, `git diff --check HEAD^ HEAD` ne couvre que le dernier (CI-ROADMAP, phase 1). Les en-têtes SPDX des Markdown ne sont pas contrôlés : plusieurs documents historiques n'en ont pas.
- **À ne pas confondre** : le fichier racine `PLAN.md` est le plan historique du produit (V1→V5), pas ce plan directeur.

## 6. Mode opératoire : une tâche du début à la fin

1. **Cadre** : identifiant du chantier, bug/objectif, bénéfice, périmètre, propriétaire de la décision.
2. **Contrat** : invariants, données touchées, contraintes iOS 16 et modèles, tests requis, non-objectifs.
3. **Preuve avant** : test de régression qui échoue pour un bug ; mesures de référence pour une optimisation.
4. **Modification** : branche et PR petites, pas d'évolution silencieuse des dépendances, pas de fusion sans accord.
5. **Vérification** : commandes + SHA + environnement, résultats passés/échoués/ignorés ; test iPad explicitement absent ou réalisé.
6. **Revue** : contrôle indépendant pour données, concurrence, sécurité ou changements de fichiers persistants.
7. **Intégration** : validation du propriétaire, contrôles sur le résultat combiné, plan de retour arrière.
8. **Transmission** : mise à jour de ce tableau, liens PR/Issues, documentation du domaine et prochaine action débloquée.

**Définition de terminé** : implémentation + vérifications exigées + documentation + revue + intégration, *et* validation sur iPad si le critère la demande. Ne jamais clore implicitement une preuve manquante.

## 7. Répertoire documentaire — sans double emploi

- **Ce fichier** : suivi du programme de professionnalisation.
- [INDEX.md](INDEX.md) : navigation dans la documentation.
- [FEUILLE-DE-ROUTE.md](FEUILLE-DE-ROUTE.md) : backlog produit et historique.
- [HISTOIRE-DU-DEVELOPPEMENT.md](HISTOIRE-DU-DEVELOPPEMENT.md) : chronologie et décisions passées.
- [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md) : règles ; [TESTS.md](TESTS.md), [CI-ET-LIVRAISON.md](CI-ET-LIVRAISON.md), [MEMOIRE-ET-SANITIZERS.md](MEMOIRE-ET-SANITIZERS.md), [DONNEES-ET-SAUVEGARDES.md](DONNEES-ET-SAUVEGARDES.md) : procédures.
- [PHASE2-STOCKAGE.md](PHASE2-STOCKAGE.md), [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md), [PHASE2-NETTOYAGE.md](PHASE2-NETTOYAGE.md) : lots de la phase 2.
- [RETOURS-IPAD.md](RETOURS-IPAD.md) : registre des retours d'usage réel (identifiant stable, build, état, Issue, PR, preuve) ; [RECETTE-IPAD-QA-02.md](RECETTE-IPAD-QA-02.md) : scénarios de recette.
- [CI-ROADMAP.md](CI-ROADMAP.md) : plan d'automatisation CI à mettre en œuvre par phases ; [CI-ET-LIVRAISON.md](CI-ET-LIVRAISON.md) décrit l'existant et la livraison.

**Résolution des contradictions** : rapporter les deux sources et leur date, vérifier le code/les runs et demander une décision si nécessaire. Ne pas effacer l'historique ni mettre à jour silencieusement les anciennes notes.

## 8. Point de reprise pour le prochain chat

**État au 10/11/2026 (relevé de cette note, sur le Mac de travail) :**

- Copie de travail sur la branche `agents/docs-verif`, pointe `76cd371`. Le lot T1-T3 / C1-C3 / T6 / Lexique E1 /
  T5 E1 est décrit au § 3 bis : hors `main`, sans fusion ni push constatés, **non testé iPad**. `main` lu localement
  est à `48fff3a` (fusion locale de la PR #88) : les deux têtes divergent, ce n'est pas une fusion.
- Preuve rejouable en une commande : `./scripts/verifier_tout.sh` (tests Swift, tests Python, compilation iOS
  générique, contrôle documentaire ; résumé daté dans `build/verif/RESUME-<date>.md`, sort en erreur si une étape
  échoue). GitHub Actions reste désactivé (CI-0).
- Rôles et méthode : § 0.
- Encore ouvert : recette iPad des lots du § 3 bis, revue de niveau R2, et la décision de NOxygen59 sur une fusion.

**État de référence du 27/10/2026, après la recette 1.3.2 et le lot RET-043 à RET-047 :**

- `main` : `6dac083` après les fusions du 27/10 (#66, #68, #70, #72), avant la fusion de cette clôture (#64) ; relever le SHA courant sur GitHub.
- Registre central : [RETOURS-IPAD.md](RETOURS-IPAD.md), RET-001 à RET-051 ; prochain identifiant libre RET-052. RET-049 (#79, animation du sélecteur de pages, PR #86, fusionnée) et RET-050 (#81, flèches du clavier, PR #85, fusionnée) : confirmés iPad par les recettes 1.3.2 (59) et (60), non publiées. RET-051 (#87, avertissement des brouillons de notes non ajoutés, demande de la recette 1.3.2 (59)) : compilé iOS, PR #88 en brouillon, non testé iPad.
- Lot du 27/10 clos : #66 (RET-044), #68 (RET-043), #70 (RET-046) et #72 (RET-047) fusionnées sur autorisation de NOxygen59 ; `main` = `6dac083`, identique à la candidate locale 1.3.2 (52) (non publiée) hors numéro de version. #63, #65, #69, #71 fermées, confirmées iPad.
- Ouverts : RET-041 (#60), RET-042 (#61) et RET-045 (#67, journal lent, suivi séparément), non résolus. RET-048 (#74) : corrigé et testé sur Mac, ASan réussi, compilé iOS, non testé iPad ; PR #77 fusionnée (`1767ce0`), Issue fermée sur preuve Mac.
- RET-014 (#17, barre de langue fixe et bascule sans rechargement) et RET-007 (#34, un seul défilement vertical dans le panneau Texte) : **confirmés iPad** sur les candidates locales 1.3.2 (53) à (56), non publiées ; PR #78 en attente de la revue de Codex et de l'accord de NOxygen59. Remarque de recette à préciser : la bulle Yomitan semble se rafraîchir à chaque mouvement de souris. #18 et #24 restent ouvertes (critères non démontrés, preuves commentées).
- Tests PageShift (cadrage #73) : PR #75 fusionnée (`8b89b93`) ; S1 à S7 et R1 à R8 sur données synthétiques, dont 182 doubles interruptions ; suite complète `KyokashoKit` 218 tests, 7 ignorés, 0 échec ; aucun code de l'app modifié.
- 03/11/2026, branche locale `claude/rotation-crash-ocr` (non publiée, base candidate 73) : plantage et repères de la rotation, corrections OCR conservées, verrou de sauvegarde (RET-060 à RET-062). Candidate locale 1.3.2 (74) à recetter sur iPad ; RET-063 reste à analyser.
- 07/11/2026, branche locale `claude/ipad-tableau-mesures` (non publiée) : reconstruction de l'OCR des pages PDF (plan `PLAN-RECONSTRUCTION-OCR-PDF-5ec3952`, décisions D1 à D7 de NOxygen59). Étape 1 (`d87e048`) : règle unique `OCRSelectionPolicy`. Étape 1 bis (revue Codex de `d87e048`, R1 à R3) : état versionné `OCRPageSelection`, adoption unique `adoptOCR` dans le lecteur, priorité des corrections (D7) en Auto. Tests Mac et compilation simulateur seulement ; non testé iPad. Étape 2 (08/11) : `store` gardé par la génération des pages, cache plus ancien que l'affichage refusé, file `ensureOCR` et tâche de page posée uniques, double page rafraîchie. Restent : étapes 3 à 5 (réglages, cartes, recherche, document entier, analyse, export).
- Actions désactivé ; aucune release ; dépendances/forks MLX inchangés ; aucune donnée personnelle manipulée.

**Une seule séquence recommandée :** à la reprise des publications (purge de l'historique Git par GitHub Support), décision de NOxygen59 sur la PR DATA-02 (#83, tests et documentation seulement ; revue de Codex favorable après corrections, puis auto-relecture en deux passes de Claude, Codex n'étant plus disponible) ; la restauration réelle sur iPad (niveau B de QA-02) reste bloquée sans accords distincts. Une seule Issue et une seule PR à la fois ; aucune manipulation de la bibliothèque personnelle.

**Question standard de reprise :** « Lis `AGENTS.md`, `docs/PLAN-DIRECTEUR.md` et `docs/RETOURS-IPAD.md`, compare avec GitHub actuellement, puis indique l'état vérifié, les blocages et une seule prochaine action ; ne fusionne ni ne publie sans mon accord. »

### Historique condensé du 26 octobre

La campagne QA02 1.3 build 40 a produit les lots diagnostics, OCR/dictionnaire et panneau OCR, ensuite fusionnés par les PR [#8](https://github.com/NOxygen59/kyokasho/pull/8), [#9](https://github.com/NOxygen59/kyokasho/pull/9) et [#10](https://github.com/NOxygen59/kyokasho/pull/10). Les constats, corrections, limites et recettes restent dans [QA02-CORRECTIONS-DIAGNOSTICS.md](QA02-CORRECTIONS-DIAGNOSTICS.md), [QA02-CORRECTIONS-OCR-DICTIONNAIRE.md](QA02-CORRECTIONS-OCR-DICTIONNAIRE.md) et [QA02-CORRECTIONS-PANNEAU.md](QA02-CORRECTIONS-PANNEAU.md). O07 et le retard de défilement n'y étaient qu'instrumentés ; ne pas les déclarer résolus sans preuve ultérieure.

### Historique conservé du 25 octobre


**Dernier fait vérifié ici (25/10) :** PR #1 à #5 fusionnées (`92a0315`, `a016091`, `c2b1b29`, `ee07c55`, `f76d9f6`), PR #6 (GOV-04) fusionnée sur autorisation de NOxygen59, commit `f83aec8c61d88f1e6c119376590899c9c1ce2876` vérifié lors de QA-02. Les derniers contrôles GitHub réussis datent d'avant la désactivation. **GitHub Actions est désactivé** (CI-0) : les preuves se font désormais en local et se documentent dans les PR. Aucune Issue. Dépôt public, `main` non protégée. Aucune build, aucun essai iPad, aucune release depuis v1.3.

**Validations encore ouvertes (aucune effectuée) :** recette iPad de DATA-01 (ajout de pages, OCR concurrent, annotations, gros PDF) et de DATA-02 (extraction/restauration TrollStore) ; MLX/Metal sur iPad pour ce lot ; DATA-03 (géométrie des annotations) ; LSan et campagne mémoire (PERF-01).

**Décisions du propriétaire encore ouvertes :**

- **Réactivation éventuelle de GitHub Actions** (désactivé, CI-0 fait le 25/10/2026) : uniquement après un constat écrit de NOxygen59 (aucun moyen de paiement, ou budget Actions à 0 $ avec « *Stop usage when budget limit is reached* ») et une autorisation par workflow. Une simple alerte de budget ou une rétention courte ne suffisent pas.
- Visibilité du dépôt et protection de `main` (SEC-01).
- Réglages Actions de sécurité à appliquer avant toute réactivation : épinglage SHA obligatoire, approbation de tous les contributeurs externes.
- Autorisation d'une build de test et de son installation pour la recette iPad. Le niveau A sur l'installation existante avec risque de perte accepté est déjà décidé par NOxygen59 ; appliquer les précautions A0. Aucun changement de version/build sans nouvel accord ; identification externe par SHA source et SHA-256 du `.tipa`.
- Qualification de la méthode d'extraction/réimport TrollStore sur conteneur jetable ; autorisations distinctes pour B1 puis B2. La copie Mac n'est pas une assurance de récupération iPad.
- Création éventuelle des étiquettes GitHub `agent:claude`, `agent:codex`, `revue-croisée`.

**Prochaine priorité :** relire/fusionner la PR documentaire QA-02 seulement sur accord. La [recette](RECETTE-IPAD-QA-02.md) est préparée ; les essais restent **non effectués**. La revue de Claude a été validée par NOxygen59 : corrections documentaires sur la même branche, niveau A admis sur l'installation existante avec acceptation du risque de perte et PDF synthétiques préfixés QA02-. Après autorisation de build/installation et précautions A0, NOxygen59 remplit A0–A5 ; B1/B2 restent bloqués jusqu'à qualification séparée d'un conteneur synthétique et accords explicites. Ne pas assimiler l'installation existante à un conteneur sans données personnelles. Aucun travail CI, aucune release ni accès à la bibliothèque personnelle ne découle de cette préparation. Les lignes DATA-01, DATA-02, DATA-03 et PERF-01 restent ouvertes pour leurs preuves appareil.

**Question standard de reprise :** « Lis `AGENTS.md` et `docs/PLAN-DIRECTEUR.md` dans `NOxygen59/kyokasho`, compare avec GitHub actuellement, puis indique en français l'état vérifié, les blocages et une seule prochaine action ; ne code ni ne fusionne sans ma demande. »

**Mise à jour à chaque PR de professionnalisation** : modifier les lignes pertinentes, associer des liens permanents vers les preuves et renouveler ce point de reprise. Ne pas transformer une intention, une checklist cochée ou un rapport IA en preuve iPad.
