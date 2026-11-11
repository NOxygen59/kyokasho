<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Sauvegarde et restauration — 04/11/2026

## Périmètre autorisé

Chantier 1 choisi par NOxygen59, puis revue indépendante par Claude. Branche `codex/sauvegarde-restauration`, base `15f18a3` (corrections Claude incluses). Aucune fusion, publication, candidate, version, dépendance ou donnée personnelle modifiée. Les essais créent uniquement des bibliothèques synthétiques temporaires. Le format de sauvegarde reste en version 1, sans migration.

## Défaut corrigé

`LibraryRestore.install` ne traitait les fichiers `support/` que s'ils étaient présents dans le marqueur. Restaurer une bibliothèque sans traductions laissait donc `definition-translations.json` de la bibliothèque remplacée, contrairement au remplacement des autres données.

La cible connue `support/definition-translations.json` rejoint toujours les emplacements à installer ou vider. Le mécanisme existant de mise de côté et de reprise traite son absence. Aucun parcours de suppression global d'Application Support n'est ajouté. Le test conserve un fichier de support sans rapport avec la bibliothèque et les modèles locaux.

Preuve avant correction : `LibraryRestoreTests.testAbsentOptionalDataDoesNotLeakFromReplacedLibrary` échoue sur le code de base (deux assertions « fichier absent » et une assertion de coupure non atteinte). Après correction, les variantes normale et interrompue passent.

## Preuves automatisées

`AppBackupRoundTripTests.swift`, extension de `BackupRoundTripTests`, appelle les vraies API `LibraryBackup.write/open` puis `LibraryRestore.writeMarker/apply`, et non l'outil Python. Les pools SQLite restent ouverts pendant l'archive. Une note ajoutée après la sauvegarde reste absente des données restaurées.

| Élément | Vérification |
|---|---|
| PDF synthétique valide | Octets identiques après installation |
| Document, note ancrée et dessin | Relecture par AppDatabase, valeurs identiques |
| Repère, surlignage, encre | Relecture par les API de l'app |
| OCR corrigé | JSON marqué `edited`, octets conservés ; pas de moteur OCR exécuté |
| Carte et historique FSRS | Relecture par ReviewStore, valeurs identiques |
| Média de carte | Octets identiques |
| Dictionnaire | Import Yomitan réel, restauration puis recherche du terme |
| Brouillon | Relecture par NoteDraftStore |
| Lecture IA, rapport, chat, lexique, traductions | Fichiers synthétiques comparés, sans exécution MLX ni validation du rendu |
| Préférences | Plist injecté et rappel de restauration vérifiés ; aucun UserDefaults personnel |
| Modèles et transaction de pages | Absents de l'archive ; modèle local du destinataire conservé |
| Ancienne bibliothèque | Ancien PDF et ancienne lecture absents |
| Écriture après restauration | Nouvelle note et compteur de carte écrits, fermeture puis réouverture et relecture |
| Traductions/Analysis absents | Anciennes données retirées, rejeu après coupure simulée, fichier de support inconnu conservé |

La sélection `Source` reproduit celle de `LibraryBackupService.source` : les tests Mac ne lancent pas ce service SwiftUI à chemins globaux. Les gardes source existantes de `LibraryRestoreLaunchTests` contrôlent l'ordre de lancement et les exclusions mutuelles ; elles ne sont pas des tests d'interface. Les tests existants de `LibraryBackupTests` couvrent notamment archives invalides, empreintes et SQLite ; ceux de `LibraryRestoreTests` couvrent les coupures par injection d'erreur et le nettoyage différé, pas une coupure matérielle iPad.

Commandes depuis la racine de la branche :

```bash
swift test --package-path Packages/KyokashoKit --disable-automatic-resolution --filter 'LibraryRestoreTests|BackupRoundTripTests/testAppArchive'
swift test --package-path Packages/KyokashoKit --disable-automatic-resolution
python3 -I -m unittest discover -s tests -v
python3 -I scripts/check_documentation.py
git diff --check
```

Compilation iOS : projet généré avec `xcodegen`, `Package.resolved` recopié depuis `Packages/GLMOCRKit`, dépendances locales clonées depuis le lot précédent, sans nouvelle résolution. Commande :

```bash
xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/codex-validation/DerivedData \
  -clonedSourcePackagesDirPath build/codex-validation/SourcePackages \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY=
```

Résultats Mac : test ciblé **7 réussis** ; suite Swift **438 comptabilisés, 431 réussis, 7 ignorés, zéro échec** ; **61 Python réussis** ; **163 liens locaux, zéro erreur** ; diff sans erreur d'espacement. Les 7 ignorés concernent les modèles ONNX/UniDic absents, sans rapport avec la restauration. **Compilation iOS Release générique réussie**, code de sortie 0, `BUILD SUCCEEDED` dans `ios-build.log`. Aucun simulateur ni iPad lancé, aucun paquet de candidate produit.

Journaux locaux dans `build/codex-validation/` (non versionnés), empreintes SHA-256 :

| Journal | SHA-256 |
|---|---|
| `regression-before.log` (échec attendu) | `f577379659fa2f431e6ba385977d2732b6c6bf2b14be01d7f20ab33a7e4e8abf` |
| `backup-focused.log` | `d3251254c752dc71f517d474199eb73ad410b3e62eca2145fb05d0c91539e90b` |
| `swift-tests.log` | `3b43da94833a8c0734e11a3cab5e7d80221f2a5608d7362f87df5ae65a290645` |
| `python-tests.log` | `bf6250e6cf66ce074afc5eaca27d12f42b76339178948a818f2ae8988dfc4646` |
| `ios-build.log` | `aa12b97ed3f40e370b3422a59e53e449c43cbd5ee85619f4e1e51533dd87ab37` |

Les trois fichiers préexistants modifiés (moteur de restauration, ses tests et inventaire documentaire) ont été copiés et comparés avant édition, puis recomparés à la base `15f18a3` avant livraison. Les deux fichiers ajoutés n'avaient pas d'original. Après validation et commit local, les backups doivent être déplacés à la Corbeille sous `2026-11-04-sauvegarde.ktnna9c4`, récupérables (confirmation dans le pont). Aucun fichier de la branche Claude n'est modifié par ce chantier.

## Revue attendue de Claude

Lire le diff depuis `15f18a3`, puis uniquement :

1. `LibraryRestore.swift` : cible optionnelle absente, déplacement vers RestoreOld, rejeu si interruption avant/après déplacement ; aucune suppression d'un autre fichier de support.
2. `LibraryRestoreTests.swift` : la nouvelle régression doit échouer sans le correctif ; les anciens tests de coupure et de nettoyage doivent rester verts.
3. `AppBackupRoundTripTests.swift` : vrais stores, correspondance avec `LibraryBackupService.source`, pools ouverts, assertions de relecture et d'écriture ; ne pas confondre les fichiers IA synthétiques avec une validation de leurs écrans.
4. Le présent rapport et `DONNEES-ET-SAUVEGARDES.md` : preuves Mac, compilation et recette iPad explicitement distinctes.

Aucune intégration dans la branche Claude n'est autorisée par cette livraison seule. Une fusion demandera l'accord précis du manager.

## Recette iPad à faire après revue et candidate autorisée

Non exécutée. Utiliser une installation/bibliothèque de test distincte autorisée, jamais l'unique bibliothèque personnelle. Garder la copie de sécurité hors de cette installation ; ne pas désinstaller l'app personnelle pour cet essai.

1. Préparer un PDF synthétique, une note ancrée avec dessin, repère, surlignage, encre, correction OCR, brouillon, carte avec média et une révision. Ajouter une lecture IA, un chat, une traduction de définition et un petit dictionnaire si disponibles ; noter précisément les éléments non préparés.
2. Choisir un dossier local dans Fichiers et « Sauvegarder maintenant ». Conserver l'archive A et noter la version/build, le nombre de documents/notes/cartes, les textes et l'état de la carte. Les modèles ne sont pas inclus.
3. Modifier une note et ajouter un document témoin. Sélectionner A pour restauration, puis annuler : ces modifications doivent rester. Sélectionner un fichier invalide : refus avant toute modification.
4. Sélectionner A, confirmer, vérifier la présence d'une nouvelle sauvegarde de sécurité de l'état courant dans le dossier choisi. Fermer et rouvrir l'app comme demandé.
5. Vérifier le retour à A : document témoin absent, note et dessins/ancrages justes, OCR corrigé conservé, carte/média/historique lisibles, dictionnaire consultable, fichiers IA accessibles. Modifier une note, réviser une carte, relancer et vérifier la persistance. Vérifier les modèles locaux et les réglages propres à l'appareil.
6. Sur une bibliothèque de test vierge distincte autorisée, créer une archive B avant toute traduction de définition ni lecture IA ; en ajouter ensuite, restaurer B : aucune ancienne traduction/lecture ne doit réapparaître. Sans environnement et archive B réellement préparés, marquer ce cas non testé ; ne pas réinitialiser la bibliothèque personnelle pour l'obtenir.
7. Les essais iCloud/Drive et de grosse bibliothèque se feront séparément ; noter durée, espace disponible et erreurs. Ne pas simuler de coupure en manipulant les fichiers du conteneur personnel.

Noter chaque étape comme réussie/échouée/non faite avec version et capture si utile. Restent non prouvés par Mac : accès au dossier Fichiers/signets, copie de sécurité dans le vrai parcours UI, filtrage effectif des réglages de compte sur appareil, démarrage iPad, rendu Pencil/OCR, interruption réelle, capacité/disque plein et volumes importants.

## Essais sur une bibliothèque séparée

`tools/make_test_tipa.sh <paquet.tipa>` produit une app « Kyōkasho Test », installable à côté de la vraie : autre identifiant, donc autre conteneur et autre bibliothèque. Elle sert à essayer la sauvegarde, la restauration et le retour vers une version antérieure sans toucher aux vraies données.

Retour arrière vérifié sur Mac le 05/11/2026, avec la vraie `AppDatabase` des deux versions, sur une base contenant un PDF, un CBZ et un manga PDF : la 1.4.5 lit les trois documents ; si elle réenregistre les réglages d'un manga PDF, ce document perd sa place dans l'espace Manga au retour, sans autre perte ; le CBZ reste reconnu. Il reste à le refaire sur iPad.

