<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Mémoire, ASan, C++ et Swift

## Distinguer les problèmes

Un accès hors limites ou après libération est une corruption mémoire. Une ressource devenue inutile mais toujours retenue est une fuite ou une rétention indue. Un modèle MLX, ses tensors, un cache GPU ou un fichier projeté peuvent consommer beaucoup de mémoire sans fuite. Un arrêt iOS pour pression mémoire (jetsam) ne prouve pas une corruption.

Dans Kyōkasho, les frontières à surveiller sont MeCab/Swift, extraction UniDic, sessions ONNX, buffers d'images/PDF, tâches et captures Swift, chargement MLX et génération Metal. Le droit `increased-memory-limit` n'est pas une garantie de RAM disponible ; `extended-virtual-addressing` agrandit l'espace d'adressage, pas la RAM physique.

## Outils et portée

| Outil | Utilité | Limite pour ce projet |
|---|---|---|
| AddressSanitizer (ASan) | Accès CPU invalides dans le code instrumenté | Ne remplace pas une recherche de cycles ARC ni une analyse GPU |
| LeakSanitizer (LSan) | Allocations non libérées selon le runtime supporté | Ne pas présumer son support dans Apple Clang ou sur iOS |
| Instruments Allocations/Leaks, Memory Graph | Allocations/rétentions et cycles d'objets | Parcours réellement exercés seulement ; outils appareil à qualifier |
| UBSan pour C/C++ | Certaines opérations au comportement indéfini | Campagne distincte, support selon toolchain |
| ThreadSanitizer | Courses de données CPU | Campagne distincte d'ASan, plateforme supportée à vérifier |
| Outils Metal et métriques MLX | Ressources et travail GPU | ASan CPU ne contrôle pas les accès des kernels Metal |

Les guides officiels [Clang ASan](https://clang.llvm.org/docs/AddressSanitizer.html) et [Clang LSan](https://clang.llvm.org/docs/LeakSanitizer.html) distinguent les cibles supportées. LSan amont cite macOS, mais cela ne garantit pas sa disponibilité dans le compilateur Apple installé, sur une architecture donnée, ni dans une app iOS. Une commande acceptée et un test témoin sont nécessaires avant d'en tirer des conclusions.

## ASan sur les tests Swift et le C++ embarqué — Mac

Commande proposée, avec dépendances déjà résolues :

```sh
swift test --package-path Packages/KyokashoKit \
  --disable-automatic-resolution --scratch-path work/asan-build \
  --sanitize address
```

Utiliser un répertoire de compilation distinct pour séparer les artefacts instrumentés. Vérifier dans le journal que les cibles C/C++ voulues sont recompilées et instrumentées. Les bibliothèques binaires précompilées, notamment certains composants ONNX, ne deviennent pas intégralement instrumentées par cette option. Sans UniDic, le test réel de MeCab peut être ignoré même si tout est compilé.

Commencer par un scénario réduit : créer/détruire l'analyseur, analyser texte vide, Unicode mixte et long, répéter, tester un chemin de dictionnaire invalide et les créations partielles. Fournir un dictionnaire externe autorisé pour les vrais appels. Le succès d'un test CSV ne valide pas le cycle de vie C++.

Pour un exécutable C++ autonome de diagnostic **hors produit**, adapter les fichiers réels :

```sh
xcrun clang++ -std=c++14 -O1 -g -fno-omit-frame-pointer \
  -fsanitize=address diagnostic.cpp -o diagnostic-asan
./diagnostic-asan
```

`diagnostic.cpp` n'est pas un programme existant du dépôt : c'est un harness à écrire pour le composant étudié. Appliquer l'instrumentation à la compilation et au lien, et conserver les symboles. Pour une campagne UBSan, qualifier séparément `-fsanitize=undefined` avec ce harness ; ne pas injecter des drapeaux globaux dans les forks sans test.

## LeakSanitizer sur Mac : qualifier avant d'utiliser

Relever `xcrun clang++ --version` et l'architecture. Compiler un petit témoin C/C++ avec fuite volontaire, hors dépôt produit, avec `-fsanitize=leak`, puis l'exécuter et vérifier un rapport et un code de sortie d'échec. Si le compilateur refuse l'option ou si le runtime ne la prend pas en charge, consigner « non supporté », sans contourner les protections.

Avec une toolchain LLVM dont le runtime ASan intègre LSan pour la cible, `ASAN_OPTIONS=detect_leaks=1` peut activer cette détection. Ce réglage ne suffit pas à ajouter un runtime absent. Pour le Mac Apple, préférer une campagne Instruments/Leaks distincte lorsque LSan n'est pas disponible. Ne pas assimiler une compilation ASan réussie à un contrôle des fuites.

## iOS 16 et TrollStore

Xcode expose ASan dans les diagnostics de schéma ; sa documentation décrit l'activation via `-enableAddressSanitizer YES`. Voir [diagnostic des erreurs mémoire](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early). Exécuter une app instrumentée exige un runtime compatible et un mode de lancement adapté ; le paquet habituel pseudo-signé par ldid ne constitue pas une preuve de compatibilité ASan.

La procédure TrollStore + iOS 16.6.1 n'a pas été qualifiée ici. Ne pas intégrer automatiquement ASan au `.tipa` normal, changer les entitlements pour le forcer ou prétendre que LSan fonctionne sur iOS. Commencer sur Mac ; un essai appareil nécessite l'accord de NOxygen59, un petit binaire témoin, la vérification des runtimes/symboles et une copie de données de test. Aucun simulateur n'est requis ni autorisé implicitement.

## Swift, GPU et répétitions

Pour Swift, inspecter les cycles entre contrôleur, closures, abonnements Combine et tâches. Utiliser Memory Graph et des contrôles de libération ciblés ; un `weak` placé partout peut aussi casser la durée de vie voulue. Les `UnsafePointer`, bridges et fonctions C restent à traiter comme frontières mémoire explicites.

Pour MLX/Metal, mesurer séparément chargement, calcul, fin de génération et attente après déchargement. Les caches GPU et la mémoire unifiée compliquent l'interprétation d'une seule valeur RSS. Les [outils Metal d'Apple](https://developer.apple.com/metal/tools/) complètent les métriques MLX ; disponibilité sur cet iPad à qualifier.

Protocole projet : noter baseline sans modèle, lancer dix fois la même petite page avec le même modèle, attendre la fin et le délai d'inactivité, revenir à la bibliothèque, recommencer après annulation et changement de modèle. Noter mémoire processus, métriques GPU disponibles, nombre de tâches et durée à froid/à chaud. Une hausse continue après les mêmes temps de repos justifie une enquête ; un plateau de cache doit être expliqué, pas automatiquement supprimé.

## Traiter un rapport

Conserver premier accès fautif, pile d'allocation/libération, SHA, toolchain, scénario et journal. Réduire le cas, corriger la propriété ou la borne au bon endroit, ajouter un test de régression et répéter l'essai instrumenté puis normal. Ne pas supprimer le rapport avec une exclusion large ou désactiver les vérifications libc++.

La référence à une « nouvelle faille PHP » ne justifie aucun patch ici : les manifestes examinés concernent Swift/C++/Metal et ne montrent pas de composant PHP. Il faudrait identifier un composant réellement utilisé, une version et une vulnérabilité précise avant de proposer une correction.

**Statut de ce lot :** procédures documentées ; aucune campagne ASan, LSan, Instruments ou GPU du produit n'est déclarée réalisée.
