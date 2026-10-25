<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# CI et livraison prudente

## État et première automatisation

Au commit audité `16d2dd8`, aucun workflow GitHub Actions n'est versionné. Cela ne prouve pas l'absence de contrôles externes ; seulement l'absence de pipeline défini dans ce dépôt.

Ce lot ajoute un contrôle documentaire léger : `.github/workflows/documentation.yml` lance `scripts/check_documentation.py` sur les changements de Markdown et sur ses propres fichiers. Le script contrôle les destinations locales des liens Markdown, sans accès réseau et sans exécuter l'app. Un contrôle local réussi ne prouve pas qu'une exécution GitHub Actions a déjà eu lieu.

## Pipeline recommandé, à qualifier par étapes

| Étape | Déclenchement conseillé | Preuve et critère |
|---|---|---|
| Liens et diff | PR/documentation | Aucun lien local invalide, `git diff --check` propre |
| Tests package Mac | PR de code, après qualification d'un runner | Sept cibles compilées, zéro échec, ignorés comptabilisés |
| ASan CPU | Manuel puis périodique | Runtime qualifié, code C++ reconstruit, scénarios mémoire exécutés |
| Compilation iOS générique | PR touchant App, manifestes, forks ou projet | Succès sans signature ; révisions figées ; aucune exécution appareil |
| Tests réels OCR/MLX | Mac autorisé et équipé | Assets externes licites, versions/mesures et résultats gardés hors logs publics |
| Recette iPad | Version candidate demandée | NOxygen59 renseigne les scénarios pertinents de TESTS.md |
| Livraison | Demande explicite avec numéro | Tag, paquet, notes, UUID/dSYM et révisions cohérents |

Les jobs Mac et ASan sont ici une stratégie, pas des workflows prétendument installés et verts. Qualifier d'abord le runner, sa version Xcode/Swift, l'architecture et les dépendances ONNX. Un runner `macos-latest` change avec le temps ; choisir ensuite une image et une version Xcode connues, en enregistrant les versions réelles.

Les tests de package ne sont pas tous purement algorithmiques : Vision, CoreGraphics, PDFKit et binaires ONNX peuvent dépendre du runner. Les vrais tests de modèles ne doivent pas être obligatoires par défaut sur chaque PR.

## Garde-fous du futur workflow Mac

Permissions minimales `contents: read`, aucun secret nécessaire aux tests publics de logique, pas de signature ou installation. Dépendances issues des résolutions versionnées, sans mise à jour opportuniste ; clé de cache incluant OS/architecture/toolchain et les deux `Package.resolved`. Conserver le code de sortie natif et publier les journaux même en échec. Vérifier la provenance des actions et épingler les actions tierces.

Ne pas exposer les PDF, modèles sous conditions d'accès, conversations, journaux privés ou tokens dans les artefacts. La visibilité du dépôt observée pendant cet audit est publique : ne pas déduire la confidentialité d'une ancienne phrase du README.

Pour l'app générique, reprendre la procédure du [guide développeur](GUIDE-DEVELOPPEUR.md), en contrôlant que la résolution de l'app provient bien du package GLMOCRKit. Un job d'archive ne doit ni créer une release automatiquement ni modifier `latest.json` à chaque push.

## Contrôle avant intégration

Lire le diff ; distinguer production, tests et documents. Vérifier l'absence de données tierces. Associer les résultats au SHA testé, signaler ce qui est ignoré et les étapes non exécutées. Un échec de test préexistant découvert pendant l'audit doit être décrit, puis corrigé dans un périmètre compréhensible ou suivi comme blocage ; il ne faut pas l'effacer des logs.

## Livraison demandée par NOxygen59

La procédure historique détaillée reste au § 5 de la feuille de route. Ordre recommandé : figer le code, exécuter les contrôles, préparer la note « Modifications / Vérifié / Non vérifié », puis attribuer seulement le numéro demandé. Construire le `.tipa` avec `build_ipa.sh`, garder archive et dSYM exacts, vérifier le paquet, créer tag/release, puis mettre à jour l'avis du dépôt auxiliaire selon la procédure existante.

Dans une fiche de livraison, conserver : SHA/tag, version/build, versions Xcode/Swift, révisions des deux forks, hachage SHA-256 du `.tipa`, UUID arm64 du binaire/dSYM, commandes et résumé des résultats, anomalies ouvertes et retour iPad. Ne pas écraser la seule archive utile à un crash encore non symbolisé.

L'installation et les essais iPad sont faits par NOxygen59. Une version candidate publiée n'est pas automatiquement confirmée. Un correctif ultérieur exige de nouvelles preuves sur son propre périmètre.

## Retour arrière

Pour ce lot : retirer les ajouts documentaires/workflow et revenir aux deux anciennes lignes de test si nécessaire ne change pas les données de l'app. Pour un futur changement de schéma, il faut une sauvegarde compatible et une procédure de restauration ; revenir au tag précédent ne suffit pas toujours.
