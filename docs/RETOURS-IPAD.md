<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Registre des retours iPad

Ce registre suit chaque retour de NOxygen59 en usage réel, du signalement à la confirmation sur l'iPad. Il ne remplace ni les Issues (discussion, informations manquantes), ni les PR (code, preuves), ni la [recette QA-02](RECETTE-IPAD-QA-02.md) (scénarios). Il relie les trois.

## Règles

- **Source de vérité** : depuis le 27/10/2026, ce registre et les Issues GitHub font foi pour l'état des retours. Les documents de feedback locaux (dont celui du 26/10) restent des sources historiques ; on ne les met plus à jour.
- **Identifiant stable** `RET-NNN`. Il ne change jamais et ne se réutilise pas, même pour un retour abandonné. Les identifiants de la série du 26/10 donnés par Codex (`O01`, `P04`…) sont conservés comme alias.
- **Une ligne par retour.** Le détail (mots de NOxygen59, questions, discussion) vit dans l'Issue.
- **État** : une seule valeur, la plus avancée réellement prouvée :

  | État | Signifie | Preuve exigée |
  |---|---|---|
  | rapporté | NOxygen59 l'a signalé | Issue ou référence au retour |
  | reproduit | reproduit sur un corpus synthétique (Mac, simulateur ou iPad) | scénario écrit dans l'Issue |
  | corrigé sur Mac | correctif dans une PR, tests Mac réussis | PR + fiche de preuve locale |
  | compilé iOS | compilation `generic/platform=iOS`, cible 16.0, réussie au SHA de la PR | fiche de preuve locale (SHA) |
  | à tester iPad | build de test contenant le correctif fournie à NOxygen59 | SHA de la build + SHA-256 du `.tipa` |
  | confirmé iPad | NOxygen59 a vérifié sur l'iPad | commentaire daté de NOxygen59, build et scénario |

  « Compilé iOS » ne veut pas dire « fonctionne sur iPad ». Une PR non fusionnée reste un correctif candidat.
- **Build observée** : la version affichée ne suffit pas, car les builds QA02 affichent « 1.3 (40) » comme v1.3. Noter le SHA source quand il est connu, sinon « à confirmer ».
- **Aucune donnée personnelle** : pas de journal brut, de PDF, de capture d'un livre personnel, de chemin, ni d'identifiant d'appareil. Les preuves sont des liens vers une PR, un commentaire ou une fiche de preuve locale.
- Mettre à jour la ligne dans la même PR que le changement d'état. Un agent ne coche jamais « confirmé iPad » à la place de NOxygen59.

## Appareil de référence

iPad Pro 12,9" M1 (8 Go), iOS 16.6.1, TrollStore. Toute autre configuration (souris, trackpad, clavier, Pencil) se note dans l'Issue.

## Série du 26/10/2026 — feedback QA02 traité par Codex

Source : document de feedback de NOxygen59, non versionné, résumé dans les PR #8 à #10. Build observée : QA02 « 1.3 (40) », source `431f1c6` (d'après les PR).

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-001 | O10 | 2026-10-26 | Bug | Journal de diagnostic vide à l'ouverture et non actualisé | QA02 1.3 (40), `431f1c6` | à tester iPad | — | [#8](https://github.com/NOxygen59/kyokasho/pull/8) (fusionnée 27/10) | PR #8 (tests Mac, iOS générique) ; [revue](https://github.com/NOxygen59/kyokasho/pull/8#issuecomment-6432038430) |
| RET-002 | P04 | 2026-10-26 | Ergonomie | Pas d'accès au journal depuis les pastilles IA | QA02 1.3 (40), `431f1c6` | à tester iPad | — | [#8](https://github.com/NOxygen59/kyokasho/pull/8) (fusionnée 27/10) | idem |
| RET-003 | O03 | 2026-10-26 | Bug | Corrections OCR de l'analyse non reflétées dans le lecteur ouvert ; « Garder tel quel » ne conservait pas l'acceptation | QA02 1.3 (40), `431f1c6` | à tester iPad | — | [#9](https://github.com/NOxygen59/kyokasho/pull/9) (fusionnée 27/10) | PR #9 ; [revue](https://github.com/NOxygen59/kyokasho/pull/9#issuecomment-6432038769), réserve levée après correction (`b1ced37`) |
| RET-004 | O07 | 2026-10-26 | Bug | Survol du dictionnaire qui cesse durablement de répondre | QA02 1.3 (40), `431f1c6` | rapporté (instrumenté, cause inconnue) | [#36](https://github.com/NOxygen59/kyokasho/issues/36) | [#9](https://github.com/NOxygen59/kyokasho/pull/9) (fusionnée 27/10) | traces `lookup` seulement |
| RET-005 | O02 | 2026-10-26 | Bug | Miniatures : indice, sans lien démontré | QA02 1.3 (40), `431f1c6` | rapporté | [#35](https://github.com/NOxygen59/kyokasho/issues/35) | — | — |
| RET-006 | O05 | 2026-10-26 | Bug | Gestes du panneau flottant : saut au relâchement, zone morte après rotation | QA02 1.3 (40), `431f1c6` | à tester iPad | — | [#10](https://github.com/NOxygen59/kyokasho/pull/10) (fusionnée 27/10) | PR #10 ; [revue](https://github.com/NOxygen59/kyokasho/pull/10#issuecomment-6432039059) |
| RET-007 | O01 | 2026-10-26 | Bug | Retard de défilement dans la fenêtre OCR | QA02 1.3 (40), `431f1c6` | rapporté (instrumenté, cause inconnue) | [#34](https://github.com/NOxygen59/kyokasho/issues/34) | [#10](https://github.com/NOxygen59/kyokasho/pull/10) (fusionnée 27/10) | traces `ocr-scroll` seulement |

RET-001, 002, 003 et 006 sont « à tester iPad » : leurs correctifs sont dans la build de test 1.3.1 (41) remise à NOxygen59 le 27/10 (voir plus bas), mais la recette de ce jour ne les a pas couverts. RET-002 ne couvre que l'accès au journal depuis les pastilles ; le reste de P04 est RET-032.

Les états « compilé iOS » reposaient sur la validation combinée locale de Codex : `ecde650` = #8 + #9 + #10, journal `BUILD SUCCEEDED` du 26/10 20:19, sans SHA inscrit dans le journal. Les autres identifiants `O…` du document source, s'il y en a, restent à reporter ici.

## Série du 27/10/2026 — usage réel en cours

Source : message de NOxygen59 du 27/10/2026. Build observée : QA02 « 1.3 (40) » installée le 26/10, source supposée `431f1c6`, **à confirmer**. Priorité du lot : 1 brouillon de note, 2 premier clic Yomitan, 3 boule flottante et modes persistants, 4 énergie, 5 le reste.

| ID | Prio | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-008 | 1 | 2026-10-27 | Bug | Brouillon de note perdu en quittant la saisie | 1.3.1 (41) locale, `e3232d5` | confirmé iPad | [#11](https://github.com/NOxygen59/kyokasho/issues/11) (fermée) | [#27](https://github.com/NOxygen59/kyokasho/pull/27) | tests Mac (165 réussis) + iOS générique, `cfdfa0e` ; recette NOxygen59 27/10 OK |
| RET-009 | 2 | 2026-10-27 | Bug | Carte Yomitan (fenêtre OCR) vide au premier clic, OK au second | 1.3.1 (41) locale, `e3232d5` | confirmé iPad | [#12](https://github.com/NOxygen59/kyokasho/issues/12) (fermée) | [#28](https://github.com/NOxygen59/kyokasho/pull/28) | iOS générique, `3fa37fc` ; recette NOxygen59 27/10 OK |
| RET-010 | 2 | 2026-10-27 | Ergonomie | Carte Yomitan trop envahissante : NOxygen59 veut une fenêtre de contexte, pas une feuille plein écran (précisé à la recette 1.3.1) | 1.3.2 (42) locale, `bfd4312` | confirmé iPad | [#13](https://github.com/NOxygen59/kyokasho/issues/13) (fermée) | [#57](https://github.com/NOxygen59/kyokasho/pull/57) (fusionnée) | tests Mac/JS + iOS générique, `68274a1` ; non essayé sur iPad ; recette NOxygen59 1.3.2 OK (tous les points) |
| RET-011 | 3 | 2026-10-27 | Bug | La « boule » (palette d'outils PencilKit) disparaît en touchant la page ; gomme et annulation inaccessibles | 1.3.2 (42) locale, `bfd4312` | confirmé iPad | [#14](https://github.com/NOxygen59/kyokasho/issues/14) (fermée) | [#29](https://github.com/NOxygen59/kyokasho/pull/29) (fusionnée), [#31](https://github.com/NOxygen59/kyokasho/pull/31) (fusionnée) | recette 1.3.1 partielle ; complément #31 compilé iOS `010bc8c`, non essayé sur iPad ; recette NOxygen59 1.3.2 OK |
| RET-012 | 3 | 2026-10-27 | Ergonomie | Modes d'un document perdus à chaque fermeture | 1.3.2 (42) locale, `bfd4312` | confirmé iPad | [#15](https://github.com/NOxygen59/kyokasho/issues/15) (fermée) | [#30](https://github.com/NOxygen59/kyokasho/pull/30) (fusionnée), [#32](https://github.com/NOxygen59/kyokasho/pull/32) (fusionnée) | recette 1.3.1 : modes globaux fonctionnels ; stockage par document testé Mac + iOS `b7d79eb`, non essayé sur iPad ; recette NOxygen59 1.3.2 OK |
| RET-013 | 5 | 2026-10-27 | Fonction | Onglets de documents en haut de l'écran | — | rapporté | [#16](https://github.com/NOxygen59/kyokasho/issues/16) | — | — |
| RET-014 | 5 | 2026-10-27 | Ergonomie | Choix de langue inaccessible après défilement | à confirmer | rapporté | [#17](https://github.com/NOxygen59/kyokasho/issues/17) | — | — |
| RET-015 | 5 | 2026-10-27 | Fonction | Changer de page avec les flèches du clavier | — | rapporté | [#18](https://github.com/NOxygen59/kyokasho/issues/18) | — | — |
| RET-016 | 5 | 2026-10-27 | Ergonomie | Boutons de page plus discrets | à confirmer | rapporté | [#19](https://github.com/NOxygen59/kyokasho/issues/19) | — | — |
| RET-017 | 4 | 2026-10-27 | Bug (énergie) | 60 % de batterie en 1 h 30 avec l'IA locale | à confirmer | rapporté | [#20](https://github.com/NOxygen59/kyokasho/issues/20) | — | — |
| RET-018 | 4 | 2026-10-27 | Fonction | Avertissement sur la consommation de l'IA locale à l'accueil | — | rapporté | [#21](https://github.com/NOxygen59/kyokasho/issues/21) | — | — |
| RET-019 | 5 | 2026-10-27 | Fonction | Date et heure des notes, groupées par jour | — | rapporté | [#22](https://github.com/NOxygen59/kyokasho/issues/22) | — | — |
| RET-020 | 5 | 2026-10-26 | Fonction | Surligner directement les zones OCR détectées (accès facile, portable sur Mac) | — | rapporté | [#23](https://github.com/NOxygen59/kyokasho/issues/23) | — | — |
| RET-021 | 5 | 2026-10-26 | Fonction | Survol Yomitan seulement pendant l'appui sur Maj | — | rapporté | [#24](https://github.com/NOxygen59/kyokasho/issues/24) | — | — |

### Recette du 27/10/2026 — build de test 1.3.1 (41)

Build **non publiée**, construite depuis le commit local `e3232d5` (= `main` `ec51cb8` + passage à 1.3.1 / build 41), `.tipa` SHA-256 `c5b31ced0e89ee30cac80c0ff55cd3f21e4dcef712469b9a61397e6946bf9016`, iPad Pro M1, iOS 16.6.1. Résultats de NOxygen59 : 0 (installation, version, données) OK ; RET-008 OK ; RET-009 OK ; RET-011 partiel ; RET-012 fonctionne mais à rendre propre à chaque document.

## Série du 26/10/2026 — compléments (document source transmis le 27/10)

Le document de feedback complet du 26/10 (13 observations O01–O13, 10 propositions P01–P10, une note sur le Mac) a été transmis par NOxygen59 le 27/10 avec le triage de Codex. Le texte de NOxygen59 fait foi ; les hypothèses du triage ne sont pas des faits. Les éléments absents du registre ont été ajoutés ci-dessous, chacun avec une Issue. La suppression de pages, le cloud et le Mac restent des **chantiers de conception, sans implémentation** (décision de NOxygen59 du 27/10).

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-022 | O04 | 2026-10-26 | Fonction (IA) | Le chat ne sait pas résumer une page | QA02 1.3 (40), `431f1c6` | rapporté | [#37](https://github.com/NOxygen59/kyokasho/issues/37) | — | — |
| RET-023 | O06 | 2026-10-26 | Ergonomie | Boutons de la fenêtre OCR redondants (quatre états à clarifier) | QA02 1.3 (40), `431f1c6` | rapporté | [#38](https://github.com/NOxygen59/kyokasho/issues/38) | — | — |
| RET-024 | O08 | 2026-10-26 | Ergonomie | Choix du moteur OCR peu clair, Apple Vision d'office | QA02 1.3 (40), `431f1c6` | rapporté | [#39](https://github.com/NOxygen59/kyokasho/issues/39) | — | — |
| RET-025 | O09 | 2026-10-26 | Ergonomie | Moniteur de performances trop long | QA02 1.3 (40), `431f1c6` | rapporté | [#40](https://github.com/NOxygen59/kyokasho/issues/40) | — | — |
| RET-026 | O11 | 2026-10-26 | Ergonomie | Analyse : choix visible, annulation, critères, relance paramétrable | QA02 1.3 (40), `431f1c6` | rapporté | [#41](https://github.com/NOxygen59/kyokasho/issues/41) | — | — |
| RET-027 | O12 | 2026-10-26 | Ergonomie | Rendu expérimental de « couverture » à retirer | QA02 1.3 (40), `431f1c6` | rapporté | [#42](https://github.com/NOxygen59/kyokasho/issues/42) | — | — |
| RET-028 | O13 | 2026-10-26 | Bug (texte) | Aide des signets : étoile au lieu de marque-page | QA02 1.3 (40), `431f1c6` | rapporté | [#43](https://github.com/NOxygen59/kyokasho/issues/43) | — | — |
| RET-029 | P01 | 2026-10-26 | Conception | Fenêtres natives ou personnalisées | QA02 1.3 (40), `431f1c6` | rapporté | [#44](https://github.com/NOxygen59/kyokasho/issues/44) | — | — |
| RET-030 | P02 | 2026-10-26 | Fonction (IA) | Paramètres IA avancés, consignes, formules | QA02 1.3 (40), `431f1c6` | rapporté | [#45](https://github.com/NOxygen59/kyokasho/issues/45) | — | — |
| RET-031 | P03 | 2026-10-26 | Documentation | Chaîne OCR → zones → furigana → affichage | QA02 1.3 (40), `431f1c6` | rapporté | [#46](https://github.com/NOxygen59/kyokasho/issues/46) | — | — |
| RET-032 | P04 | 2026-10-26 | Fonction | Moniteur intégré partout, pastilles IA animées | QA02 1.3 (40), `431f1c6` | rapporté | [#47](https://github.com/NOxygen59/kyokasho/issues/47) | — | — |
| RET-033 | P05 | 2026-10-26 | Fonction | Historique des ajouts de pages | QA02 1.3 (40), `431f1c6` | rapporté | [#48](https://github.com/NOxygen59/kyokasho/issues/48) | — | — |
| RET-034 | P05 | 2026-10-26 | Conception (données) | Suppression de pages | QA02 1.3 (40), `431f1c6` | rapporté | [#49](https://github.com/NOxygen59/kyokasho/issues/49) | — | — |
| RET-035 | P06 | 2026-10-26 | Fonction | Dictionnaires téléchargeables, lexique design d'intérieur | QA02 1.3 (40), `431f1c6` | rapporté | [#50](https://github.com/NOxygen59/kyokasho/issues/50) | — | — |
| RET-036 | P07 | 2026-10-26 | Conception (données) | Sauvegarde cloud, restauration, import OCR | QA02 1.3 (40), `431f1c6` | rapporté | [#51](https://github.com/NOxygen59/kyokasho/issues/51) | — | — |
| RET-037 | P08 | 2026-10-26 | Fonction | Temps passé à la place de la progression | QA02 1.3 (40), `431f1c6` | rapporté | [#52](https://github.com/NOxygen59/kyokasho/issues/52) | — | — |
| RET-038 | P09 | 2026-10-26 | Design | Nouvelle icône | QA02 1.3 (40), `431f1c6` | rapporté | [#53](https://github.com/NOxygen59/kyokasho/issues/53) | — | — |
| RET-039 | P10 | 2026-10-26 | Fonction | Catégorie livre / manuel | QA02 1.3 (40), `431f1c6` | rapporté | [#54](https://github.com/NOxygen59/kyokasho/issues/54) | — | — |
| RET-040 | Pensées | 2026-10-26 | Conception | Version Mac (PORT-01) | QA02 1.3 (40), `431f1c6` | rapporté | [#55](https://github.com/NOxygen59/kyokasho/issues/55) | — | — |

### Correspondance complète O/P → registre

| Origine | RET | Issue | PR | Remarque |
|---|---|---|---|---|
| O01 | RET-007 | [#34](https://github.com/NOxygen59/kyokasho/issues/34) | [#10](https://github.com/NOxygen59/kyokasho/pull/10) (instrumentation) | cause inconnue |
| O02 | RET-005 | [#35](https://github.com/NOxygen59/kyokasho/issues/35) | — | indice, à préciser |
| O03 | RET-003 | — | [#9](https://github.com/NOxygen59/kyokasho/pull/9) | à tester iPad (1.3.1) |
| O04 | RET-022 | [#37](https://github.com/NOxygen59/kyokasho/issues/37) | — |  |
| O05 | RET-006 | — | [#10](https://github.com/NOxygen59/kyokasho/pull/10) | à tester iPad (1.3.1) |
| O06 | RET-023 | [#38](https://github.com/NOxygen59/kyokasho/issues/38) | — |  |
| O07 | RET-004 | [#36](https://github.com/NOxygen59/kyokasho/issues/36) | [#9](https://github.com/NOxygen59/kyokasho/pull/9) (instrumentation) | cause inconnue |
| O08 | RET-024 | [#39](https://github.com/NOxygen59/kyokasho/issues/39) | — |  |
| O09 | RET-025 | [#40](https://github.com/NOxygen59/kyokasho/issues/40) | — |  |
| O10 | RET-001 | — | [#8](https://github.com/NOxygen59/kyokasho/pull/8) | à tester iPad (1.3.1) |
| O11 | RET-026 | [#41](https://github.com/NOxygen59/kyokasho/issues/41) | — |  |
| O12 | RET-027 | [#42](https://github.com/NOxygen59/kyokasho/issues/42) | — |  |
| O13 | RET-028 | [#43](https://github.com/NOxygen59/kyokasho/issues/43) | — | petit correctif de texte |
| P01 | RET-029 | [#44](https://github.com/NOxygen59/kyokasho/issues/44) | — | conception |
| P02 | RET-030 | [#45](https://github.com/NOxygen59/kyokasho/issues/45) | — | lié à RET-022 |
| P03 | RET-031 | [#46](https://github.com/NOxygen59/kyokasho/issues/46) | — | documentation |
| P04 | RET-002 + RET-032 | [#47](https://github.com/NOxygen59/kyokasho/issues/47) | [#8](https://github.com/NOxygen59/kyokasho/pull/8) (accès au journal) | RET-002 à tester iPad ; le reste dans RET-032 |
| P05 | RET-033 + RET-034 | [#48](https://github.com/NOxygen59/kyokasho/issues/48), [#49](https://github.com/NOxygen59/kyokasho/issues/49) | — | suppression : conception seulement |
| P06 | RET-035 | [#50](https://github.com/NOxygen59/kyokasho/issues/50) | — | licences à vérifier |
| P07 | RET-036 | [#51](https://github.com/NOxygen59/kyokasho/issues/51) | — | conception seulement |
| P08 | RET-037 | [#52](https://github.com/NOxygen59/kyokasho/issues/52) | — |  |
| P09 | RET-038 | [#53](https://github.com/NOxygen59/kyokasho/issues/53) | — |  |
| P10 | RET-039 | [#54](https://github.com/NOxygen59/kyokasho/issues/54) | — |  |
| Note Mac | RET-040 | [#55](https://github.com/NOxygen59/kyokasho/issues/55) | — | conception seulement ; chantier PORT-01 |

### Recette du 27/10/2026 — candidate locale 1.3.2 (42)

Build **non publiée**, construite depuis le commit local `bfd4312` (= `main` `242be8f` + passage à 1.3.2 / build 42), `.tipa` SHA-256 `8276afe1fe819acdc423a76241016115eaa111987c96f01c565a0385885f8f6e`, iPad Pro M1, iOS 16.6.1, TrollStore ; doigt, Pencil, souris et clavier. Résultat général de NOxygen59 : **validée avec limites**.

- Installation et données : OK (version 1.3.2, démarrage, documents, notes, annotations, repères et cartes conservés, rien de dupliqué).
- RET-011 (palette Pencil) et RET-012 (modes par document) : **OK**, Issues #14 et #15 fermées.
- RET-010 (bulle Yomitan) : **OK** sur tous les points, y compris « changer de page avec la bulle ouverte » (précisé ensuite par NOxygen59) ; Issue #13 fermée.
- Régressions rapides : OK (RET-008 brouillon, RET-009 premier toucher, défilement, annotations, OCR, aucune anomalie évidente).
- Nouveaux problèmes : RET-041 et RET-042 ci-dessous, **ouverts et non résolus**.
- **Aucune release publiée** : la candidate n'existe que sur le Mac de NOxygen59 ; `main` reste en 1.3 (40).

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-041 | — | 2026-10-27 | Bug (affichage) | La pastille « Apple Vision », lorsqu'elle est sélectionnée, semble recharger son libellé à chaque changement de page : elle se redimensionne pendant une fraction de seconde puis reprend sa taille (cause à confirmer) | 1.3.2 (42) locale, `bfd4312` | rapporté, symptôme précisé | [#60](https://github.com/NOxygen59/kyokasho/issues/60) | — | observation iPad de NOxygen59 ; reproduction ciblée encore nécessaire |
| RET-042 | — | 2026-10-27 | Ergonomie | Survol avec Maj peu fiable quand le curseur bouge vite ; s'inspirer de Yomitan (GPL-3.0, licence à respecter) | 1.3.2 (42) locale, `bfd4312` | rapporté | [#61](https://github.com/NOxygen59/kyokasho/issues/61) | — | — |

### Retours du 27/10/2026 — après la recette 1.3.2 (lot clos par les fusions #66, #68, #70, #72)

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-043 | — | 2026-10-27 | Bug (navigation) | Pincement difficile et déplacement bloqué sur un axe en double page (mode lecture) ; cause mesurée : verrou de direction et pan à deux doigts du `PDFScrollView` de PDFKit | 1.3.2 (50) locale, `d1480fe` | confirmé iPad | [#63](https://github.com/NOxygen59/kyokasho/issues/63) (fermée) | [#68](https://github.com/NOxygen59/kyokasho/pull/68) (fusionnée) | candidates de diagnostic 2a à 2g (journaux iPad) ; 2d + 2g validées par NOxygen59 ; correctif `c7d20c8` compilé iOS ; recette 1.3.2 (50) : double page OK, page simple et mode écriture inchangés |
| RET-044 | — | 2026-10-27 | Bug (affichage) | La fiabilité de l'analyse du document affiche toujours 0,0 % ; cause démontrée (entier formaté avec %.1f) | 1.3.2 (50) locale, `d1480fe` | confirmé iPad | [#65](https://github.com/NOxygen59/kyokasho/issues/65) (fermée) | [#66](https://github.com/NOxygen59/kyokasho/pull/66) (fusionnée) | 3 tests + suite Swift 191 réussis, iOS générique ; recette NOxygen59 1.3.2 (50) OK |
| RET-045 | — | 2026-10-27 | Bug (performance) | « Voir le journal » met plus de 30 s à s'ouvrir quand le journal est long | 1.3.2 (47), diagnostic local | rapporté | [#67](https://github.com/NOxygen59/kyokasho/issues/67) | — | — |
| RET-046 | — | 2026-10-27 | Ergonomie (animation) | Fermeture brusque de la fenêtre OCR intégrée ; cause établie : choix volontaire du 23/10 (`5efd2ca`, `.animation(nil, value: side)`), remplacé par une animation en deux temps sans redimensionner PDFKit à chaque image | 1.3.2 (51) locale, `d751205` | confirmé iPad | [#69](https://github.com/NOxygen59/kyokasho/issues/69) (fermée) | [#70](https://github.com/NOxygen59/kyokasho/pull/70) (fusionnée) | revue croisée Codex favorable ; recette NOxygen59 1.3.2 (51) : 9 tests OK |
| RET-047 | — | 2026-10-27 | Ergonomie | Bulle Yomitan de la fenêtre OCR : sources trop grosses, définitions sous le pli ; mode compact (mot, FR, définitions ; accents, fréquences, IPA, dictionnaires et étiquettes masqués) | 1.3.2 (52) locale, `91d4898` | confirmé iPad | [#71](https://github.com/NOxygen59/kyokasho/issues/71) (fermée) | [#72](https://github.com/NOxygen59/kyokasho/pull/72) (fusionnée) | 3 tests `CompactBubbleTests` ; recette NOxygen59 1.3.2 (52) : « c'est bon nickel » |

`main` après le lot : `6dac083`, identique à la candidate 1.3.2 (52) hors numéro de version (`project.yml`).

### Défaut trouvé par les tests PageShift du 27/10/2026 (cadrage #73, PR #75)

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-048 | — | 2026-10-27 | Bug (données, PageShift) | Un rapport d'analyse dont une page est hors du document est décalé sans contrôle ; l'ajout de pages devrait s'arrêter comme pour les brouillons et les lectures IA | `main` `8b89b93`, tests Mac | compilé iOS | [#74](https://github.com/NOxygen59/kyokasho/issues/74) | [#77](https://github.com/NOxygen59/kyokasho/pull/77) (tests : [#75](https://github.com/NOxygen59/kyokasho/pull/75), fusionnée) | garde de plage `116431e` ; `testS7…` démarqué (pages 7, 2, −1), échoue sans la garde ; 39 PageShift + ASan + 218 KyokashoKit verts ; build iOS générique réussie ; pas d'essai iPad |

### Proposition du 28/10/2026 — animation du sélecteur de pages

| ID | Alias | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-049 | — | 2026-10-28 | Ergonomie (animation) | Animer l’apparition et la disparition de la vue de sélection des pages, qui apparaît actuellement sans transition ; préserver la page, le défilement des miniatures et la stabilité du PDF, avec Réduire les animations et iOS 16.6.1 | — | proposé, à cadrer | [#79](https://github.com/NOxygen59/kyokasho/issues/79) | — | retour direct de NOxygen59 ; aucun code ni essai |

Prochain identifiant libre : **RET-050**.
