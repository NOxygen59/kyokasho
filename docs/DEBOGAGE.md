<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Débogage et incidents

## Recueillir un signal utile

Le mode diagnostic de l'app est utilisable quel que soit l'assistant qui aide à analyser le problème. Il n'est pas réservé à Claude. `App/Settings/Diagnostics.swift` définit le journal ; le chemin est **Réglages → Aide et informations → Aide au diagnostic → Mode diagnostic**. La recherche « diagnostic » dans les réglages mène aussi à cet écran. L’activation enrichit le journal sans ajouter d’indicateur au lecteur : elle ne produit pas forcément de changement visuel. Les erreurs sont toujours notées, même si le mode est désactivé.

Activer le diagnostic, reproduire le problème une fois, puis « Voir le journal » sur le même écran. « Partager le journal » transmet le fichier complet et ne le nettoie pas : pour GitHub, recopier manuellement seulement un extrait relu et expurgé ; le fichier est aussi dans `Documents/Diagnostics/journal.txt` du conteneur. Relever version/build, iOS, livre/page, moteur/modèle, langue, orientation et périphérique. Vérifier le contenu avant de le publier : un journal ou une capture peut révéler des chemins, textes ou titres personnels.

Un bon rapport contient : étapes exactes, attendu, observé, fréquence, dernière version où cela fonctionnait, opération en cours et premier message d'erreur. Une capture aide au rendu ; le journal aide aux tâches et à Metal ; le `.ips` aide au crash. N'envoyer ni clé ni mot de passe. Utiliser un exemple synthétique dès que possible.

## Orienter l'enquête

| Symptôme | Premiers éléments à vérifier |
|---|---|
| Mot faux ou absent | PDF texte/image, moteur OCR, texte brut, langue, dictionnaire et MeCab |
| Furigana panneau présents mais absents sur page | OCR géométrique, boîtes/caractères, alignement, orientation et réglage page |
| Chat sur de mauvaises pages | Étiquettes des pages, question exacte, lectures Ovis disponibles et passages sélectionnés |
| App lente | Phase : chargement, lecture image, génération, rendu ; modèle et froid/chaud |
| Fermeture pendant IA | Première erreur MLX/Metal, mémoire disponible, rapport `.ips` ou jetsam |
| Notes/repères décalés | Taille/rotation/égalisation, ajout de pages, versions avant/après |
| Travail bloqué | Tâche active, chargement partagé, annulation, état après changement de vue |
| Bibliothèque qui ne persiste plus | Erreur d'ouverture de base : AppModel prévoit un repli en mémoire, à distinguer d'une base persistante réparée |

Le repli en mémoire après échec d'ouverture de base maintient une interface utilisable, mais ne prouve pas la conservation des nouvelles écritures. Préserver la base sur disque avant une réparation.

## Symboliser un crash

Conserver le `.ips`, le binaire exact et son dSYM **avant** de reconstruire avec `build_ipa.sh`, qui remplace l'archive. Une archive d'une autre compilation peut porter le même numéro de version et être inutilisable pour cette symbolisation.

```sh
dwarfdump --uuid build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM
```

Comparer l'UUID arm64 au `slice_uuid` de l'image Kyokasho du rapport. Puis adapter la base de chargement et les adresses du même rapport :

```sh
atos -arch arm64 \
  -o build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM/Contents/Resources/DWARF/Kyokasho \
  -l <base-de-chargement> <adresse-du-rapport>
```

Les marqueurs entre chevrons sont à remplacer, pas à coller tels quels dans le terminal. Consigner la pile et la fonction responsable ; ne pas inventer de symbole en l'absence du bon UUID. Un arrêt jetsam se traite par analyse de pression mémoire et contexte d'utilisation, pas seulement avec `atos`.

## Enquête MLX et Metal

Lire [IA locale](IA-LOCALE.md). Les deux compilations des kernels — précompilation Mac et compilation à la volée sur iPad — doivent rester compatibles. Un essai Mac forcé Metal 3.0 ne reproduit pas toutes les absences du compilateur iOS 16 ; cela a déjà masqué `remove_addrspace_t` et `simdgroup_matrix<bool>`.

Garder la première erreur, identifier le kernel et les motifs similaires, comparer les API disponibles puis appliquer un équivalent dans le fork. Ne pas couper les contrôles libc++ ni transformer une erreur de chargement en succès silencieux. Une modification du fork doit être poussée et épinglée avant la compilation du paquet qui la revendique.

## Ajouter de l'observabilité

Sur un nouveau chemin lourd, employer `Diagnostics.log`, `measure` et `error` aux frontières : début/fin/échec/annulation, identifiant de tâche, document/page, modèle, durée et catégorie d'erreur. Éviter le contenu intégral d'un manuel et les identifiants de compte. Ne pas enregistrer chaque token ou chaque image en production sans nécessité.

Pour un incident de données, arrêter les opérations qui modifient la ressource, garder une copie cohérente, reproduire sur une copie et distinguer cause démontrée de piste. Le marqueur `page-shift.json` est une preuve de l'état de reprise ; ne pas l'effacer arbitrairement.

## Clôturer

Une correction est terminée lorsque le cas réduit échoue avant, réussit après, que les comportements proches sont préservés et que le statut iPad est explicitement renseigné. Conserver dans la PR le symptôme, la cause prouvée, la correction, les tests et les limites ; l'historique de chat seul ne suffit pas à la prochaine reprise.

## Consultation après correction QA02 (non validée sur iPad)

« Voir le journal » lit un instantané après ouverture. « Actualiser » relit les écritures déjà
en file ; il n'y a pas de suivi continu. Journal absent, vide et erreur de lecture sont distincts.
Une rotation coupant un caractère UTF-8 laisse le reste lisible ; l'export brut reste inchangé.
Les pastilles IA proposent aussi ce journal. Leur « Voir le détail » reste réservé aux tâches
actives : absence de tâche ne signifie pas absence de journal. Voir les [preuves](QA02-CORRECTIONS-DIAGNOSTICS.md).
