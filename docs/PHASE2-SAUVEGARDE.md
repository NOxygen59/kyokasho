<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Sauvegarde cohérente — outil hors ligne et preuve de restauration

## Périmètre

Ce lot ajoute un outil développeur Python sans dépendance tierce, `tools/backup_container.py`, et des tests. Il ne modifie pas le comportement de l'app ni son interface, n'extrait pas le conteneur d'un appareil, ne s'exécute pas sur l'iPad et ne touche pas à la bibliothèque de NOxygen59. Les tests emploient exclusivement des conteneurs synthétiques temporaires.

Il prend en entrée une **copie exportée du conteneur, app arrêtée**, contenant `Documents/` et `Library/`. Les bases essentielles attendues sont `Library/Application Support/Kyokasho/kyokasho.sqlite` et `Library/Application Support/Kyokasho/Review/review.sqlite`. Une méthode réelle d'export/import du conteneur TrollStore sur iOS 16.6.1 reste à qualifier avec NOxygen59 ; aucun accès automatique n'est ajouté.

## Inventaire et exclusions explicites

| Catégorie | Contenu | Politique de l'outil |
|---|---|---|
| Persistant essentiel | PDF, base app : annotations, dessins, repères, OCR retouché, réglages | Inclus |
| Révisions | Base Review, cartes, planification FSRS, historique, médias | Inclus ensemble |
| Japonais | Bases et ressources dictionnaires, lexique personnel, UniDic | Inclus ; UniDic peut suivre l'exclusion facultative du dossier Models |
| IA | Lectures brutes, traductions, rapports, conversations | Inclus, sans recalcul ni normalisation |
| Préférences | `Library/Preferences` et autres fichiers persistants exportés | Inclus |
| Modèles | Poids et métadonnées présents dans Models | Inclus par défaut ; option d'exclusion déclarée au manifeste |
| Diagnostic | Journal local dans Documents | Inclus ; sauvegarde personnelle, pas artefact CI public |
| Régénérable | `Library/Caches`, `tmp` | Exclus et consignés au manifeste |
| État transactionnel inachevé | `page-shift.json` | Sauvegarde logique refusée ; conserver une copie de constat et réparer d'abord |
| Hors conteneur | Trousseau, connexions, droits, TrollStore/jailbreak | Non sauvegardé ; reconnexion et installation séparées |

L'outil copie les contenus de fichiers, pas les protections iOS, attributs étendus, ACL, métadonnées d'installation ou une image complète de l'appareil. Il n'ajoute ni chiffrement ni synchronisation. Les liens symboliques sont refusés. Ce périmètre évite de présenter un simple export PDF ou un dossier de bases isolé comme une sauvegarde intégrale des usages.

## Cohérence des bases

Pour chaque fichier SQLite reconnu, l'API SQLite `backup` capture aussi les transactions validées encore dans le WAL. Le résultat est converti en base autonome ; les fichiers `-wal`/`-shm` ne sont pas copiés comme des bases indépendantes. `integrity_check` et `foreign_key_check` doivent réussir. Les autres fichiers sont copiés sans transformation, avec taille et SHA-256 au manifeste.

L'arrêt des écritures est une **précondition**, attestée explicitement par `--source-stopped`. La comparaison des inventaires et des dates/tailles des fichiers et WAL détecte des modifications pendant la copie, mais ne remplace pas un verrou global entre bases, fichiers et préférences : ne pas utiliser l'outil sur un conteneur actif. Il ne prétend pas reconnaître par magie si une app iPad distante est arrêtée.

La restauration vérifie tout l'inventaire et les empreintes avant copie, contrôle les bases, recopie vers un dossier temporaire privé puis vérifie les fichiers copiés. Elle publie uniquement un nouveau dossier `destination/container`. Elle refuse toute destination déjà existante : jamais de restauration directement au-dessus d'une bibliothèque. Un manifeste garantit une cohérence vérifiable, pas l'authenticité d'une archive modifiée avec son manifeste.

## Utilisation sur une copie de test

```sh
python3 tools/backup_container.py backup /copie/conteneur /nouveau/dossier-sauvegarde --source-stopped
python3 tools/backup_container.py verify /nouveau/dossier-sauvegarde/backup
python3 tools/backup_container.py restore /nouveau/dossier-sauvegarde/backup /nouveau/dossier-restauration
```

Les chemins sont à adapter ; les dossiers parents doivent exister et les destinations doivent être absentes. La sauvegarde est dans `dossier-sauvegarde/backup`, le conteneur restauré dans `dossier-restauration/container`. `--omit-models` exclut uniquement `Library/Application Support/Kyokasho/Models` et consigne cette omission. Sans cette option, les poids sont inclus, ce qui peut être volumineux.

Ne pas recopier le résultat sur l'iPad avant qualification de la procédure de restauration, des permissions, de la version de schéma et des connexions. Aucun retour arrière de version d'app n'est effectué par l'outil.

## Tests exécutés

```sh
python3 -m unittest discover -s tests -v
swift test --package-path Packages/KyokashoKit --disable-automatic-resolution --filter BackupRoundTripTests
```

14 tests Python passent : WAL, contenus persistants, omissions annoncées, source non arrêtée, opération PageShift en attente, bases essentielles manquantes, fichier altéré/absent, WAL inattendu, destination existante, lien symbolique, chemin invalide, erreur de copie et mutation de source. Une erreur ne publie pas un faux conteneur restauré et n'efface pas les données sources.

Un test Swift supplémentaire utilise les **véritables AppDatabase et ReviewStore**, avec leurs migrations réelles : PDF synthétique, notes ancrées et dessin, encre, surlignage, repère, résultat OCR retouché, carte FSRS, historique, média, lectures IA, conversations, lexique et préférences synthétiques. Les pools sont fermés avant copie. Après sauvegarde et restauration, les vraies bases sont rouvertes, contenus/positions/état FSRS vérifiés, puis une nouvelle note est écrite et retrouvée après une nouvelle ouverture.

La première comparaison du test a révélé un artefact de précision des dates du fixture (Date natif contre représentation SQLite), pas une perte de sauvegarde ; le fixture emploie désormais une date de référence exacte. Aucun changement des formats applicatifs n'en découle. Le runner Swift 6.1.2 exige aussi deux conversions explicites `CGFloat` → `Double` dans un tuple d'OCRModels, implicitement acceptées par Swift 6.4. L'ajustement conserve les mêmes valeurs et le même algorithme, sans nouvelle API ni dépendance. Les deux assertions de test OCR obsolètes sont alignées sur `results`, comme dans #1, pour compiler la suite sans changer l'app.

## Renforcement DATA-02 — 28 octobre 2026 (Issue #83)

Tests ajoutés sans modifier l'outil : inventaire des données récentes et garde-fou d'inventaire (Swift), noms japonais et Unicode, fichiers vide, gros ou en lecture seule, SIGKILL réel pendant la sauvegarde et la restauration, limite du manifeste (Python), restauration et migration d'une base au schéma `v3-page-one` (Swift). Détail et résultats : [TESTS.md](TESTS.md), section DATA-02.

Constats documentés, sans correctif : après un arrêt brutal, le dossier privé `.partial-…` reste à côté de la destination et peut contenir des données personnelles ; une destination réservée vide refuse la relance au même chemin. **Reprise :** mettre le dossier `.partial-…` à la corbeille, puis relancer vers un chemin neuf (ou après avoir mis à la corbeille la destination vide). Les copies `PageShift/<UUID>` conservées après chaque ajout de pages sont incluses dans la sauvegarde et peuvent l'alourdir. Les permissions des fichiers ne sont pas restaurées : seuls les contenus le sont.

## Limites et prochaines validations

### Complément de revue indépendante — 25 octobre 2026

Une reproduction synthétique a montré que des fichiers ordinaires `notes-wal`, `notes-shm` et `notes-journal` étaient omis silencieusement dès qu'un fichier `notes` existait, même si celui-ci était un simple texte. L'inventaire ne traite désormais un fichier comme annexe SQLite que si son fichier principal est une base SQLite et si l'annexe porte la signature attendue du journal WAL, du fichier partagé ou du journal de rollback. Les autres fichiers entrent dans l'inventaire et sont vérifiés/restaurés comme tout contenu persistant. Des tests contrôlent les trois noms ordinaires ainsi que l'incorporation des vrais fichiers WAL et SHM dans la copie SQLite autonome.

Une annexe suspecte près d'une vraie base reste soumise aux contrôles d'intégrité SQLite : cette correction ne transforme pas une archive incohérente en restauration sûre. La condition `--source-stopped` reste obligatoire ; elle n'est pas vérifiable automatiquement par cet outil.

Sur la branche corrigée : 16 tests Python exécutés sans échec, dont les deux nouvelles régressions ; le test Swift de restauration avec les vraies bases et leur réouverture passe également. Les essais restent synthétiques et Mac/Linux ; aucun conteneur personnel ou iPad n'a été utilisé.

L'essai valide le cycle de données synthétiques sur Mac, pas une réinstallation sur l'iPad. Le rendu des annotations, l'ouverture des modèles, la réauthentification des comptes et les permissions de conteneur après import restent à vérifier. Les fichiers de préférences d'essai servent à prouver leur conservation octet pour octet ; ils ne valident pas tous les comportements UserDefaults d'iOS.

Avant une fonction de sauvegarde dans l'app : mécanisme de mise au repos de toutes les écritures, inventaire partagé des données, écran explicitant les exclusions, tests d'interruption supplémentaires et recette iPad autorisée sur une copie. Le présent outil constitue une preuve et un point de départ révisable, pas une promesse de restauration universelle TrollStore.
