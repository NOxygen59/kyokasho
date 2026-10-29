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
| Dictionnaires | `Application Support/Kyokasho/Dictionaries`, `DictionaryDatabase` | Base SQLite des dictionnaires ; profils et carnet dans la base de l'app. Ceux du catalogue (#50) se retéléchargent : `tools/backup_container.py --omit-dictionaries` les laisse de côté (option explicite, car un dictionnaire importé à la main ne se retélécharge pas). Téléchargement temporaire : `tmp/DictionaryDownload-<UUID>/`, effacé après import |
| Audio des dictionnaires | `Documents/Audio`, `DictionaryModel` | Copié par la sauvegarde mais non vérifié : non essentiel (décision de NOxygen59, 28/10/2026) |
| Traductions de définitions | `Application Support/definition-translations.json`, `DefinitionTranslations` | Traductions françaises et votes 👍/👎 ; donnée personnelle |
| Brouillons de notes | `Application Support/Kyokasho/NoteDrafts/<id>.json`, `NoteDraftStore` | Brouillons non encore ajoutés (RET-008) ; donnée personnelle |
| Modèles et UniDic | `ModelStore.root`, sous `Application Support/Kyokasho/Models` (UniDic : `Models/unidic`) | Retéléchargeables si source/version encore disponibles ; coûteux |
| Mesures de vitesse (banc d'essai) | `Application Support/Kyokasho/Bench/`, `AppModel` | Résultats de mesures locales ; incluses dans la sauvegarde |
| Lectures IA, traductions | `Application Support/Analysis/<id>/*.md`, `DocumentAITextStore` | Données dérivées coûteuses ; garder pour reproduire un bug |
| Rapports | `Application Support/Analysis/<id>.json` | Résultats dépendant des versions des lectures |
| Chats | `Application Support/Kyokasho/Chats/qwen*.json`, `AIModelViews` | Donnée personnelle persistante |
| Lexique | `DomainLexicon`, fichier `lexique.json` | Donnée personnelle à inclure dans l'inventaire de sauvegarde |
| Préférences | Base et UserDefaults / AppStorage | Un export PDF ne les transporte pas |
| Identifiants de compte | Trousseau selon intégration Drive/GitHub/DeepL | Ne pas exporter dans Git ou les rapports ; prévoir reconnexion |
| Diagnostic | `Documents/Diagnostics/journal.txt` | Potentiellement personnel ; partager après contrôle |
| Relevé de batterie (#20) | `Documents/Diagnostics/energie.csv` | Seulement si « Relevé de batterie » est allumé : niveau, chaleur, activité de l'app par minute ; non essentiel |
| Vignettes, pages préparées/nettoyées | `Caches/`, dont Thumbnails, Sharpened, Equalized | Régénérables ; ne pas supprimer une tâche active |
| Reprise d'une modification des pages (ajout, suppression, restauration) | `Application Support/Kyokasho/page-shift.json` et PDF de passage | État transactionnel : ne pas effacer à la main |
| Paquets de sécurité (export complet) | `Documents/Paquets de sécurité/<date>/<titre>.kyokasho` (visible dans Fichiers) | Version d'un document **avant** son remplacement par un paquet importé ; à garder ou effacer à la main |
| Sauvegardes complètes (#51) | dossier choisi dans Fichiers (signet `backup.folderBookmark`), `Kyokasho-<date>.kyokasho-sauvegarde`, 10 gardées | Tout `Application Support/Kyokasho` sauf `Models` et `page-shift.json` (bases par l'API SQLite), `Analysis/`, `definition-translations.json`, réglages de l'app ; préparé dans `tmp/BackupApp-<UUID>/` |
| Restauration préparée (#51) | `Application Support/restore-pending.json`, `RestoreStaging/<id>/` (sauvegarde extraite et vérifiée), `RestoreOld/<id>/` (état mis de côté pendant l'application) | État transactionnel : appliqué au lancement suivant avant l'ouverture des bases, rejouable après une coupure ; ne pas effacer à la main. Une sauvegarde de sécurité de l'état d'avant est écrite dans le dossier de sauvegarde avant le marqueur |
| Sauvegarde complète en cours (#51) | `tmp/BackupWrite-<UUID>/` | Temporaire : copies des bases par l'API SQLite et relecture de la sauvegarde ; effacé après usage |
| Paquets en cours (export complet) | `tmp/Export/`, `tmp/PackageImport-<UUID>/`, `tmp/PackageWrite-<UUID>/` | Temporaires : extraction vérifiée d'un paquet importé, fichiers écrits pour un paquet ; effacés après usage |
| Copies des modifications des pages (#49) | `Application Support/Kyokasho/PageShift/<opération>/` (`manifest.json`, PDF d'origine et préparé, lectures IA, rapport, brouillons) | Gardées **30 jours** (décision de NOxygen59) pour restaurer des pages supprimées ; effacées au lancement suivant l'échéance, ou avec le document. Effacées aussi à la demande (« Pages du document » → « Effacer ») et, après une restauration réussie, celles de la suppression restaurée et de la restauration (recette 68). Les copies des ajouts faites avant les fiches suivent la date du dossier |
| Identités et archives des pages (#49) | `kyokasho.sqlite` : `pageIdentity`, `pageEdit`, `pageEditRow`, colonne `document.layoutVersion` | Identifiant et numéro imprimé de chaque page ; opérations ; lignes des pages supprimées (notes, encre, surlignages, OCR, repères, rotations, identité, cartes détachées) jusqu'à la purge |

Les chemins précis de chaque sous-système restent définis par le code. Depuis DATA-02 (#83), le test `testI2EveryStorageLocationInCodeIsInventoried` alerte quand une source qui appelle directement les API de répertoire du conteneur n'est pas inventoriée, ou y ajoute un nouveau composant de chemin littéral : mettre alors à jour ce test **et** cette table. C'est une alerte partielle, dont les limites sont détaillées dans [TESTS.md](TESTS.md), section DATA-02 : un chemin dérivé d'une racine existante sans ces API n'est pas détecté.

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

## Paquet d'un document (`.kyokasho`)

« Exporter… » → « Paquet Kyōkasho (tout le document) » écrit un zip : PDF exact, lignes du document dans `kyokasho.sqlite` (fiche, annotations, OCR et retouches, identités des pages), lectures IA et traductions (`Analysis/<id>/`), rapport d'analyse, brouillons, langue OCR et modes du lecteur, liste des dictionnaires. Ni cartes, ni conversations, ni réglages de l'app, ni dictionnaires, ni modèles (décision de NOxygen59, 29/10/2026). Import (Importer → « Importer un paquet Kyōkasho ») : paquet vérifié en entier avant toute modification (empreintes, PDF = identifiant, chemins autorisés) ; document déjà présent remplacé seulement après accord, après un paquet de sécurité de sa version actuelle. Code : `ReaderCore/DocumentPackage.swift`, `App/Library/DocumentPackageService.swift`.
