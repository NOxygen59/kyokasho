<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Registre des retours iPad

Ce registre suit chaque retour de NOxygen59 en usage réel, du signalement à la confirmation sur l'iPad. Il ne remplace ni les Issues (discussion, informations manquantes), ni les PR (code, preuves), ni la [recette QA-02](RECETTE-IPAD-QA-02.md) (scénarios). Il relie les trois.

## Règles

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
| RET-001 | O10 | 2026-10-26 | Bug | Journal de diagnostic vide à l'ouverture et non actualisé | QA02 1.3 (40), `431f1c6` | compilé iOS | — | [#8](https://github.com/NOxygen59/kyokasho/pull/8) (fusionnée 27/10) | PR #8 (tests Mac, iOS générique) ; [revue](https://github.com/NOxygen59/kyokasho/pull/8#issuecomment-6432038430) |
| RET-002 | P04 | 2026-10-26 | Ergonomie | Pas d'accès au journal depuis les pastilles IA | QA02 1.3 (40), `431f1c6` | compilé iOS | — | [#8](https://github.com/NOxygen59/kyokasho/pull/8) (fusionnée 27/10) | idem |
| RET-003 | O03 | 2026-10-26 | Bug | Corrections OCR de l'analyse non reflétées dans le lecteur ouvert ; « Garder tel quel » ne conservait pas l'acceptation | QA02 1.3 (40), `431f1c6` | compilé iOS | — | [#9](https://github.com/NOxygen59/kyokasho/pull/9) (fusionnée 27/10) | PR #9 ; [revue](https://github.com/NOxygen59/kyokasho/pull/9#issuecomment-6432038769), réserve levée après correction (`b1ced37`) |
| RET-004 | O07 | 2026-10-26 | Bug | Survol du dictionnaire qui cesse durablement de répondre | QA02 1.3 (40), `431f1c6` | rapporté (instrumenté, cause inconnue) | — | [#9](https://github.com/NOxygen59/kyokasho/pull/9) (fusionnée 27/10) | traces `lookup` seulement |
| RET-005 | O02 | 2026-10-26 | Bug | Miniatures : indice, sans lien démontré | QA02 1.3 (40), `431f1c6` | rapporté | — | — | — |
| RET-006 | O05 | 2026-10-26 | Bug | Gestes du panneau flottant : saut au relâchement, zone morte après rotation | QA02 1.3 (40), `431f1c6` | compilé iOS | — | [#10](https://github.com/NOxygen59/kyokasho/pull/10) (fusionnée 27/10) | PR #10 ; [revue](https://github.com/NOxygen59/kyokasho/pull/10#issuecomment-6432039059) |
| RET-007 | O01 | 2026-10-26 | Bug | Retard de défilement dans la fenêtre OCR | QA02 1.3 (40), `431f1c6` | rapporté (instrumenté, cause inconnue) | — | [#10](https://github.com/NOxygen59/kyokasho/pull/10) (fusionnée 27/10) | traces `ocr-scroll` seulement |

Les états « compilé iOS » reposent sur la validation combinée locale de Codex : `ecde650` = #8 + #9 + #10, journal `BUILD SUCCEEDED` du 26/10 20:19, sans SHA inscrit dans le journal. Les autres identifiants `O…` du document source, s'il y en a, restent à reporter ici.

## Série du 27/10/2026 — usage réel en cours

Source : message de NOxygen59 du 27/10/2026. Build observée : QA02 « 1.3 (40) » installée le 26/10, source supposée `431f1c6`, **à confirmer**. Priorité du lot : 1 brouillon de note, 2 premier clic Yomitan, 3 boule flottante et modes persistants, 4 énergie, 5 le reste.

| ID | Prio | Date | Type | Retour (résumé) | Build | État | Issue | PR | Preuve |
|---|---|---|---|---|---|---|---|---|---|
| RET-008 | 1 | 2026-10-27 | Bug | Brouillon de note perdu en quittant la saisie | à confirmer | compilé iOS | [#11](https://github.com/NOxygen59/kyokasho/issues/11) | [#27](https://github.com/NOxygen59/kyokasho/pull/27) | tests Mac (165 réussis) + iOS générique, `cfdfa0e` |
| RET-009 | 2 | 2026-10-27 | Bug | Carte Yomitan (fenêtre OCR) vide au premier clic, OK au second | à confirmer | compilé iOS | [#12](https://github.com/NOxygen59/kyokasho/issues/12) | [#28](https://github.com/NOxygen59/kyokasho/pull/28) | iOS générique, `3fa37fc` |
| RET-010 | 2 | 2026-10-27 | Ergonomie | Carte Yomitan trop envahissante dans la fenêtre OCR | à confirmer | rapporté | [#13](https://github.com/NOxygen59/kyokasho/issues/13) | — | — |
| RET-011 | 3 | 2026-10-27 | Bug | La « boule » (palette d'outils PencilKit) disparaît en touchant la page ; gomme et annulation inaccessibles | à confirmer | compilé iOS | [#14](https://github.com/NOxygen59/kyokasho/issues/14) | [#29](https://github.com/NOxygen59/kyokasho/pull/29) | iOS générique, `e1347e2` |
| RET-012 | 3 | 2026-10-27 | Ergonomie | Modes d'un document perdus à chaque fermeture | à confirmer | compilé iOS | [#15](https://github.com/NOxygen59/kyokasho/issues/15) | [#30](https://github.com/NOxygen59/kyokasho/pull/30) | iOS générique, `4ad1c91` |
| RET-013 | 5 | 2026-10-27 | Fonction | Onglets de documents en haut de l'écran | — | rapporté | [#16](https://github.com/NOxygen59/kyokasho/issues/16) | — | — |
| RET-014 | 5 | 2026-10-27 | Ergonomie | Choix de langue inaccessible après défilement | à confirmer | rapporté | [#17](https://github.com/NOxygen59/kyokasho/issues/17) | — | — |
| RET-015 | 5 | 2026-10-27 | Fonction | Changer de page avec les flèches du clavier | — | rapporté | [#18](https://github.com/NOxygen59/kyokasho/issues/18) | — | — |
| RET-016 | 5 | 2026-10-27 | Ergonomie | Boutons de page plus discrets | à confirmer | rapporté | [#19](https://github.com/NOxygen59/kyokasho/issues/19) | — | — |
| RET-017 | 4 | 2026-10-27 | Bug (énergie) | 60 % de batterie en 1 h 30 avec l'IA locale | à confirmer | rapporté | [#20](https://github.com/NOxygen59/kyokasho/issues/20) | — | — |
| RET-018 | 4 | 2026-10-27 | Fonction | Avertissement sur la consommation de l'IA locale à l'accueil | — | rapporté | [#21](https://github.com/NOxygen59/kyokasho/issues/21) | — | — |
| RET-019 | 5 | 2026-10-27 | Fonction | Date et heure des notes, groupées par jour | — | rapporté | [#22](https://github.com/NOxygen59/kyokasho/issues/22) | — | — |
| RET-020 | 5 | 2026-10-26 | Fonction | Surligner directement les zones OCR détectées (accès facile, portable sur Mac) | — | rapporté | [#23](https://github.com/NOxygen59/kyokasho/issues/23) | — | — |
| RET-021 | 5 | 2026-10-26 | Fonction | Survol Yomitan seulement pendant l'appui sur Maj | — | rapporté | [#24](https://github.com/NOxygen59/kyokasho/issues/24) | — | — |

Prochain identifiant libre : **RET-022**.
