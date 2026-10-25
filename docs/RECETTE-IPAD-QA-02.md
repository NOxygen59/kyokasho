<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# QA-02 — recette iPad PageShift et sauvegarde

**Préparation du 25 octobre 2026 ; aucun essai iPad effectué.** Base étudiée : `f83aec8c61d88f1e6c119376590899c9c1ce2876` (PR #1 à #6 fusionnées). Agent : Codex. Autorisation : demande de NOxygen59 dans le chat du 25/10, préparation et PR uniquement, sans build, bibliothèque personnelle, release ni GitHub Actions.

## 1. But et règle de départ

Vérifier que l'ajout de pages conserve les contenus sur leur bonne page, même avec de l'OCR en cours, puis qualifier séparément la sauvegarde/restauration. **Cette fiche n'autorise pas encore les essais.** La version v1.3/build 40 ne contient pas les correctifs PageShift des PR #2/#3 : noter le SHA de la future build, pas seulement son nom de version.

Périmètre : protocole et fiches de résultats ; aucun changement du code, des dépendances, des formats ou de la version. Invariants : PDF original conservé hors app, notes/encre/repères/OCR/cartes attachés au même contenu, aucune donnée personnelle utilisée ou publiée. Acceptation de cette préparation : scénarios exécutables, attentes vérifiables, blocages explicites et suivi GitHub prêt. Clôture de QA-02 : résultats réels datés par build, avec limites et anomalies ; aucune case n'est cochée par anticipation.

### Deux niveaux à ne pas mélanger

| Niveau | Ce qui est permis après accord | Conditions |
|---|---|---|
| A — essais ordinaires, sans enjeu pour les données personnelles | Import, annotation, ajout de pages, OCR, export des seuls documents synthétiques | Installation et conteneur de test isolés et vérifiés ; A0 réussi |
| B — restauration et incidents | Extraction d'un conteneur, copie hors ligne, réimport sur iPad, éventuelle interruption volontaire | Autorisation distincte et procédure qualifiée ; section 6 |

Un dossier « QA » dans la bibliothèque habituelle **n'isole pas** ses bases ni ses réglages. Ne pas désinstaller l'app personnelle, vider sa bibliothèque ou installer par-dessus pour obtenir un terrain de test. Aucun second conteneur ou bouton de changement de bibliothèque n'est supposé exister. Si l'isolation n'est pas démontrée, **A0 est bloqué et les essais iPad attendent**. La préparation des fichiers synthétiques sur Mac reste possible.

## 2. Préparer les documents sans données personnelles

À faire sur Mac dans un nouveau dossier local `QA02-synthetique`, hors dépôt et hors dossier synchronisé. Aucun téléchargement de livre, image, dictionnaire ou modèle. Aucun PDF, même synthétique, à committer. Les fichiers ne sont pas fournis par cette PR documentaire : les fabriquer ainsi, ou faire préparer ce même lot avant les essais.

1. Dans Pages (ou un traitement de texte déjà installé), partir d'un document **vierge**. Utiliser des sauts de page, du texte noir de grande taille, et uniquement les textes ci-dessous. Ajouter un carré et une croix dessinés avec les formes de l'éditeur sur chaque page ; ils serviront de cibles pour l'encre et la note. Exporter en PDF dans ce dossier, sans mot de passe ni commentaire.
2. Créer `BASE-4.pdf` : quatre pages, marquées en grand `BASE-01`, `BASE-02`, `BASE-03`, `BASE-04`. Sous chaque marque, écrire respectivement `ALPHA 111 日本語`, `BETA 222 図`, `GAMMA 333 学校`, `DELTA 444 本`. Ces marques imprimées restent fixes même si le numéro de page change.
3. Créer `AVANT-2.pdf` : `AVANT-01 / PREFIXE 901`, puis `AVANT-02 / PREFIXE 902`. Créer `APRES-2.pdf` : `APRES-01 / SUITE 801`, puis `APRES-02 / SUITE 802`.
4. Créer `SCAN-4.pdf` : ouvrir BASE-4, capturer **seulement l'intérieur de chaque page**, une image par page ; ni bureau, ni barre de compte, ni nom de fichier personnel. Placer chaque image seule sur une page d'un nouveau document vierge, puis exporter en PDF. Vérifier dans Aperçu que le texte de ces pages ne se sélectionne pas ; sinon refaire l'export image. Contrôler les quatre marques et leur ordre. Cette variante force un vrai travail OCR, contrairement au PDF texte.
5. Créer `MIXTE-4.pdf` dans Aperçu : copier les quatre pages de BASE-4, remplacer la deuxième par une version exportée au format A5, tourner la troisième de 90°. Garder les marques BASE-01 à BASE-04. Vérifier dimensions différentes et rotation avant de sauvegarder une **nouvelle copie**.
6. Créer `LONG-256.pdf` : dupliquer SCAN-4 dans un nouveau fichier. Dans les vignettes d'Aperçu, sélectionner toutes les pages, copier puis coller **après la dernière** pour doubler le nombre. Répéter six fois : 4 → 8 → 16 → 32 → 64 → 128 → 256. Vérifier le total et le motif BASE-01…BASE-04 répété. Noter la taille réelle dans Finder. Cette variante teste beaucoup de pages ; si elle reste petite en octets, elle ne valide pas les copies d'un PDF lourd.
7. Pour la variante lourde, refaire les quatre images à plus haute résolution et exporter sans réduction de qualité, puis répéter l'étape 6. Viser au moins 50 Mo comme charge d'essai, **pas comme limite produit**. Si ce lot n'est pas disponible, marquer « gros fichier en octets : non essayé ». Ne pas gonfler le fichier avec des données personnelles ni remplir le disque pour atteindre une taille.

Garder ces originaux hors de l'app. Sur le Mac, relever le nombre de pages, la taille et, si accompagné par l'agent, `shasum -a 256` de chaque PDF. Le SHA permet de retrouver exactement le corpus, sans publier le PDF. Les propriétés d'un PDF peuvent contenir le nom du compte créateur : ces fichiers restent locaux et ne sont pas joints aux Issues.

## 3. A0 — préparer la session autorisée

1. Faire confirmer la build et le conteneur jetable isolé. Une sauvegarde Mac seule ne démontre pas qu'on pourra récupérer la bibliothèque personnelle sur iPad.
2. Noter date, modèle d'iPad, version iOS, version/build **et SHA**, espace libre, moteurs disponibles et mode diagnostic. Pas de numéro de série, identifiant de conteneur ou compte.
3. Dans le conteneur de test seulement, désactiver la lecture automatique Ovis dans les réglages « Texte des pages » pour A1/A2/A4. Choisir un affichage Simple, égalisation désactivée, puis importer uniquement BASE-4 et une seconde copie nommée `TEMOIN` avec le même contenu. Ne pas connecter Drive ou un service de traduction.
4. Sur BASE-02, ajouter une note `NOTE-BETA`, un repère, un trait Pencil sur le carré et un surlignage sur `BETA`. Sur BASE-04, placer `NOTE-DELTA` à la croix. Sur BASE-04, dans le panneau Texte, obtenir l'OCR et retoucher une ligne en `CORRECTION-QA02` en choisissant « Brut », furigana désactivés, puis appui long sur la ligne → « Corriger cette ligne » → saisir le texte → « Garder ». Noter le moteur. Ne plus relancer cette page pour les essais de conservation.
5. Si les outils déjà présents le permettent, créer depuis 図 une carte avec lecture `ず` et sens `figure QA02`, puis faire une seule révision. Noter le nombre de cartes, la page source et l'échéance affichée. Si l'édition OCR ou les cartes ne sont pas accessibles, noter cette sous-vérification « bloquée », sans installer de ressources implicitement.
6. Sur TEMOIN, ajouter seulement `TEMOIN-INCHANGE` en page 2. Fermer puis rouvrir les deux livres ; vérifier déjà les annotations. Cette référence permet de distinguer un défaut antérieur d'un décalage provoqué par l'ajout.

Repères de manipulation : pour une note, panneau « Notes » → saisir le texte → « Ajouter » ; toucher ensuite la note, puis son bouton cible d'ancrage et la croix sur la page. Le bouton « Signet » du lecteur marque la page ; l'onglet « Repères » permet de la retrouver. Pour le surlignage, sélectionner le mot sur le PDF par appui long puis choisir une couleur dans le menu de surlignage. Pour l'encre, dessiner au Pencil sur le carré. Si un contrôle n'est pas présent dans la build autorisée, consigner le libellé réellement affiché et bloquer la sous-vérification, sans inventer un parcours.

**Attendu :** 4 pages par livre, tous les repères corrects. Sinon arrêter A1 et signaler A0. Les numéros ci-dessous commencent à **1**, comme les pages visibles, et non à 0 comme certains journaux techniques.

## 4. Niveau A — essais utilisateur ordinaires

Faire A1 puis A2 sur le même livre BASE. Pour A3/A4/A5, réimporter une copie neuve avec un nom distinct ; ne pas poursuivre sur un livre déjà en anomalie. Après chaque opération, attendre la fin, revenir à la bibliothèque puis rouvrir. Ne pas répéter un ajout parce qu'il semble lent.

### A1 — ajouter à la fin

1. Appui long sur BASE → « Ajouter des pages… » → « Choisir des PDF » → APRES-2.
2. Laisser le document actuel en premier. Vérifier l'annonce de 2 pages ajoutées puis toucher « Ajouter 2 pages » **une seule fois**. Attendre « Pages ajoutées », puis « OK ».
3. Parcourir les six pages et vérifier les notes, le dessin, le surlignage, le repère, la correction OCR et la carte préparés en A0. Ouvrir aussi TEMOIN.

**Attendu :** BASE-01, BASE-02, BASE-03, BASE-04, APRES-01, APRES-02. NOTE-BETA reste en p. 2, NOTE-DELTA en p. 4 ; aucune carte en double, échéance inchangée sans nouvelle révision, TEMOIN inchangé. Après réouverture : toujours 6 pages.

### A2 — ajouter avant et contrôler le décalage une seule fois

1. Sur le livre à 6 pages issu de A1, refaire « Ajouter des pages… », choisir AVANT-2.
2. Avec la poignée de déplacement de la liste, placer AVANT-2 **au-dessus du document actuel entier**. L'écran doit annoncer 2 pages avant le document. Il ne permet pas ici de couper l'ancien livre en deux.
3. Ajouter une fois, attendre la fin, puis vérifier cette table. Fermer et rouvrir deux fois le livre sans nouvel ajout.

| Contenu imprimé | Page après A1 | Page après A2 | À retrouver |
|---|---:|---:|---|
| AVANT-01, AVANT-02 | absent | 1, 2 | Aucune ancienne annotation ni texte BASE |
| BASE-01 | 1 | 3 | ALPHA 111 |
| BASE-02 | 2 | 4 | NOTE-BETA, repère, encre, surlignage et carte |
| BASE-03 | 3 | 5 | GAMMA 333 |
| BASE-04 | 4 | 6 | NOTE-DELTA et CORRECTION-QA02 |
| APRES-01, APRES-02 | 5, 6 | 7, 8 | SUITE 801/802 |

**Attendu :** 8 pages après chaque réouverture ; annotation toujours sur le carré/la croix du même contenu, jamais décalée une deuxième fois ; texte OCR associé à la bonne marque. TEMOIN reste à 4 pages. Le lien source de la carte doit ouvrir BASE-02, désormais p. 4. Si une donnée n'est pas visible dans l'interface, noter « non observable », pas « conservée ».

### A3 — OCR concurrent : deux essais distincts

**A3a — OCR géométrique (Apple Vision, sans modèle téléchargé).**

1. Importer SCAN-4 sous un nom neuf, ou LONG-256 si le traitement est trop rapide. Désactiver Ovis automatique ; choisir Apple Vision comme moteur du livre. Relever le total N (4 ou 256).
2. Dans le panneau Texte, démarrer « Lire tout le document » ou utiliser le menu du moteur → « Relancer » sur une page image. Pendant l'indication de traitement, revenir à la bibliothèque et tenter l'ajout de AVANT-2 avant le livre. Noter si le traitement était encore visible au départ et si le retour a annulé l'OCR.
3. Laisser terminer sans autre commande, puis comparer les pages 1 à 6 et les deux dernières. Réouvrir le livre, lancer ensuite l'OCR des nouvelles pages si nécessaire.

**Attendu :** l'ajout peut attendre l'OCR déjà lancé ; aucun texte ancien ne doit être enregistré sur AVANT-01/02. Le total est N+2 ; BASE-01 commence p. 3. Le moteur peut mal reconnaître un caractère : consigner cette erreur séparément d'un texte complet placé sur la mauvaise page. Un cache absent peut être recalculé après l'ajout ; ce n'est pas une preuve de perte d'une correction manuelle.

**Preuve de concurrence :** le retour bibliothèque peut annuler la tâche, et le moteur peut terminer avant l'ajout. Dans ce cas inscrire « concurrence non reproduite » ; une réussite du parcours ne suffit pas. Au plus trois tentatives sur des copies neuves, puis transmettre cette limite. Les tests automatisés du résultat tardif restent la preuve contrôlée ; l'interface seule ne montre pas le moment exact de l'écriture.

**A3b — lecture IA Ovis (uniquement si déjà disponible et autorisée).**

1. Sur une nouvelle copie SCAN-4, lancer « Rescanner » depuis Texte. Pendant la pastille de lecture IA, retourner à la bibliothèque et tenter d'ajouter AVANT-2.
2. **Attendu :** refus explicite demandant d'attendre ou d'arrêter la lecture IA ; le livre reste à 4 pages. Ce refus est le comportement attendu, pas un bug.
3. Attendre la fin de la lecture, puis refaire l'ajout. Attendu : 6 pages, lecture BASE attachée aux pages 3 à 6 ; aucun texte BASE sur les pages AVANT. Si traduction ou rapport existaient avant, vérifier leur page et leur texte sans les régénérer.

Modèle absent, lecture terminée avant la tentative ou retour qui l'arrête : « bloqué » ou « non reproduit » selon le cas, jamais « réussi ». Aucun téléchargement de poids, appel distant ou essai de chat n'est nécessaire à cette recette.

### A4 — annotations, rotation, pages mixtes et export (risque DATA-03)

1. Importer MIXTE-4, affichage Simple et égalisation désactivée. Sur la petite BASE-02 et la BASE-03 tournée, tracer un trait sur le carré, poser une note sur la croix et un surlignage sur la marque. Photographier mentalement ou capturer seulement la page synthétique pour comparer.
2. Passer en Double et activer « Égaliser les pages ». Vérifier les trois annotations, tourner l'iPad portrait/paysage, zoomer puis revenir à la page entière. Revenir en Simple sans égalisation pour comparer.
3. Ajouter AVANT-2 devant ce livre, puis refaire les observations : petite page en p. 4, page tournée en p. 5. Fermer puis rouvrir.
4. Bibliothèque → appui long → « Exporter… » → PDF annoté, toutes les pages. Enregistrer dans le dossier de test et ouvrir dans Aperçu ou Fichiers. Comparer les positions sur les carrés/croix et les pages des notes ; une page récapitulative de notes peut s'ajouter à l'export.

**Attendu :** même ancrage visuel avant/après, bonne page et aucune annotation perdue. Un décalage déjà visible avant PageShift est un résultat DATA-03 à signaler séparément. Un affichage correct n'implique pas un export correct : renseigner deux résultats. Ce risque est ouvert ; aucune réussite n'est promise.

### A5 — beaucoup de pages, puis gros fichier en octets

1. Importer LONG-256, Ovis automatique désactivé. Noter sa taille exacte, l'espace libre et l'heure. Comme marge de campagne, garder au moins 5 Go libres **et** cinq fois la taille cumulée des PDF concernés ; ce repère prudent n'est pas une garantie de suffisance. Sinon reporter, sans effacer de données pour faire de la place.
2. Mettre un repère et une note `FIN-256` sur la dernière page, puis une note `DEBUT-1` sur la première. Ajouter AVANT-2 devant une seule fois ; chronométrer jusqu'à la fin et noter les pauses de l'interface.
3. Vérifier 258 pages : AVANT-01/02 en p. 1/2, DEBUT-1 en p. 3, FIN-256 en p. 258. Vérifier aussi les pages 4, 5, 6 et 130 (motif BASE-04 à la p. 130). Réouvrir deux fois et vérifier les liens des repères.
4. Relever espace libre après et durée. Les copies de secours PageShift restent conservées : une hausse de stockage est attendue ; ne pas les purger. Refaire sur une copie du lot ≥ 50 Mo si LONG-256 est plus petit, et consigner séparément taille/durée/résultat.

**Attendu :** total exact et annotations conservées ; aucune fermeture de l'app. On mesure les ralentissements, sans seuil de vitesse prétendument validé. Si l'écran reste sans progrès apparent pendant deux minutes, noter l'heure et demander conseil ; ne pas forcer l'arrêt ni relancer l'ajout. Manque d'espace, alerte de reprise ou crash : arrêter cette session et suivre la section 5.

## 5. Quand arrêter

Une note sur la mauvaise page, une perte de contenu, un total inattendu, un blocage de reprise ou un crash arrête les mutations sur ce livre. Noter le dernier geste et le texte de l'alerte, conserver les sources et le conteneur jetable dans leur état, puis ouvrir une anomalie avec la fiche ci-dessous.

Ne pas effacer `page-shift.json`, les copies PageShift, les caches ou les résultats OCR pour « débloquer ». Ne pas revenir à l'ancien binaire : il ne sait pas reprendre le journal v2. Ne pas forcer une interruption, couper l'alimentation, remplir le disque ou injecter un journal corrompu sur iPad. Les tests de pannes Mac couvrent plusieurs de ces situations sans enjeu pour la bibliothèque.

## 6. Niveau B — sauvegarde/restauration : garde d'autorisation

**B0 — bloqué tant que la méthode iPad n'est pas qualifiée.** Il n'existe pas de bouton de sauvegarde intégrale dans l'app ajouté par ces travaux. L'outil `tools/backup_container.py` tourne sur Mac à partir d'une copie du conteneur. Il n'extrait ni ne réinstalle un conteneur TrollStore. Ne pas improviser de chemin système, de droits ou de commande d'écrasement.

Avant B1, faire consigner et approuver :

- l'identité de l'installation jetable et la preuve qu'elle ne partage pas la bibliothèque personnelle ;
- la méthode précise d'arrêt de l'app et des écritures, d'extraction complète de `Documents/` et `Library/`, puis de réimport avec droits/protections iOS compatibles ;
- la build et le schéma compatibles, les chemins locaux source/destination vérifiés, l'espace nécessaire, et une copie de constat intacte ;
- la marche à suivre en cas d'échec, sans désinstaller ni remplacer l'app personnelle ;
- l'accord explicite de NOxygen59 pour l'extraction puis, séparément, pour le réimport. Tout essai d'interruption volontaire demanderait encore un accord et un protocole propres ; il n'est pas proposé ici.

**B1 — sauvegarde puis restauration dans un dossier Mac neuf (accompagné par l'agent).** Après A2 réussi, relever les 8 pages et toutes les données de la table A2, les cartes/échéances, les lectures IA présentes et un réglage visuel de test. Attendre la fin des tâches, arrêter l'app suivant la méthode approuvée, puis exporter le seul conteneur synthétique complet. Préserver cette copie originale. Aucun journal PageShift en attente : s'il existe, l'outil doit refuser, sans qu'on le supprime.

Sur cette copie hors ligne seulement, appliquer les trois commandes de [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md#utilisation-sur-une-copie-de-test), avec chemins explicitement vérifiés. Dossiers parents existants, destinations inexistantes. `--source-stopped` est une attestation humaine, pas une détection de l'arrêt. Garder les trois codes de sortie : backup, verify, restore doivent tous être 0. Vérifier le manifeste et ses exclusions. La restauration publie `destination/container` ; elle ne doit jamais écraser un dossier existant.

**Attendu :** empreintes/inventaire et contrôles SQLite valides, source intacte. Caches et temporaires exclus ; modèles inclus sauf omission explicitement choisie. Trousseau, connexions, droits iOS et installation ne sont pas restaurés par l'outil. Une erreur arrête B1 ; ne pas passer B2 en ignorant l'alerte.

**B2 — réimport et contrôle iPad, autorisation distincte.** Seulement après B1 réussi et méthode approuvée, réimporter le résultat dans l'installation jetable prévue. NOxygen59 ouvre le livre, refait toutes les observations A2 et vérifie en plus la carte, son échéance sans révision supplémentaire, les lectures IA existantes et le réglage visuel. Ajouter `APRES-RESTAURATION` sur BASE-02 (p. 4), fermer puis rouvrir : la note doit persister. Contrôler TEMOIN. Noter explicitement les fonctions non essayées (modèles, dictionnaires, connexions, historique FSRS non observable).

B1 réussi sur Mac ne valide pas B2. Une carte visible ne prouve pas à elle seule tout l'historique FSRS ; le test Swift vérifie cet état interne. QA-02/DATA-02 restent ouverts tant que B2 manque. Aucun succès synthétique n'autorise automatiquement une restauration de données personnelles.

## 7. Consigner dans GitHub sans données personnelles

Ouvrir une Issue de campagne via **New issue → Tâche**, titre `QA-02 — recette iPad — build …`, et y copier la fiche ci-dessous ; lier la PR de préparation. Aucun workflow n'est requis. Utiliser un commentaire par session ; un agent signe `[Codex]` ou `[Claude]`, NOxygen59 écrit en son nom. Ouvrir une Issue séparée par anomalie et reporter son lien dans le tableau. Ne pas créer de fausse campagne exécutée : les résultats initiaux sont « non essayé ».

```text
QA-02 — session [identifiant neutre, date]
Build / SHA :
iPad (modèle seulement) / iOS :
Isolation approuvée et vérifiée : oui / non ; référence de l'accord :
Corpus : noms synthétiques, pages, tailles, SHA-256 si disponible
OCR / modèles déjà présents ; Ovis automatique activé ou désactivé :
Diagnostic : activé / désactivé ; espace libre avant / après :
Autorisation niveau A : référence / absente
Autorisation B1 puis B2 : références séparées / absentes

Scénario | Statut | Attendu / observé | Durée | Anomalie liée
A0 | non essayé | | |
A1 | non essayé | | |
A2 | non essayé | | |
A3a | non essayé | concurrence réellement observée ? | |
A3b | non essayé | refus IA puis ajout après fin ? | |
A4 affichage | non essayé | | |
A4 export | non essayé | | |
A5 256 pages | non essayé | | |
A5 gros octets | non essayé | taille exacte : | |
B0 qualification | bloqué | méthode à approuver | |
B1 Mac | non essayé | backup/verify/restore, 3 codes : | |
B2 iPad | non essayé | réouverture et nouvelle écriture : | |
Sous-vérifications absentes (cartes, retouches, traductions…) :
Décision : poursuivre / arrêter ; prochaine action autorisée :
```

Statuts : **réussi**, **échoué**, **bloqué**, **non essayé**, **non reproduit** (concurrence non obtenue). Un scénario partiel garde ses sous-vérifications manquantes visibles. Chaque nouvelle build a ses propres résultats ; ne pas recopier les réussites anciennes comme nouvelles.

```text
Titre : [QA-02][A2] Note synthétique sur une mauvaise page
Session / build / SHA :
Corpus synthétique et état initial :
Gestes exacts (1, 2, 3) :
Attendu :
Observé (marque imprimée ET numéro de page) :
Fréquence : … fois sur … essais ; reproductible / inconnu
Impact : perte ou corruption / blocage / affichage / lenteur
Arrêt des essais : oui / non ; dernière opération terminée :
Lien de campagne :
Pièce minimale relue et expurgée, sinon description textuelle :
```

**Avant Publier :** relire titre, texte et pièces. Aucun PDF, sauvegarde, base SQLite, manifeste complet, journal brut, `.ips`, chemin de compte, UUID d'appareil/conteneur, clé ou jeton. Privilégier les marques BASE/AVANT et un court message d'erreur retranscrit sans chemin. Une capture doit cadrer seulement la page synthétique, sans notifications, noms de comptes ou autres livres. Ne pas exporter les anciens diagnostics de l'app personnelle. Les pièces brutes restent locales ; demander un extrait précis et expurgé si nécessaire.

## 8. Preuves disponibles et risques ouverts

Voir [TESTS.md](TESTS.md) pour le relevé actuel. Sources inspectées : les deux fichiers de tests PageShift, le test BackupRoundTripTests, les 16 tests Python et les interfaces AddPagesView/StudyPanel. Les tests de panne ne demandent pas de les reproduire manuellement sur iPad.

Restent ouverts : concurrence réelle de l'interface et autres écritures différées ; rendu PDFKit/annotations et export après égalisation (DATA-03) ; temps/mémoire/espace des grands PDF ; copies PageShift conservées ; anciens journaux ambigus ; coupure matérielle non démontrée ; extraction/réimport TrollStore, protections iOS et comportement des préférences. La campagne ne qualifie ni tous les modèles MLX/Metal ni toutes les bibliothèques possibles.
