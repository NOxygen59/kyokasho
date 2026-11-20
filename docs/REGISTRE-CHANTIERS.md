<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Registre des chantiers

Seule table active de ce qui est ouvert dans Kyōkasho : bugs, incohérences, dettes et projets.
Elle a été établie le 19/11/2026 par une réunion d'agents en trois tours. Codex a arbitré ; DeepSeek V4 Pro, GLM 5.3
et DeepSeek V4.1 Flash ont analysé. Le travail s'est fait en lecture seule, sur `f4c0718`.

- **GitHub** suit les actions (tickets, PR).
- **[RETOURS-IPAD.md](RETOURS-IPAD.md)** garde les scénarios et les résultats des recettes.
- Le **[plan directeur](PLAN-DIRECTEUR.md)** dit où en est le projet.
- Ce registre ne recopie pas l'état de ces documents : il les relie.

## Légende

- **Gravité** : P1 bloque la livraison ou la publication ; P2 est un problème significatif ; P3 un suivi mineur.
- **Risque** du travail à faire :
  - R0 : documentation ;
  - R1 : interface isolée ;
  - R2 : données, concurrence ou plusieurs modules ;
  - R3 : changement structurel ou décision produit.
- **Statut** : « confirmé dans le code » ne veut pas dire « corrigé », et « à recetter » ne vaut pas validation.
- **Règle de clôture** : un ticket de code se ferme seulement après une confirmation sur iPad par le responsable
  (voir [RETOURS-IPAD.md](RETOURS-IPAD.md), « Compilé iOS ne veut pas dire fonctionne sur iPad »). Un ticket de
  documentation se ferme quand le document est présent sur `main` et répond à la demande du ticket.

## Ordre des lots

1. **Confidentialité** : tout de suite.
2. **1.5.10** : KYO-001, 002 et 006 d'abord, puis les rappels (KYO-004) ; KYO-003 selon la recette.
3. **Cohérence et Diagnostics** : sur des tranches de code séparées (plan des diagnostics approuvé le 19/11, code après la 1.5.10).
4. **Performance mesurée.**
5. **Plus tard.**

## Table

| ID | Titre | Lot | Gravité | Risque | Statut | Ticket | Condition de clôture |
|---|---|---|---|---|---|---|---|
| KYO-060 | Retirer les chemins et références personnels des contenus publiés, et empêcher qu'ils reviennent | Confidentialité | P1 | R2 | En cours : chemins absolus et titre retirés de la version courante ; historique et artefacts publiés à décider | Suivi privé | Contenus courants propres, garde-fou de commit qui refuse les chemins personnels, décision sur l'historique |
| KYO-001 | Le lecteur ne s'ouvre plus après le menu d'un document ou la fenêtre d'export | 1.5.10 | P1 | R2 | Signal de recette ; piste dans le code, cause non prouvée | À créer | Recette iPad des gestes carte, menu, export et partage ; ouverture du même puis d'un autre document ; journal « demandé → affiché → PDF prêt ou échec » |
| KYO-002 | Furigana absents après export ou après « Effacer le cache » | 1.5.10 | P1 | R2 | Signal de recette ; cause inconnue | À créer | Rendu stable après chaque purge, réouverture, changement de page et retour au premier plan ; OCR enregistré intact |
| KYO-003 | Une paire d'égalisation incohérente n'est jamais régénérée, l'export refuse | 1.5.10 | P2 | R2 | Défaut confirmé dans le code ; corrigé dans ce lot s'il est reproduit ou contribue à KYO-001/002, sinon suivi en Cohérence | À créer | Export fidèle ou refus expliqué, vérifié sur iPad (rotation, tailles mixtes, annotations) |
| KYO-004 | Rappels de notes : numéro de page imprimé, autorisation refusée, mise à jour des rappels | 1.5.10 | P2 | R2 | Confirmé dans le code | À créer | Bon numéro et bonne note ; rien programmé après un refus ; mise à jour sans recréation inutile ; affichage du plafond de rappels en Cohérence |
| KYO-006 | « Autres mots » enregistre le mot lui-même comme lecture | 1.5.10 | P2 | R1 | Confirmé dans le code | À créer | Lecture inconnue laissée vide ; cartes existantes et calendrier de révision intacts |
| KYO-008 | Porte avant candidate : relecture de tout le diff et citations vérifiées | 1.5.10 | P1 | R0 | PR #91 bloquée | PR #91 | Diff entier relu, références vérifiées au SHA, recette ciblée consignée, accord de fusion distinct |
| KYO-007 | Notes : texte tapé perdu si l'écriture est occupée, actions groupées, aide d'urgence | Cohérence | P3 | R1 | Confirmé dans le code | — | Texte conservé, actions ordonnées, aide conforme à la règle horaire |
| KYO-009 | Classeurs et étiquettes de notes : renommer, supprimer ; suppression de note confirmée partout | Cohérence | P2 | R2 | À faire (décision du 19/11) | — | Même confirmation et même résultat dans l'écran Notes et dans le lecteur |
| KYO-011 | Document supprimé : cartes gardées par défaut, proposition de les supprimer ; rappels après renommage | Cohérence | P2 | R2 | À faire (décision du 19/11) | — | Choix proposé à la suppression ; rappels à jour après renommage |
| KYO-013 | Réglages globaux repérables (page Notes, Fond de page et Nettoyage des scans dans Réglages › Lecture) ; erreurs des cartes visibles | Cohérence | P2 | R2 | À faire (décision du 19/11) | #50 lié | Un seul chemin par réglage global ; erreurs visibles |
| KYO-030 | Recettes données : remplacement Drive, ajout et suppression de pages, restauration | Cohérence | P2 | R2 | Preuves iPad à compléter | #48, #49 | Recette sur copie jetable : historique, corbeille, restauration, repères et OCR |
| KYO-036 | Ancienne PR de la 1.5.7 remplacée par la #91 | Cohérence | P3 | R0 | Inclusion vérifiée | PR #90 | PR #90 fermée sans fusion, avec lien vers #91 |
| KYO-040 | Fenêtre OCR : pastille, modes, choix du moteur, analyse | Cohérence | P3 | R1 | En partie livré ; à recetter | #38, #39, #41, #42, #60 | Un scénario iPad par critère |
| KYO-041 | Survol avec Maj : activation et stabilité | Cohérence | P2 | R1 | Livré ; à recetter | #24, #61 | Panneau et page PDF ; relâchement de Maj et curseur rapide vérifiés séparément |
| KYO-044 | Navigation, temps de lecture, dates des notes | Cohérence | P3 | R1 | #18 confirmé sur iPad ; reste à recetter | #16, #18, #19, #22, #52 | Clôture de #18 proposée (preuve iPad), sur accord ; les autres après recette |
| KYO-047 | Avertissement de l'IA locale, zones OCR surlignées, signets, catégorie à l'import | Cohérence | P3 | R1 | Livré ; à recetter | #21, #23, #43, #54 | Un scénario iPad par ticket |
| KYO-051 | Moniteur de performances : compacité, accès, pastilles IA | Cohérence | P3 | R1 | Deux demandes distinctes à préciser | #40, #47 | Tickets liés, chacun recetté pour lui-même |
| KYO-058 | Documentation : guides et libellés de réglages périmés, notes de version 1.4 à 1.5.9 absentes de `docs/` | Cohérence | P3 | R0 | Relevé fait (19/11) | #26 | Guides alignés sur les réglages actuels, notes de version rangées ; brief README (#26) traité à part |
| KYO-029 | Guide de la chaîne OCR → zones → furigana | Cohérence | P3 | R0 | Livré et conforme sur `main` | #46 | Clôture de #46 proposée (guide présent et conforme), sur accord |
| KYO-015 | Diagnostics renforcés (événements typés, partage filtré) | Diagnostics | P2 | R2 | Plan approuvé, pas de code | À créer | Étapes E1 à E5 du plan validées ; partage sans donnée personnelle |
| KYO-019 | « Voir le journal » lent quand le journal est long | Diagnostics | P2 | R1 | Livré ; à recetter | #67 | Ouverture rapide d'un long journal vérifiée sur iPad |
| KYO-042 | Le survol du dictionnaire cesse de répondre | Diagnostics | P2 | R1 | Cause inconnue | #36 | Reproduction tracée, cause trouvée, correctif recetté |
| KYO-043 | Miniatures après une correction OCR | Diagnostics | P2 | R1 | À préciser | #35 | Reproduction écrite avant tout correctif |
| KYO-016 | Requêtes de la base sur le fil principal (révision, listes de cartes, carnet du dictionnaire) | Performance | P2 | R2 | Confirmé dans le code ; coût non mesuré | — | Mesures avant/après sur parcours fixes ; ordre de révision et historique intacts |
| KYO-020 | Mémoire de l'OCR, export et énergie de l'IA locale | Performance | P2 | R2 | Non mesuré | #20 | Mesure reproductible sur iPad, puis correction du premier coût prouvé |
| KYO-021 | Code mort et clés inutilisées | Plus tard | P3 | R2 | Candidats relevés, non prouvés | — | Absence d'appel prouvée (y compris clés dynamiques) avant tout retrait |
| KYO-025 | Design : fenêtres, icône, accessibilité, design des dossiers | Plus tard | P3 | R1 | Conception | #44, #53 | Critères produit décidés, puis recette |
| KYO-027 | IA et dictionnaires : paramètres avancés, résumé de page, lexiques | Plus tard | P3 | R2 | En partie livré ; périmètre à préciser | #37, #45, #50 | Reste à faire écrit dans chaque ticket, puis recette |
| KYO-056 | Sauvegarde en ligne, import OCR, version Mac | Plus tard | P3 | R3 | Conception, pas d'engagement | #51, #55 | Décision produit séparée pour chacun |

Identifiants regroupés le 19/11, jamais réattribués : 005 → 004 ; 032 → 003 ; 039 → 008 ; 010 → 009 ; 012 → 011 ;
014 et 022 → 013 ; 031 et 053 → 030 ; 038 → 036 ; 050 → 040 ; 045 et 046 → 044 ; 048 et 055 → 047 ; 017 → 016 ;
018 → 020 ; 023, 024 et 028 → 021 ; 026, 037 et 052 → 025 ; 049, 054 et 059 → 027 ; 057 → 056.
KYO-033, 034 et 035 (QA transverse, CI-0, Drive et données mises de côté) : reliquats à vérifier, lot Plus tard.
Tickets à fermer : seulement #18 et #46, sur accord du responsable. #40 et #47 restent distincts et liés.
