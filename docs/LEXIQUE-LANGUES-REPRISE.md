<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Lexique multilingue — livraison locale du 04/11/2026

## État et périmètre

Lot autorisé par NOxygen59, sur `codex/lexique-langues`, base `15f18a3`, worktree `/Users/noxygen/.codex/worktrees/kyokasho-lexique-langues/wt-rotation`. La reprise explicite remplace les anciennes pauses : anglais complet, chinois limité aux équivalents littéraux selon sa consigne. Traductions rédigées directement par Codex, sans moteur local ni service externe. Aucun push, fusion, changement de version, dépendance, CI ou paquet candidat.

Objectif : conserver les lexiques FR/EN/zh-Hans séparément et utiliser la variante de la langue réellement appliquée après relancement. Invariants : termes et lectures japonais, tags, scores, séquences, liens, attribution et avertissements IA ; archive française inchangée, dictionnaires personnels et profils conservés. Acceptation locale : archives complètes, vrai import et recherche après réouverture d'une base jetable, tests, compilation iOS. La revue Claude et la recette utilisateur restent distinctes.

## Archives hors dépôt

Dossier : `/Users/noxygen/Projets-iPad/dictionnaires-construits/lexique-interieur/`.

| Fichier | Contenu | SHA-256 |
|---|---|---|
| `lexique-interieur.zip` | Français original, 3 836 entrées, révision 2026-11-04.2, inchangé | `b67f8143495796b9dc86438be216504fe203dd757965d8f8e1ebb004782ff3da` |
| `lexique-interieur-en.zip` | 3 836 entrées ; 8 121 textes source uniques couverts, définitions françaises et extraits japonais compris | `cad7b2d984ec020a587b413da8c6d83a087273533a219d1febdec93d005b5bb2` |
| `lexique-interieur-zh-Hans.zip` | 3 836 équivalents courts, sans définition, liens et notices conservés | `417926897e92f7528dbd2dccb9bfa60a20a495ffe44ab7aa88d6b6003f662913` |

Titres des variantes EN/zh-Hans distincts, mises à jour en place par titre ; aucune suppression de l'autre langue. Révisions `2026-11-04.2.en.1` et `2026-11-04.2.zh-Hans.1`. Le français garde son titre historique.

Provenance reproductible dans le dossier externe `traductions-2026-11-04/` : source gelée `source-fr-2026-11-04.2.zip`, liste `texts.json`, cache lié au SHA source `codex-direct.json`, lots `codex-direct/en-001.tsv` à `en-046.tsv`. Les 200 définitions prioritaires sont traduites. Réutilisation contrôlée de 1 053 titres anglais déjà associés aux titres français dans les mêmes entrées (`source-title-pairs.json`), et de 42 variantes textuelles équivalentes et non ambiguës (`exactTextAliases`). Anciens brouillons automatiques `traductions-2026-11-04.json` exclus.

## Comportement du code

- `DictionaryCatalog.swift` : choix selon `Bundle.main.preferredLocalizations`, chinois sur Mac/Catalyst seulement ; variantes inactives exclues des recherches sans modifier activation, ordre ou profils.
- `DictionaryModel.swift` : filtre appliqué aux recherches, segmentation, préfixes et disponibilité des termes.
- `DictionaryCatalogService.swift` : propose localement la variante manquante si une autre est déjà importée, avant l'échéance réseau hebdomadaire ; choix conservé par langue, anciennes propositions d'autres langues retirées.
- `build_ipa.sh` et `tools/copy_bundled_lexicons.py` : FR/EN dans iOS ; helper Mac FR/EN/zh-Hans ; chemin français personnalisé historique conservé. Les variantes absentes sont signalées, pas substituées.
- `tools/localize_domain_lexicon.py` : refuse cache incomplet, SHA source différent ou écrasement ; vérifie conservation des champs et liens.
- `tools/import_lexicon_translations.py` : import atomique des lots directs, contrôles des indices, doublons et conflits.

La branche Mac de Claude est plus récente et distincte. **Le helper sait préparer les ressources Mac ; son appel dans le vrai script de paquet Mac doit encore être intégré par Claude lors de sa revue.** Aucune fusion dans son worktree. La base de ce lot ne permet pas de prouver une compilation Catalyst.

## Preuves du 04/11

Journaux locaux : `build/codex-validation/`, non versionnés.

- `swift-tests.log` : **439 comptabilisés, 432 réussis, 7 ignorés, 0 échec**, avec `KYOKASHO_TEST_LEXICONS` explicitement fourni.
- Le test `DictionaryCatalogTests.testRealBundledArchivesImportAndReopenWhenProvided` importe les vrais trois ZIP dans une base disque jetable, rouvre la base, contrôle 3 × 3 836 termes, lecture japonaise, sens FR/EN/zh-Hans et filtre réel de `Translator`. Il est ignoré si les archives externes ne sont pas fournies.
- `python-tests.log` : **67 tests réussis**.
- `ios-build.log` : **BUILD SUCCEEDED**, Release générique iOS, sans signature, simulateur ou appareil lancé, sans résolution/mise à jour des dépendances.
- Vérificateur sur les deux vrais ZIP : champs japonais et séquences, liens, notices IA et attribution conservés ; SHA français identique à la source gelée.
- Copie des vrais ZIP dans des dossiers temporaires : iOS exactement FR/EN, Mac exactement FR/EN/zh-Hans.
- 162 liens documentaires examinés, zéro erreur ; `git diff --check` réussi.

Commandes de contrôle :

```sh
KYOKASHO_TEST_LEXICONS=/Users/noxygen/Projets-iPad/dictionnaires-construits/lexique-interieur swift test --package-path Packages/KyokashoKit --disable-automatic-resolution
python3 -I -m unittest discover -s tests -v
python3 -I scripts/check_documentation.py
git diff --check
```

## Revue ciblée pour Claude

Lire ce document puis seulement le diff depuis `15f18a3` ; ne pas relire tout le vault.

1. **Conservation et langue** : `DictionaryCatalog.swift`, `DictionaryModel.swift`, les trois nouveaux tests de `DictionaryCatalogTests.swift`. Importer les trois archives puis vérifier qu'une seule variante apparaît dans les recherches, sans désactiver un dictionnaire personnel ni changer un profil enregistré.
2. **Propositions de mise à jour** : `DictionaryCatalogService.swift`, transitions FR → EN → FR, « Plus tard », suppression d'une variante, vérification manuelle et hebdomadaire. Le paquet local doit être vérifié même lorsque le réseau n'est pas dû.
3. **Paquets** : `build_ipa.sh`, `copy_bundled_lexicons.py`, tests Python. Préserver l'override français et exclure le chinois d'iPad ; brancher le helper dans le paquet Mac sur la branche Mac actuelle avant d'annoncer l'intégration Mac.
4. **Traductions** : cache externe + lots TSV, échantillons techniques, unités et lois. La couverture et le format ne prouvent pas l'exactitude linguistique. La source contient déjà des fragments, notices hors domaine et erreurs : par exemple Portland stone décrit comme marbre (indice 6556), larvikite comme minéral (6629), et un résidu de modèle `{{{2}}}` dans un extrait tronqué (7308). Traduction fidèle de ces limites, sans correction générale implicite. Décider séparément d'un nettoyage du corpus français puis régénérer les variantes si nécessaire.

## Recette utilisateur restante

Sur une future candidate autorisée, avec bibliothèque de test :

1. Français : importer le lexique, chercher un terme d'architecture ; noter les dictionnaires/profils actifs.
2. Passer l'app en anglais et la relancer : vérifier la proposition locale, importer, chercher le même terme. Les deux lexiques restent listés et seul l'anglais est recherché.
3. Revenir au français : résultat français, ordre et dictionnaires personnels conservés ; tester refus puis vérification manuelle de la proposition.
4. Sur Mac uniquement après intégration du paquet : chinois court disponible ; aucune définition chinoise détaillée attendue.
5. Sur iPad : absence du ZIP chinois. Vérifier également segmentation et suggestions de préfixe.

**Non testé** : interface réelle Mac/iPad, cycle utilisateur de changement de langue et alertes, paquet Mac réellement signé, revue linguistique indépendante, revue Claude. Pas de candidate construite dans ce lot.

Six originaux sauvegardés et comparés avant édition : dossier `2026-11-04-lexique.v4zpnupt`, initialement dans `/Users/noxygen/Documents/Codex/Kyokasho-Backups/`. Les six fichiers ont été recomparés octet par octet à la base Git `15f18a3`, puis le dossier a été déplacé avec `/usr/bin/trash` à la Corbeille après les contrôles réussis, conformément à la consigne du manager. Aucune suppression définitive.
