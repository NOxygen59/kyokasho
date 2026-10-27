<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Audit de reprise — v1.3

## Périmètre et méthode

Audit du 25 octobre 2026 sur `16d2dd89e4cb811b0bc956ef2a225431ed83864a` : mêmes sources applicatives que le tag v1.3, plus l'histoire du développement. La branche `main` distante a été comparée par SHA à la copie locale. Lecture des manifestes, du projet XcodeGen, du script de paquetage, des tests, de la documentation et de chemins sensibles : `PageShift`, `DocumentAITextStore`, `DocumentKnowledge`, interface MeCab. Il s'agit d'un audit ciblé, pas d'une revue exhaustive de chaque ligne ni d'un audit de sécurité complet.

Le fichier joint `HISTOIRE-DU-DEVELOPPEMENT.md` a été lu et recoupé avec sa version déjà présente dans le dépôt. Ses annonces de tests et releases restent des preuves historiques attribuées à leurs sources. Aucun simulateur, iPad, téléchargement de modèle ou nouvelle release n'est nécessaire à ce lot documentaire.

## État réel à préserver

| Domaine | Preuve disponible avant cet audit | Limite |
|---|---|---|
| v1.3, build 40 | `project.yml`, note de release et historique : paquet compilé sur Mac | Les changements v1.3 ne sont pas confirmés sur iPad dans les sources consultées |
| OvisOCR2, Qwen3-VL, analyse et vérification | Retour iPad rapporté dans `IA-LOCALE.md` et feuille de route | Ne valide pas toutes les combinaisons des versions suivantes |
| Gestes 0.8.9.2 | Retour utilisateur positif après annulation du zoom fluide | Trackpad et changements ultérieurs à revérifier |
| Réglages et panneau v1.1.1 | Confirmation utilisateur dans la passation | Ne confirme pas automatiquement les transitions et correctifs suivants |
| Qwen3.5-4B | Intégration et compilation iOS 16 rapportées | Chargement, qualité et mémoire iPad non mesurés |
| Export et ajout de pages | Code livré ; tests de décalage des bases présents | Pas de recette complète iPad ; retour intermittent d'ajout de pages sans cause démontrée |
| OCR japonais v1.3 | Correction ciblée `图` → `図`, langue par document et source IA partagée | Exactitude des scans, vertical et formules non garantie |

Une case cochée de la feuille de route signifie souvent « codé ». Ne pas la convertir en validation iPad. Une mesure Mac Metal 3.0 ne reproduit pas le compilateur Metal embarqué dans iOS 16.

## Constats et priorités

| Priorité | Constat étayé | Action recommandée et preuve de clôture |
|---|---|---|
| P0 — décision | `gh repo view` renvoie `isPrivate: false` le 25/10 ; README, AGENTS et histoire parlent de dépôt privé | Faire décider la visibilité par l’utilisateur ; inventorier les artefacts effectivement accessibles. Ne pas changer les permissions automatiquement. Aucun secret exposé n'est affirmé par cet audit |
| P1 — données | `App/Library/PageShift.swift` journalise plusieurs étapes, mais `try? save` peut masquer un échec de journal ; étape `cards` effacée à la reprise pour éviter un double décalage | Tests d'interruption et d'erreur disque avant modification. Vérifier correspondance PDF/base/rapports/Markdown/cartes à chaque étape |
| P1 — données | Le journal marque `report` avant `shiftReport` ; la reprise à `report` poursuit vers les fichiers | Une interruption dans cette fenêtre peut laisser le rapport non décalé ; reproduire sur copie puis rendre l'étape idempotente |
| P1 — annotations | La feuille de route signale des coordonnées d'anciennes annotations décalées par l'égalisation, et un export annoté non adapté | Recette avec pages de tailles différentes et notes antérieures ; test des transformations avant refactorisation |
| P1 — validation | Sept cibles de tests KyokashoKit et une cible GLMOCRKit ; pas de cible de tests app/UI dans `project.yml`. Deux références obsolètes `.pages` empêchaient la compilation des tests OCR | Deux références de test corrigées en `.results` dans ce lot ; 135 tests exécutés sans échec, 7 ignorés. Ajouter ensuite les tests aux frontières du stockage et de la coordination |
| P1 — automatisation | Aucun `.github/workflows` versionné au commit audité | Amorcer les contrôles documentaires, puis qualifier un runner Mac avant de déclarer les tests obligatoires |
| P2 — reproductibilité | Deux `Package.resolved` versionnés ; guide IA historique propose `swift package update` | Pour une vérification, conserver les épingles. Réserver les mises à jour à une intervention dédiée et comparer les résolutions |
| P2 — mémoire | `MorphologyKit/MeCab.swift` crée tagger puis lattice dans un même `guard`, et ne détruit que model en cas d'échec | Examiner la propriété du tagger si lattice échoue ; suspicion de fuite sur création partielle, pas une fuite observée. Test avec échec injecté avant correction |
| P2 — diagnostic C++ | `MeCabC` utilise `-w` dans le manifeste | Qualifier les avertissements du code tiers dans un lot séparé ; ne pas retirer tous les réglages à l'aveugle |
| P2 — maintenabilité | `ReaderController.swift` compte 1 022 lignes, en plus de ses extensions | Mesurer couplage et responsabilités ; le nombre de lignes seul ne justifie pas une réécriture |

Les risques PageShift sont des fenêtres déduites du code, pas une cause établie du problème intermittent rapporté par l'utilisateur. Les tests existants de `AppDatabase.shiftPages` et `ReviewStore.shiftSourcePages` ne couvrent pas à eux seuls l'orchestration `App/Library/PageShift.swift`.

## Ce qui est déjà sain

Modules séparés, tests de logique, migrations GRDB nommées, PDF originaux conservés, sorties IA brutes conservées séparément de leur normalisation, modèle MLX exclusif, bornes de génération, diagnostics exportables, épingles et correctifs iOS 16 documentés : la reprise peut s'appuyer sur ces éléments. Il n'est pas nécessaire de repartir de zéro.

## Résultats de cette intervention

Voir le registre de [TESTS.md](TESTS.md) pour les commandes réellement exécutées, échecs d'environnement et tests ignorés. Le lot documentaire ne constitue ni une nouvelle compilation de l'app, ni une certification mémoire, ni une validation iPad. Aucun changement de logique applicative, de dépendance, de schéma ou de numéro de version n'est inclus.

## Questions restant ouvertes

Visibilité souhaitée du dépôt ; preuve de restauration complète des données ; état réel des exports/annotations sur pages égalisées ; comportement de Qwen3.5 sur l'appareil ; mesures de mémoire après répétition et annulation ; couverture du pipeline Chat et des changements de langue. Ces questions deviennent des tâches finies dans [GOUVERNANCE-ET-REPRISE.md](GOUVERNANCE-ET-REPRISE.md).
