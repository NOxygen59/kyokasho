<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Données, sauvegardes et restauration

## Inventaire à la base v1.3

Les chemins ci-dessous sont relatifs au conteneur de l'app sur iPad. Ils ne désignent pas le dossier source du Mac. La racine réelle dépend de l'installation ; ne pas figer un UUID de conteneur dans les outils.

| Ressource | Emplacement / responsable | Traitement |
|---|---|---|
| PDF importés | `Application Support/Kyokasho/Documents/<id>.pdf`, `DocumentStorage` | Donnée utilisateur, conserver |
| Bibliothèque, OCR, notes, repères, encre, réglages de base | `Application Support/Kyokasho/kyokasho.sqlite`, `AppDatabase` | Donnée persistante ; ne pas assimiler les retouches à un cache |
| Cartes et médias | `ReviewStore`, `review.sqlite` et dossier `Media`, racine fournie par `ReviewModel` | Sauvegarder base et médias ensemble |
| Dictionnaires | `Application Support/Kyokasho/Dictionaries`, intégration DictionaryModel | Dictionnaires et réglages associés à inventorier |
| Modèles et UniDic | `ModelStore.root`, sous `Application Support/Kyokasho/Models` | Retéléchargeables si source/version encore disponibles ; coûteux |
| Lectures IA, traductions | `Application Support/Analysis/<id>/*.md`, `DocumentAITextStore` | Données dérivées coûteuses ; garder pour reproduire un bug |
| Rapports | `Application Support/Analysis/<id>.json` | Résultats dépendant des versions des lectures |
| Chats | `Application Support/Kyokasho/Chats/qwen*.json`, `AIModelViews` | Donnée personnelle persistante |
| Lexique | `DomainLexicon`, fichier `lexique.json` | Donnée personnelle à inclure dans l'inventaire de sauvegarde |
| Préférences | Base et UserDefaults / AppStorage | Un export PDF ne les transporte pas |
| Identifiants de compte | Trousseau selon intégration Drive/GitHub/DeepL | Ne pas exporter dans Git ou les rapports ; prévoir reconnexion |
| Diagnostic | `Documents/Diagnostics/journal.txt` | Potentiellement personnel ; partager après contrôle |
| Vignettes, pages préparées/nettoyées | `Caches/`, dont Thumbnails, Sharpened, Equalized | Régénérables ; ne pas supprimer une tâche active |
| Reprise d'une modification des pages (ajout, suppression, restauration) | `Application Support/Kyokasho/page-shift.json` et PDF de passage | État transactionnel : ne pas effacer à la main |
| Copies des modifications des pages (#49) | `Application Support/Kyokasho/PageShift/<opération>/` (`manifest.json`, PDF d'origine et préparé, lectures IA, rapport, brouillons) | Gardées **30 jours** (décision de NOxygen59) pour restaurer des pages supprimées ; effacées au lancement suivant l'échéance, ou avec le document. Les copies des ajouts faites avant les fiches suivent la date du dossier |
| Identités et archives des pages (#49) | `kyokasho.sqlite` : `pageIdentity`, `pageEdit`, `pageEditRow`, colonne `document.layoutVersion` | Identifiant et numéro imprimé de chaque page ; opérations ; lignes des pages supprimées (notes, encre, surlignages, OCR, repères, rotations, identité, cartes détachées) jusqu'à la purge |

Les chemins précis de chaque sous-système restent définis par le code ; une future sauvegarde doit s'appuyer sur un inventaire central testé, pas recopier cette table comme une liste exhaustive de fichiers immuable.

## Effacement et relecture

« Effacer le cache » concerne des données recalculables. « Effacer le cache OCR » touche des résultats pouvant contenir des retouches manuelles et invalide les votes associés. Supprimer un modèle ne supprime pas un PDF, mais empêche sa prochaine lecture IA tant qu'il n'est pas réinstallé.

`DocumentAITextStore.write` enregistre la sortie brute, et retire l'ancienne traduction française quand Ovis relit la page. La normalisation japonaise se fait à la lecture sans réécrire le brut. Conserver cette séparation pour expliquer ce qui provenait du modèle et ce qui a été transformé.

## Sauvegarde actuelle : ce qui est prouvé et ce qui manque

L'app propose des exports PDF, Markdown, images et Anki. Le code examiné ne démontre pas une fonction de sauvegarde/restauration intégrale et cohérente du conteneur. Aucun export isolé n'est donc présenté comme une assurance de récupération de toutes les données.

Avant une opération risquée : exporter les PDF utiles, notes et cartes par les parcours disponibles ; ouvrir les exports ailleurs ; garder les PDF sources ; noter version/build et modèles. Ne pas désinstaller l'app. Une sauvegarde de conteneur par un outil disponible sur l'appareil demande une procédure propre à cet environnement, à vérifier avec NOxygen59 ; ne pas inventer une commande universelle TrollStore.

Pour une future sauvegarde intégrale, mettre les écritures au repos, utiliser l'API de sauvegarde SQLite adaptée plutôt qu'une copie isolée du `.sqlite` pendant des écritures WAL, et inclure médias, fichiers IA, lexique et préférences. Si l'on copie un conteneur arrêté, traiter ensemble les éventuels fichiers SQLite annexes et vérifier la cohérence après restauration. Ne pas remplacer une base en fonctionnement.

## Protocole de restauration à qualifier

1. Créer un petit corpus synthétique : PDF de plusieurs tailles, notes, dessin, repère, OCR retouché, carte avec média, chat et lexique.
2. Noter nombres d'éléments, hachages des fichiers, version/build et schéma. Produire une sauvegarde par la méthode candidate.
3. Restaurer dans un environnement de test distinct autorisé, jamais par-dessus l'unique bibliothèque sans copie de secours.
4. Ouvrir chaque document, vérifier ancrages et pages, modifier puis rouvrir une note, réviser une carte et consulter les médias, conversations et retouches.
5. Comparer les inventaires et noter toute donnée exclue volontairement, notamment les connexions à rétablir.

Le test n'est réussi qu'après lecture fonctionnelle, pas parce qu'une archive ZIP existe. La première preuve de restauration complète reste à produire.

## Migrations et retour arrière

`AppDatabase` enregistre `v1`, `v2-ocr`, `v3-page-one`, `v4-note-canvas-anchor`. `ReviewStore` a ses propres migrations. Ajouter une nouvelle migration plutôt que réécrire une migration déjà livrée. Tester une base ancienne, une base neuve et une réouverture après migration, avec comparaison des données conservées.

Réinstaller une ancienne app ne garantit pas qu'elle lira une base migrée. Un retour arrière sûr combine code et sauvegarde compatible. Pour un refactoring sans schéma modifié, conserver tout de même les fichiers utilisateur avant les essais de reprise après panne.

L'ajout de pages coordonne plusieurs stockages et comporte des fenêtres non intégralement testées : [audit](AUDIT-V1.3.md). Ne pas supprimer un marqueur de reprise pour masquer un problème ; conserver une copie du marqueur, des bases et des fichiers concernés avant toute analyse.
