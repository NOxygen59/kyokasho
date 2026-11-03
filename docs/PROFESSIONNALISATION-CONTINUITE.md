<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Continuité du plan de professionnalisation — 3 novembre 2026

## Décision et périmètre

NOxygen59 demande le 03/11 d'intégrer la suite du bilan de professionnalisation dans Git local et de la rendre accessible depuis Obsidian, sans désorienter les agents en cours de travail. Ce lot est **documentaire** : il ne réalise pas les automatismes proposés ci-dessous, ne change aucune version, dépendance, CI ou donnée, et n'autorise aucune publication ni fusion.

Ce document prolonge [le plan directeur](PLAN-DIRECTEUR.md). Les identifiants existants sont conservés ; aucune nouvelle roadmap concurrente n'est créée. Les relevés anciens du plan restent historiques. Les fichiers et preuves datés, le pont local et la passation active déterminent la reprise concrète.

## Reprise sans interruption

1. Un agent déjà au travail conserve sa tâche, sa branche et ses critères d'acceptation. Il prend connaissance de cette mise à jour à sa prochaine passation ; il ne redémarre pas un audit général.
2. Le lot « rotation fiable » de Claude reste prioritaire. Cette documentation ne valide ni son correctif, ni une candidate ultérieure. Relire son état réel avant toute revue : il peut évoluer après la rédaction de ce plan.
3. Qwen est mis en retrait par le manager : aucune attente de son rapport ne bloque le cycle. Claude développe ; Codex assure la revue indépendante adaptée au risque et vérifie aussi la cohérence des preuves. L'auteur reste responsable de sa propre vérification. Un contrôle de l'auteur n'est jamais présenté comme indépendant.
4. Les rapports Qwen déjà produits restent des éléments historiques utilisables. Une intervention future de Qwen est facultative, sur demande du manager. Cela ne concerne pas les modèles Qwen utilisés **dans l'application**.
5. Sur ce Mac, commencer par le point d'entrée Obsidian et le protocole local lorsqu'ils sont disponibles, puis lire uniquement les documents du chantier. Le vault reste hors Git. En leur absence, les guides versionnés suffisent ; indiquer les informations locales indisponibles.

## Lots progressifs et critères de fin

La planification est intégrée ; les réalisations techniques restent à attribuer séparément. Cet ordre ne supplante pas une tâche déjà autorisée. Ne pas imposer aux anciennes candidates une reconstruction rétroactive ; consigner les informations manquantes.

| Lot / chantiers existants | Travail borné à préparer | Preuve de fin attendue |
|---|---|---|
| A — QA-02 / OPS-01 : fin de tâche et candidate | Appliquer les critères existants avec une fiche courte : comportement attendu, état exact relu, tests pertinents, non testé, avis indépendant et décision manager | Un lot pilote relu sur son dernier état ; chaque réserve est résolue ou explicitement acceptée ; une candidate expérimentale est identifiée comme telle |
| B — OPS-01 / CI-01 : identité des builds | Ajouter un manifeste local au paquet : version/build, branche/SHA, état propre ou diff conservé et empreinté, Xcode/Swift/SDK, épingles des dépendances, commande, tests et journaux, SHA-256 du paquet, archive et dSYM/UUID lorsqu'ils sont disponibles | Reconstitution de l'origine d'un paquet et correspondance binaire/symboles vérifiées ; aucune donnée personnelle ni symbole déclaré présent sans contrôle |
| C — CI-01 / QA-01 : validation locale unifiée | Réutiliser les commandes de tests et de build existantes dans un point d'entrée manuel ; profils rapides/ciblés et complets, échec correctement propagé, rapport lié au SHA et au diff | Succès et échec contrôlés sur corpus synthétique ; ignorés distincts des réussites ; aucune activation Actions, dépendance ou tâche récurrente |
| D — DATA-01/02/03 / QA-03 : preuves des risques | Cibler conservation des retouches OCR, atomicité fichiers/base, sauvegarde/restauration, annulation et géométrie rotation/découpe/export | Test de régression qui distingue avant/après lorsque possible ; cas matériel décrit puis rempli par le manager ; bibliothèque jetable pour les essais de données |
| E — GOV-02/03 / OPS-01 : état et passation | Un seul état courant par information, avec date et source ; index Obsidian vers les documents, distinction statuts Git / Mac / iOS / iPad ; résumés anciens clairement historiques | Reprendre une tâche sans relire les chats ; contradictions détectées ou signalées ; aucun contrôle de liens présenté comme preuve de vérité des statuts |
| F — PERF-01 : mesures de référence | Définir un petit corpus synthétique et des parcours M1 : ouverture, navigation, OCR, longue session ; relever appareil/OS, froid/chaud, modèle, durée et mémoire mesurable | Mesures répétables avant optimisation, limites des outils explicites ; seuils acceptables décidés avec le manager, aucun objectif inventé |

Priorité immédiate : fermer les risques de rotation et de données déjà identifiés. Les lots A et B préparent ensuite les livraisons ; C réutilise B pour les preuves. D continue selon les risques du lot courant. E accompagne chaque passation sans déplacer les fichiers utilisés par les agents ; F précède les optimisations.

## Fiche minimale de contrôle et de passation

À inclure dans la mission/PR ou la preuve existante, sans multiplier les documents :

```text
Tâche / responsable / objectif / critère d'acceptation :
Branche / worktree / SHA / diff éventuel / périmètre du diff relu :
Comportement attendu / données et invariants à préserver :
Fichiers et fonctions à lire, puis dépendances utiles seulement :
Preuves : commandes, environnement, résultats, ignorés, journaux :
Revue indépendante : auteur, état relu, constats, réserves :
Non testé / recette iPad nécessaire / retour arrière et limites données :
Prochaine action exacte / décision attendue du manager :
```

Une modification après la revue invalide ses conclusions pour la partie touchée : faire relire le delta et exécuter les contrôles concernés. Un nombre de tests verts ne prouve pas le comportement UIKit, Metal ou TrollStore sur l'iPad. Le [contrat de fin existant](GOUVERNANCE-ET-REPRISE.md) continue de s'appliquer.

## Point de reprise du présent lot

- Base documentaire : candidate 73, `b06ff62` ; branche locale `codex/professionnalisation-continuite`, indépendante de la rotation.
- Livrable : ce plan, liens de navigation et clarification du cycle à deux agents. Aucun lot A–F déclaré implémenté par cette livraison documentaire.
- Vérification : contrôle des liens/documents et du diff ; aucune nouvelle preuve Swift/iOS/iPad nécessaire ou revendiquée pour ce lot.
- Intégration future : relire le diff documentaire contre la branche cible, préserver les mises à jour intervenues depuis ; fusion uniquement sur accord précis du manager. La présence de cette branche ne signifie pas que le plan est déjà dans `main` ou dans le worktree de Claude.

Procédures existantes à réutiliser : [tests](TESTS.md), [livraison](CI-ET-LIVRAISON.md), [débogage](DEBOGAGE.md), [données](DONNEES-ET-SAUVEGARDES.md), [mémoire et mesures](MEMOIRE-ET-SANITIZERS.md). La [politique zéro dépense](CI-ROADMAP.md) reste inchangée.
