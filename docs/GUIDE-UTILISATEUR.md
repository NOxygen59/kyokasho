<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Guide utilisateur — Kyōkasho v1.3

Kyōkasho sert à lire des manuels PDF japonais, les annoter, comprendre leur texte et réviser le vocabulaire. L'app est conçue pour l'iPad Pro 12,9 pouces M1, 8 Go, iOS 16.6.1, TrollStore. Les fonctions décrites sont présentes dans le projet ; leur validation réelle est précisée dans [l'audit](AUDIT-V1.3.md). Le support d'autres appareils n'est pas établi.

## 1. Installer et commencer

1. Utiliser le `.tipa` d'une release choisie par NOxygen59 sur [GitHub](https://github.com/NOxygen59/kyokasho/releases). Ouvrir le fichier avec TrollStore puis installer. Cette procédure ne décrit pas l'installation de TrollStore ou du jailbreak.
2. Avant une mise à jour importante, exporter les documents et données utiles ; un export PDF ne sauvegarde pas toute l'app. Voir [sauvegardes](DONNEES-ET-SAUVEGARDES.md).
3. Ouvrir Kyōkasho, importer un petit PDF d'essai depuis Fichiers. Choisir la langue avant l'import : Japonais pour un manuel japonais, Automatique pour un document mixte que l'on ne veut pas normaliser comme du japonais.
4. Ouvrir le document. Commencer par la lecture et les annotations, puis installer les outils japonais et modèles nécessaires depuis les Réglages. Tous les gros modèles ne sont pas requis pour lire un PDF.

Le premier téléchargement exige une connexion et du stockage libre. Les durées et la mémoire dépendent du modèle et de la page ; les vitesses Mac publiées dans le projet ne sont pas des promesses de vitesse sur iPad.

## 2. Bibliothèque et import

L'import copie le PDF dans la bibliothèque locale. Garder aussi le fichier source dans Fichiers. La recherche aide à retrouver un livre ; son menu d'appui long donne notamment accès aux opérations de document. L'intégration Google Drive permet un import après connexion ; elle ne constitue pas une sauvegarde complète et automatique des notes et cartes.

Le menu du livre propose « Ajouter des pages… », « Supprimer des pages… » et « Exporter… ». « Exporter… » → « Paquet Kyōkasho (tout le document) » crée un fichier `.kyokasho` à ouvrir dans Kyōkasho sur un autre appareil (Importer → « Importer un paquet Kyōkasho », ou toucher le fichier dans Fichiers : il porte l'icône de Kyōkasho et s'ouvre dans l'app) : le document revient avec ses notes, surlignages, dessins, OCR corrigé, lectures IA, traductions, analyse et brouillons, sans rien relancer. Les cartes, les conversations et les réglages de l'app ne sont pas inclus ; les dictionnaires manquants sont signalés. Si le document existe déjà, Kyōkasho demande avant de le remplacer et garde l'ancienne version dans Fichiers → Kyōkasho → Paquets de sécurité. « Supprimer des pages… » (aussi : corbeille au-dessus de la bande des pages du lecteur, qui ferme le livre) : choisir des pages une à une ou « de … à … », puis confirmer. Les pages supprimées restent restaurables 30 jours depuis la même fenêtre, avec leurs notes, dessins, OCR, analyses et brouillons ; ce qui a été fait entre-temps est gardé. « Effacer » (sur une suppression) ou « Effacer toutes les copies » libère la place tout de suite ; ces pages ne sont alors plus restaurables. Une restauration efface d'elle-même les copies devenues inutiles. Les cartes de révision liées restent, sans page, et retrouvent leur page à la restauration. Les numéros imprimés des autres pages ne bougent pas. Les liens « Pages consultées » du chat suivent leur page, ou disparaissent avec une explication si la page n'existe plus. Après un remplacement du PDF depuis Drive, les anciennes suppressions ne sont plus restaurables. Essayer d'abord sur un document de test. Pour réunir plusieurs PDF, utiliser l'outil de fusion et vérifier l'ordre avant l'enregistrement. L'ajout à un livre existant déplace aussi des données liées aux pages : commencer sur une copie de travail et contrôler le nombre de pages, les repères, notes et cartes après l'opération. Une observation intermittente d'ajout tardif figure dans l'historique ; sa cause n'est pas démontrée. Éviter de répéter immédiatement l'ajout sans vérifier le résultat.

Le bandeau « Continuer » reste une idée de la feuille de route : ce guide ne le présente pas comme livré.

## 3. Lire et annoter

Dans le lecteur, « … » → « Pagination et réglages de ce document » → « Pages », choisir « Automatique selon l'orientation », « Page simple » ou « Double page ». Le mode Auto adapte la présentation à la place et à l'orientation ; les réglages du document peuvent remplacer les réglages généraux. Utiliser les boutons de page et la pellicule pour naviguer. Le sens de lecture et les zones de toucher influencent le changement de page.

Le lecteur propose zoom, thèmes et fonds de page. Réglages → Apparence → Thèmes : choisir d'abord un **style** (Atelier, Neo-Brutalism, Glassmorphism, Synthwave, Swiss Design, Wabi-Sabi), qui change formes, bordures, ombres et polices de toute l'app, lecteur compris, et propose sa palette ; puis, si besoin, une autre **palette** (sombres, Clair, Sépia…). Les pages du manuel ne changent jamais. Glassmorphism floute les panneaux : plus joli, un peu plus gourmand en batterie. Les hauteurs des pages sont égalisées automatiquement lorsqu’elles diffèrent ; aucun interrupteur ne désactive cette égalisation. Si un rendu gêne la lecture, comparer « Page simple » et « Double page » ; ce changement ne supprime pas l’égalisation. Les gestes ont déjà subi un retour arrière après un essai jugé mauvais sur iPad ; signaler précisément doigt/Pencil/trackpad, orientation et niveau de zoom lors d'un problème.

Les annotations comprennent surlignages, dessins Pencil et notes flottantes ancrées. Faire une note d'essai, fermer puis rouvrir le livre pour vérifier sa conservation. Sur un ancien document aux pages de tailles différentes, contrôler l'alignement avant d'utiliser un export annoté : un risque est consigné dans la feuille de route.

## 4. La « fenêtre OCR »

C'est le panneau d'étude, pas un moteur de reconnaissance. Ses onglets donnent accès au texte, au dictionnaire, aux notes, aux repères et au chat. Il peut être ancré, détaché, agrandi ou réduit en pastille. Dans les réglages de lecture, les options de conservation du zoom et d'animation permettent d'adapter les changements de fenêtre.

En double page, vérifier la page de travail sélectionnée dans le panneau avant de lancer une lecture, une correction ou une création de cartes. Une page visible et une page sélectionnée pour l'étude peuvent être différentes.

## 5. Reconnaître le texte et afficher les furigana

Deux traitements se complètent :

| Traitement | Produit | Utilité |
|---|---|---|
| OCR géométrique : texte PDF, NDLOCR, PP-OCRv5, Apple Vision | Texte avec positions sur la page | Toucher un mot, sélection, superposition et furigana |
| Lecture IA OvisOCR2 | Texte de page en Markdown | Texte mis en forme, comparaison, chat et référence pour les lectures |

En mode OCR Auto, le service préfère la couche texte PDF disponible, puis NDLOCR, PP-OCRv5 et Vision selon disponibilité. Le lecteur traite aussi les scans dont la couche cachée est inutilisable. Un PDF photographié peut n'avoir aucune couche texte : c'est normal que la reconnaissance soit nécessaire.

Installer MeCab/UniDic pour l'analyse japonaise et importer ses dictionnaires Yomitan dans l'espace Dictionnaire. Activer les furigana sur la page via le bouton dédié ou les options d'affichage ; le panneau texte propose aussi ses lectures. Les deux affichages ne prouvent pas que chaque lecture est juste. Un mauvais mot peut venir du scan, de l'alignement ou de l'analyse japonaise.

La lecture automatique OvisOCR2 se règle dans Réglages → Japonais et traduction → Reconnaître le texte des pages → section « Lecture IA du document » → « Lire les nouvelles pages avec OvisOCR2 ». Le titre de cet écran est « Texte des pages ». Elle réutilise les pages déjà lues. Changer la langue du livre ne relit pas les anciennes pages automatiquement ; utiliser « Rescanner »/la relecture de la page pour obtenir une nouvelle sortie avec la consigne courante. La normalisation japonaise v1.3 corrige notamment `图` en `図`, sans convertir arbitrairement tous les caractères ni effacer les chiffres et formules.

## 6. Corriger et analyser

Depuis le panneau Texte, « Corrections IA » ouvre les différences proposées ; « Rescanner » demande une nouvelle lecture de la page. Comparer les propositions avec le PDF original avant acceptation. Les lignes retouchées à la main sont protégées par le pipeline de correction ; effacer les résultats OCR peut néanmoins supprimer ces retouches.

L'analyse du document compare plusieurs lectures et propose une indication de fiabilité. Plusieurs moteurs d'accord peuvent avoir tort : le score n'est pas une certification. L'acceptation de corrections sur tout le document réutilise les lectures existantes et exclut certains cas, dont les lignes éditées et les formules. Une relecture invalide l'ancien vote de la page ; il faut refaire l'analyse pour une nouvelle comparaison.

Pour une erreur de chiffre, d'unité, de kanji ou de formule, garder le PDF comme référence. Les tableaux et le japonais vertical restent des zones à vérifier.

## 7. Dictionnaire, lexique et cartes

L'espace Dictionnaire est accessible depuis la bibliothèque et le lecteur. Chercher un mot ou sa lecture, consulter les fiches, gérer les dictionnaires et retrouver les éléments enregistrés. Sur la page, toucher/survoler un mot reconnu ouvre sa recherche ; si le mauvais composé est choisi, comparer le texte OCR à la page.

Le lexique personnel ajoute des termes du domaine et aide plusieurs traitements. Il ne remplace pas un dictionnaire général et n'améliore pas rétroactivement toutes les pages déjà traitées.

Les cartes de révision utilisent FSRS. Créer une carte depuis un mot ou les termes trouvés sur la page, vérifier lecture et sens, puis réviser depuis l'espace Cartes. L'export `.apkg` permet un transfert vers Anki ; tester l'import de quelques cartes avant un transfert complet. L'export n'est pas une synchronisation bidirectionnelle.

## 8. Chat et traduction

Le chat du manuel utilise les pages déjà lues par OvisOCR2. Ouvrir l'onglet Chat, choisir la conversation du livre et poser une question précise. Une question « p. 6 » est interprétée selon les étiquettes de page du livre : vérifier que le repère correspond à la page voulue. Si cette page n'a pas été lue, lancer sa lecture plutôt qu'attendre une réponse inventée.

Ouvrir les pages citées pour vérifier la réponse. Une citation montre une source consultable, pas une garantie de fidélité. Qwen3-VL et Qwen3.5 sont proposés selon installation ; Qwen3.5-4B reste sans validation iPad documentée à la base v1.3.

La traduction locale Qwen d'une page (panneau Texte → ✨) se fait en **français ou en anglais** : la petite pastille FR / EN à côté du bouton choisit la langue. Chaque langue garde ses propres fichiers ; les traductions françaises déjà faites restent. Le lexique du domaine n'est imposé qu'à la traduction française (ses sens sont en français). « Analyser le document » propose de traduire tout le document dans chaque langue, et l'export Markdown inclut les deux traductions quand elles existent. La même fenêtre propose « Supprimer la traduction en anglais / en français » : seules les pages traduites dans cette langue sont effacées de l'appareil (les lectures OvisOCR2, l'analyse et l'autre langue restent ; on peut retraduire plus tard). Relire une page avec OvisOCR2 efface ses traductions, devenues fausses.

La traduction locale Qwen et l'option DeepL sont différentes : DeepL envoie le texte à un service distant. Le glossaire aide la terminologie, sans garantir le sens. Vérifier les termes techniques, nombres et unités.

## 9. Activité IA, stockage et effacement

Les pastilles IA affichent chargement, travail, attente ou modèle chargé. Les tâches longues peuvent continuer lorsque l'on change de page ou ferme le lecteur ; cela ne garantit pas une exécution illimitée quand iOS suspend l'app. Ouvrir le détail pour consulter progression et arrêt. L'arrêt est confirmé ; attendre la fin avant de relancer une opération identique.

Le suivi du stockage distingue PDF, modèles, dictionnaires, analyses et caches. Effacer les caches régénérables diffère d'effacer les résultats OCR. Lire l'avertissement : les corrections manuelles appartiennent aux résultats OCR. Ne pas supprimer l'app pour « nettoyer » sans sauvegarde vérifiée.

Les modèles se déchargent selon l'activité, mais une mémoire élevée ne prouve pas une fuite. En cas de fermeture brutale, noter le modèle, la page et les opérations en cours ; voir [débogage](DEBOGAGE.md).

## 10. Exporter et demander de l'aide

Bibliothèque → appui long sur le livre → « Exporter… » propose « PDF d'origine », « PDF annoté », « Texte (Markdown) », « Images PNG (zip) » et « Cartes Anki (.apkg) ». Pour un PDF annoté : choisir « PDF annoté », régler les pages ou toucher « Tout le document », puis « Exporter ». Après préparation, toucher « Partager <nom du fichier> », enregistrer dans Fichiers via la feuille de partage iOS et ouvrir le résultat dans une autre app. Vérifier texte japonais, ordre, annotations et notes. Les exports ne sont pas interchangeables avec une sauvegarde intégrale.

Pour signaler un problème : version/build, étapes, résultat attendu, résultat observé, page, modèle, orientation et périphérique utilisé. Le chemin est Réglages → Aide et informations → Aide au diagnostic → Mode diagnostic. L’activation enrichit le journal sans ajouter d’indicateur dans le lecteur : aucun changement visuel n’est nécessairement perceptible. Les erreurs restent notées même désactivé. Reproduire une fois, consulter « Voir le journal », puis ne partager qu’un extrait relu et expurgé des données personnelles. Un rapport iOS `.ips` est utile pour un plantage. Batterie (#20) : même écran → « Relevé de batterie » note chaque minute le niveau, la chaleur et ce que fait l'app ; « Voir le résumé » donne le % de batterie par heure de chaque activité (lecture, IA, analyse). Mesurer avec une luminosité fixe, iPad débranché, au moins 15 minutes par activité. Ne jamais fournir mot de passe ou jeton ; un petit PDF synthétique reproduisant le problème est préférable à un manuel personnel complet.

## Glossaire

OCR : reconnaissance du texte d'une image. Furigana : lectures kana près des kanji. Markdown : texte avec balises de mise en forme. Modèle : fichiers de poids d'un moteur IA. Cache : donnée recalculable, à distinguer des retouches. Build : numéro d'une compilation. `.tipa` : paquet installé avec TrollStore. ASan : outil développeur de détection d'accès mémoire invalides, pas un bouton de réparation de l'app.
