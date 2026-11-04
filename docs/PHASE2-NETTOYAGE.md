<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Nettoyage recommandé — classement avant toute refactorisation

Inspection du code v1.3 (`16d2dd8`), recoupée avec la correction PageShift proposée séparément. Aucun code n'est supprimé ou déplacé par ce document. Les noms et responsabilités constituent des points de départ, pas une preuve d'inutilité fondée sur une seule recherche textuelle.

| Rang | Zone et constat | Bénéfice attendu | Risque / preuve préalable |
|---|---|---|---|
| 1 | `DocumentAnalysisService.save`, écritures de lecture/traduction et `AIModelViews` : plusieurs `try?` peuvent masquer des échecs persistants | Éviter d'afficher un résultat comme conservé quand l'écriture échoue | Élevé : injecter erreurs disque et vérifier contenu/cache/notifications avant de changer la propagation d'erreur |
| 2 | `AppModel.init`, `ReviewModel.init` : repli en mémoire lors d'une base inaccessible | Rendre visible l'absence de persistance et éviter des succès trompeurs | Élevé : PageShift refuse ce repli dans la PR de correction ; étendre aux autres écritures seulement après scénario produit et tests |
| 3 | `PDFMergeView.merge` et `AddPagesView.apply` : deux boucles PDFKit de copie/fusion proches, avec traitements d'erreur différents | Un contrat de fusion « toutes les pages ou échec », testable | Moyen/élevé : le premier chemin peut ignorer une page non copiable ; reproduire avant correction. Préserver ordre, fermeture et annulation ; ne pas extraire avant preuve |
| 4 | `AIModelViews.swift` : interface, persistance JSON, conversations, choix de modèle et génération dans le même fichier | Tester sauvegarde/conversations sans interface ou poids IA | Moyen : préserver anciens fichiers, numérotation, historique, arrêt et durée de vie du modèle ; extraire une seule frontière à la fois |
| 5 | `DocumentKnowledge` et stockage IA dans App | Tester ciblage de page, questions nouvelles/relances, absence de source et langue sans modèle | Moyen : données réelles de pageLabel et fixtures multilingues avant extraction vers un package |
| 6 | `ReaderController.swift` : 1 022 lignes, plus extensions partageant l'état | Réduire le couplage entre affichage, navigation, OCR et tâches | Élevé : les gestes ont déjà régressé. Tests de repères/coordonnées et recette iPad avant extraction. Le nombre de lignes ne justifie pas une réécriture |
| 7 | `StorageUsage`, chemins AppModel/Review/IA/préférences et futur backup | Inventaire explicite évitant l'oubli d'une base, des médias ou du lexique | Moyen : comparer inventaires existants ; ne pas traiter OCR retouché comme cache ni introduire un service global sans usages précis |
| 8 | Annulation de `Task.detached`, gestion des caches et notifications | Réduire travail périmé et rétention de ressources | Moyen/élevé : mesures et tests de changement de page/document/modèle ; pas de nouveau framework de concurrence à l'aveugle |
| 9 | `MorphologyKit/MeCab` : création partielle tagger/lattice, `@unchecked Sendable` et verrou | Vérifier la libération native et documenter la propriété mémoire | Moyen : injection d'échec native et vrai dictionnaire autorisé. Le soupçon de fuite n'est pas présenté comme fuite observée |
| 10 | Anciennes méthodes de décalage après la nouvelle orchestration | Éviter deux chemins de reprise concurrents à terme | Le 04/11, retrait local de la seule méthode interne `DocumentAnalysisService.shiftReport`, sans appel produit, dans le [lot ciblé](NETTOYAGE-CIBLE-2026-11-04.md) ; le PageShift actuel et les adaptateurs de test restent inchangés. `ReviewStore.shiftSourcePages` demeure public et testé : conservé. Aucune suppression générale ni intégration dans `main` revendiquée |

## Candidats qui ne doivent pas être supprimés par simple comptage

`BenchView` reste accessible depuis les réglages ; les callbacks UIKit/SwiftUI, points d'entrée Objective-C, clés persistées et ressources peuvent être invoqués sans appel Swift textuel. Les champs historiques `Pending.stage` servent encore à lire les journaux anciens. Les balises FDR indiquent souvent un travail planifié, pas du code mort. La faible fréquence d'un symbole n'est donc qu'un signal d'inspection.

## Séquence conseillée

Intégrer d'abord les preuves de reprise et qualifier la restauration. Choisir ensuite un défaut de persistance observable, écrire sa régression, faire la correction ciblée puis seulement une extraction qui conserve le comportement. Séparer chaque changement de format, mise à jour de dépendance et amélioration visuelle. Une PR doit rester examinable avec son critère de fin et son retour arrière.

Les tests prioritaires suivants sont : échecs de sauvegarde des conversations/rapports ; langue et lignes OCR éditées ; ciblage du chat sur pages imprimées/romaines/absentes ; annotations et export après égalisation ; durée de vie de tâches et modèles. Les nouvelles fonctions (Continuer, grammaire, moteurs) viennent après la stabilisation, selon les choix de NOxygen59.

Les commentaires doivent expliquer contrats, propriété mémoire, repères et raisons des rétroportages iOS 16. Aucun objectif de commentaire par ligne, de réécriture totale, de suppression massive ou de pourcentage arbitraire de couverture n'est proposé.
