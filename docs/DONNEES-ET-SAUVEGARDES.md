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
| Audio des dictionnaires | `Documents/Audio`, `DictionaryModel` | Copié par l'outil Python de conteneur, non inclus dans la sauvegarde de l'app : non essentiel (décision de NOxygen59, 28/10/2026) |
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
| Extraction des lectures OvisOCR2 (aide au diagnostic) | `tmp/partage-lectures-<UUID>/<titre> - lectures <modèle>.txt`, `AIReadingExport` | Temporaire, contient le texte du livre ; partagé par NOxygen59, jamais envoyé seul |
| Comics en cours d'import | `Kyokasho/Documents/<UUID>.partial`, `<UUID>.page`, `ComicBookArchive` | Temporaires, à côté de la destination : PDF en cours et page extraite, effacés après l'import ; le `.cbz` n'est pas gardé. Correspondances archive → document (`comics.sources`) et CBZ → PDF converti (`comics.converted`) dans la base, donc sauvegardées. Espace Manga : `mangaSpace` dans les réglages du document, qui suit aussi les paquets. Les anciennes versions ignorent ces valeurs |
| Paquets en cours (export complet) | `tmp/Export/`, `tmp/PackageImport-<UUID>/`, `tmp/PackageWrite-<UUID>/` | Temporaires : extraction vérifiée d'un paquet importé, fichiers écrits pour un paquet ; effacés après usage |
| Copies des modifications des pages (#49) | `Application Support/Kyokasho/PageShift/<opération>/` (`manifest.json`, PDF d'origine et préparé, lectures IA, rapport, brouillons) | Gardées **30 jours** (décision de NOxygen59) pour restaurer des pages supprimées ; effacées au lancement suivant l'échéance, ou avec le document. Effacées aussi à la demande (« Pages du document » → « Effacer ») et, après une restauration réussie, celles de la suppression restaurée et de la restauration (recette 68). Les copies des ajouts faites avant les fiches suivent la date du dossier |
| Identités et archives des pages (#49) | `kyokasho.sqlite` : `pageIdentity`, `pageEdit`, `pageEditRow`, colonne `document.layoutVersion` | Identifiant et numéro imprimé de chaque page ; opérations ; lignes des pages supprimées (notes, encre, surlignages, OCR, repères, rotations, identité, cartes détachées) jusqu'à la purge |

Les chemins précis de chaque sous-système restent définis par le code. Depuis DATA-02 (#83), le test `testI2EveryStorageLocationInCodeIsInventoried` alerte quand une source qui appelle directement les API de répertoire du conteneur n'est pas inventoriée, ou y ajoute un nouveau composant de chemin littéral : mettre alors à jour ce test **et** cette table. C'est une alerte partielle, dont les limites sont détaillées dans [TESTS.md](TESTS.md), section DATA-02 : un chemin dérivé d'une racine existante sans ces API n'est pas détecté.

## Effacement et relecture

« Effacer le cache » concerne des données recalculables. « Effacer le cache OCR » touche des résultats pouvant contenir des retouches manuelles et invalide les votes associés. Supprimer un modèle ne supprime pas un PDF, mais empêche sa prochaine lecture IA tant qu'il n'est pas réinstallé.

`DocumentAITextStore.write` enregistre la sortie brute, et retire l'ancienne traduction française quand Ovis relit la page. La normalisation japonaise se fait à la lecture sans réécrire le brut. Conserver cette séparation pour expliquer ce qui provenait du modèle et ce qui a été transformé.

## Sauvegarde actuelle : ce qui est prouvé et ce qui manque

Deux mécanismes existent et leurs preuves ne sont pas interchangeables :

- **Dans l'app**, Réglages → Fichiers et comptes → Sauvegarde crée une archive `.kyokasho-sauvegarde`. Les trois bases utilisent l'API SQLite de sauvegarde, même ouvertes. Sont inclus `Application Support/Kyokasho/` (sauf modèles et transaction de pages), `Analysis/`, `definition-translations.json` et les préférences ; les fichiers de `Documents/` (diagnostics, audio, paquets de sécurité) et les caches n'en font pas partie. La restauration vérifie les empreintes et l'intégrité SQLite, exige une copie de sécurité dans le dossier choisi, puis s'applique au prochain lancement avant l'ouverture des bases. Les modèles locaux sont conservés ; les réglages propres à l'appareil (comptes, signet de sauvegarde, diagnostic, etc.) restent ceux de l'appareil. Aucun identifiant du Trousseau n'est exporté.
- **Sur Mac**, `tools/backup_container.py` copie un conteneur dont l'app source est arrêtée. Il couvre aussi `Documents/` et `Library/Preferences/` ; ses exclusions sont des options explicites. Procédure et limites : [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md). Ses tests seuls ne prouvent pas le parcours de restauration de l'app.

Depuis le chantier du 04/11, un test du **format applicatif** remplit les vrais `AppDatabase`, `ReviewStore` et `DictionaryDatabase`, sauvegarde leurs bases ouvertes, restaure dans un dossier temporaire puis compare les données et rouvre les bases en écriture. Il couvre PDF, notes ancrées/dessins, repères, surlignages, OCR marqué corrigé, cartes et historique FSRS, média de carte, dictionnaire importé, brouillons et fichiers IA/lexique/conversation. Les fichiers sont comparés ; leur rendu iPad n'est pas testé par cette preuve. Détail, commandes et recette : [SAUVEGARDE-RESTAURATION-2026-11-04.md](SAUVEGARDE-RESTAURATION-2026-11-04.md).

Une bibliothèque sauvegardée sans `definition-translations.json` ne doit pas garder celui de la bibliothèque remplacée. Ce cas est désormais traité, avec reprise après interruption ; les autres fichiers de support restent intacts. Les tests antérieurs de reprise à chaque étape et de nettoyage différé restent applicables.

Avant une opération risquée, garder une copie vérifiée des données et les PDF sources ; noter version/build et modèles. Ne pas désinstaller l'app. Ne jamais remplacer une base en fonctionnement. Le parcours SwiftUI, les fournisseurs Fichiers et la restauration réelle sur iPad restent à qualifier ; aucune commande universelle TrollStore n'est supposée.

## Protocole de restauration à qualifier

1. Créer un petit corpus synthétique : PDF de plusieurs tailles, notes, dessin, repère, OCR retouché, carte avec média, chat et lexique.
2. Noter nombres d'éléments, hachages des fichiers, version/build et schéma. Produire une sauvegarde par la méthode candidate.
3. Restaurer dans un environnement de test distinct autorisé, jamais par-dessus l'unique bibliothèque sans copie de secours.
4. Ouvrir chaque document, vérifier ancrages et pages, modifier puis rouvrir une note, réviser une carte et consulter les médias, conversations et retouches.
5. Comparer les inventaires et noter toute donnée exclue volontairement, notamment les connexions à rétablir.

La preuve automatisée Mac du format applicatif comprend maintenant la relecture fonctionnelle des bases et l'écriture après restauration. La recette réelle sur iPad, le rendu des dessins et les connexions restent distincts et non confirmés dans ce chantier.

## Migrations et retour arrière

`AppDatabase` enregistre `v1`, `v2-ocr`, `v3-page-one`, `v4-note-canvas-anchor`. `ReviewStore` a ses propres migrations. Ajouter une nouvelle migration plutôt que réécrire une migration déjà livrée. Tester une base ancienne, une base neuve et une réouverture après migration, avec comparaison des données conservées.

Réinstaller une ancienne app ne garantit pas qu'elle lira une base migrée. Un retour arrière sûr combine code et sauvegarde compatible. Pour un refactoring sans schéma modifié, conserver tout de même les fichiers utilisateur avant les essais de reprise après panne.

L'ajout de pages coordonne plusieurs stockages et comporte des fenêtres non intégralement testées : [audit](AUDIT-V1.3.md). Ne pas supprimer un marqueur de reprise pour masquer un problème ; conserver une copie du marqueur, des bases et des fichiers concernés avant toute analyse.

## Paquet d'un document (`.kyokasho`)

« Exporter… » → « Paquet Kyōkasho (tout le document) » écrit un zip : PDF exact, lignes du document dans `kyokasho.sqlite` (fiche, annotations, OCR et retouches, identités des pages), lectures IA et traductions (`Analysis/<id>/`), rapport d'analyse, brouillons, langue OCR et modes du lecteur, liste des dictionnaires. Ni cartes, ni conversations, ni réglages de l'app, ni dictionnaires, ni modèles (décision de NOxygen59, 29/10/2026). Import (Importer → « Importer un paquet Kyōkasho ») : paquet vérifié en entier avant toute modification (empreintes, PDF = identifiant, chemins autorisés) ; document déjà présent remplacé seulement après accord, après un paquet de sécurité de sa version actuelle. Code : `ReaderCore/DocumentPackage.swift`, `App/Library/DocumentPackageService.swift`.
