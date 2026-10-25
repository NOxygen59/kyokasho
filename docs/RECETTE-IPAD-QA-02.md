<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# QA-02 — recette iPad PageShift et sauvegarde

**Préparation du 25 octobre 2026 ; aucun essai iPad effectué.** Base étudiée : `f83aec8c61d88f1e6c119376590899c9c1ce2876` (PR #1 à #6 fusionnées). Agent : Codex. Autorisation : demande de NOxygen59 dans le chat du 25/10, préparation et PR uniquement, sans build, bibliothèque personnelle, release ni GitHub Actions.

## Fiche courte — commencer par A0, A1 et A2

À utiliser lors de la future session autorisée, pas pendant cette correction documentaire.

1. **A0 :** NOxygen59 accepte la perte éventuelle des données actuelles pour le niveau A sur son installation existante. Garder hors app les originaux utiles ; exporter soi-même les annotations importantes si nécessaire (ce n'est pas une sauvegarde intégrale). Attendre l'autorisation de build/installation et la fiche d'identification décrite en section 3. **Ne pas revenir à l'ancien binaire v1.3 après les essais.**
2. **Préparer :** Réglages → Japonais et traduction → Reconnaître le texte des pages → section « Lecture IA du document » → désactiver « Lire les nouvelles pages avec OvisOCR2 ». Attendre la fin des tâches déjà lancées. Importer les PDF synthétiques sous des noms `QA02-…` ; ne pas ouvrir les livres réels pour ces essais.
3. **Affichage :** lecteur → « … » → « Pagination et réglages de ce document » → « Pages » → « Page simple ». L'égalisation des tailles est automatique ; aucun interrupteur n'est à chercher.
4. **A1 :** sur `QA02-BASE`, appui long → « Ajouter des pages… » → « Choisir des PDF » → APRES-2, laissé après le livre → « Ajouter 2 pages » une fois → « Pages ajoutées » → « OK ». Attendu : 6 pages ; notes toujours en pages 2 et 4.
5. **A2 :** même menu, choisir AVANT-2 puis le glisser au-dessus du livre. Ajouter une fois. Attendu : 8 pages ; NOTE-BETA en page 4, NOTE-DELTA en page 6, même résultat après deux réouvertures.
6. **Arrêter** à la première perte, mauvaise page, alerte de reprise ou fermeture inattendue. Consigner le résultat avec la fiche de section 7 ; aucun journal brut ni document personnel sur GitHub. Le niveau B reste bloqué.

Les sections suivantes détaillent la préparation, puis les essais complémentaires A3–A5 et la restauration B.

## 1. But et règle de départ

Vérifier que l'ajout de pages conserve les contenus sur leur bonne page, même avec de l'OCR en cours, puis qualifier séparément la sauvegarde/restauration. **Décision de NOxygen59 (chat du 25/10/2026) : il accepte le risque de perdre les données actuellement présentes et autorise le principe du niveau A sur l’installation existante.** Cette mission reste documentaire : aucune build ni installation ni exécution des essais maintenant. La release historique v1.3/build 40 ne contient pas les correctifs PageShift ; une future compilation des sources actuelles pourrait pourtant afficher le même « 1.3 (40) ». L’identification externe de section 3 est donc nécessaire.

Périmètre : protocole et fiches de résultats ; aucun changement du code, des dépendances, des formats ou de la version. Invariants : PDF original conservé hors app, notes/encre/repères/OCR/cartes attachés au même contenu, aucune donnée personnelle utilisée ou publiée. Acceptation de cette préparation : scénarios exécutables, attentes vérifiables, blocages explicites et suivi GitHub prêt. Clôture de QA-02 : résultats réels datés par build, avec limites et anomalies ; aucune case n'est cochée par anticipation.

### Deux niveaux à ne pas mélanger

| Niveau | Ce qui est permis après accord | Conditions |
|---|---|---|
| A — essais ordinaires, risque de perte accepté par NOxygen59 | Import, annotation, ajout de pages, OCR, export des seuls documents synthétiques | Installation existante admise, précautions A0 ; build/installation à autoriser avant exécution |
| B — restauration et incidents | Extraction d'un conteneur, copie hors ligne, réimport sur iPad, éventuelle interruption volontaire | Autorisation distincte et procédure qualifiée ; section 6 |

Un préfixe `QA02-` distingue les livres d'essai mais **n'isole pas** les bases ou réglages : le risque pour les données déjà présentes demeure, et NOxygen59 l'accepte pour A seulement. Une seconde app n'est plus un prérequis. Cette décision ne permet ni d'effacer la bibliothèque, ni de manipuler ses fichiers, ni de restaurer son conteneur. L'agent ne consulte ni ne modifie les fichiers personnels pendant cette mission.

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

**Ne pas réinstaller l'ancien binaire v1.3 après les essais : il ne sait pas reprendre un journal PageShift v2.** Ne pas désinstaller l'app ni vider sa bibliothèque pour préparer A.

1. Avant la future installation, NOxygen59 garde lui-même hors de Kyōkasho les PDF originaux qu'il souhaite conserver. Si des annotations comptent, il peut en faire un export PDF annoté (chemin exact en A4) ; cet export ne sauvegarde pas les cartes, les corrections OCR et tout l'état de l'app. Si ces précautions ne suffisent plus à son acceptation du risque, reporter la session. Relever l'espace libre. Aucun export personnel n'est à communiquer à l'agent ou à GitHub.
2. Après accord explicite de build et d'installation, la mise à jour de l'installation existante avec le même identifiant sera le parcours à vérifier ; la conservation des livres par TrollStore n'est pas garantie par cette recette. NOxygen59 vérifie leur présence après installation, sans les utiliser comme corpus. Si des livres manquent ou si une reprise est signalée, arrêter A0. Noter les preuves externes de build ci-dessous, date, modèle d'iPad, iOS, espace libre, moteurs et état du diagnostic ; aucun numéro de série, compte ou identifiant de conteneur.
3. Dans **Réglages → Japonais et traduction → Reconnaître le texte des pages**, section « Lecture IA du document », noter l'état initial puis désactiver **« Lire les nouvelles pages avec OvisOCR2 »** pour A1/A2/A3a/A4/A5. Attendre la fin de toute lecture déjà lancée : l'interrupteur empêche les nouveaux départs automatiques, il n'annule pas une tâche active. Dans le lecteur, « … » → « Pagination et réglages de ce document » → « Pages » → **« Page simple »**. Importer BASE-4 sous le nom `QA02-BASE` et une copie `QA02-TEMOIN`. Dans la suite, BASE et TEMOIN désignent ces deux livres synthétiques. Préfixer aussi chaque autre livre d'essai `QA02-` ; ne pas connecter Drive ou un service de traduction.
4. Sur BASE-02, ajouter une note `NOTE-BETA`, un repère, un trait Pencil sur le carré et un surlignage sur `BETA`. Sur BASE-04, placer `NOTE-DELTA` à la croix. Sur BASE-04, dans le panneau Texte, obtenir l'OCR et retoucher une ligne en `CORRECTION-QA02` en choisissant « Brut », furigana désactivés, puis appui long sur la ligne → « Corriger cette ligne » → saisir le texte → « Garder ». Noter le moteur. Ne plus relancer cette page pour les essais de conservation.
5. Si les outils déjà présents le permettent, créer depuis 図 une carte avec lecture `ず` et sens `figure QA02`, puis faire une seule révision. Noter le nombre de cartes, la page source et l'échéance affichée. Si l'édition OCR ou les cartes ne sont pas accessibles, noter cette sous-vérification « bloquée », sans installer de ressources implicitement.
6. Sur TEMOIN, ajouter seulement `TEMOIN-INCHANGE` en page 2. Fermer puis rouvrir les deux livres ; vérifier déjà les annotations. Cette référence permet de distinguer un défaut antérieur d'un décalage provoqué par l'ajout.

**Pourquoi couper la lecture automatique ?** Ovis peut lire les pages manquantes à l'import et à l'ouverture ; `AddPagesView.apply()` appelle aussi `DocumentScan.start()` après un ajout. Si le réglage est actif et le modèle installé, un travail IA peut donc partir sans autre geste, bloquer l'ajout suivant et brouiller la comparaison avant/après des textes ou des durées. On sépare ainsi les essais de conservation des lectures IA. Le réglage est global et affecte aussi les livres existants ; ne pas les ouvrir pendant la session. A3b déclenche volontairement « Rescanner » avec le modèle déjà disponible, sans avoir besoin de réactiver la lecture automatique.

**Identifier la future build sans changer sa version.** L'écran Réglages → Aide et informations → À propos et mises à jour affiche version et build, **pas le SHA**. `project.yml` reste à 1.3 / 40 : aucun numéro ne change sans autorisation de NOxygen59. Lors d'une future build autorisée, l'agent consigne sur Mac le SHA source complet (`git rev-parse HEAD`), un arbre de sources propre (`git status --porcelain` vide), la date, le nom et la taille du fichier `.tipa`, et son empreinte (`shasum -a 256` sur ce fichier). Conserver cette fiche et le fichier exact hors dépôt, sans l'écraser lors d'une compilation suivante. Avant installation, vérifier l'empreinte du fichier destiné au transfert ; NOxygen59 note qu'il a sélectionné ce fichier et le résultat de l'installation. Version affichée seule ou SHA source seul ne prouvent pas quel binaire a été installé. En cas de doute sur le fichier choisi, A0 reste bloqué. Ces preuves sont externes : rien ne les affiche automatiquement dans l'app.

**Diagnostic facultatif :** Réglages → Aide et informations → Aide au diagnostic → **Mode diagnostic** (également accessible par la recherche « diagnostic »). L'activer n'ajoute pas d'indicateur dans le lecteur et ne produit pas forcément de changement visuel : il enrichit le journal. « Voir le journal » est sur le même écran ; les erreurs sont notées même sans ce mode. Les tests A reposent sur les pages observées et peuvent se faire sans diagnostic. Le journal de l'installation existante peut contenir des informations personnelles antérieures : ne pas le publier brut.

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

1. Importer SCAN-4 sous un nom neuf, ou LONG-256 si le traitement est trop rapide. Garder « Lire les nouvelles pages avec OvisOCR2 » désactivé suivant A0 ; choisir « Apple Vision » dans le menu du moteur du panneau Texte. Relever le total N (4 ou 256).
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

1. Importer MIXTE-4 sous un nom `QA02-…`, puis choisir « Page simple » par le chemin A0. L’égalisation est automatique lorsque les hauteurs diffèrent ; le risque DATA-03 concerne donc aussi cet affichage, sans option à désactiver. Sur la petite BASE-02 et la BASE-03 tournée, tracer un trait sur le carré, poser une note sur la croix et un surlignage sur la marque. Photographier mentalement ou capturer seulement la page synthétique pour comparer.
2. Au même endroit, choisir « Double page ». Vérifier les trois annotations, tourner l’iPad portrait/paysage, zoomer puis revenir à la page entière. Revenir à « Page simple » pour comparer. Noter la disposition effectivement affichée : l’adaptation au portrait peut montrer une seule page. Cette comparaison ne désactive jamais l’égalisation automatique.
3. Ajouter AVANT-2 devant ce livre, puis refaire les observations : petite page en p. 4, page tournée en p. 5. Fermer puis rouvrir.
4. Bibliothèque → appui long sur le livre `QA02-…` → « Exporter… » → section « Format » : « PDF annoté » → « Tout le document » → « Exporter ». Attendre la préparation, puis toucher « Partager <nom du fichier> » (le nom réel remplace ce texte). Dans la feuille de partage iOS, enregistrer dans Fichiers, dans le dossier de test ; ouvrir le résultat dans Fichiers sur iPad ou dans Aperçu sur Mac. Comparer les positions sur les carrés/croix et les pages des notes ; une page récapitulative de notes peut s'ajouter à l'export.

**Attendu :** même ancrage visuel avant/après, bonne page et aucune annotation perdue. Un décalage déjà visible avant PageShift est un résultat DATA-03 à signaler séparément. Un affichage correct n'implique pas un export correct : renseigner deux résultats. Ce risque est ouvert ; aucune réussite n'est promise.

### A5 — beaucoup de pages, puis gros fichier en octets

1. Importer LONG-256 sous un nom `QA02-…`, « Lire les nouvelles pages avec OvisOCR2 » toujours désactivé suivant A0. Noter sa taille exacte, l'espace libre et l'heure. Comme marge de campagne, garder au moins 5 Go libres **et** cinq fois la taille cumulée des PDF concernés ; ce repère prudent n'est pas une garantie de suffisance. Sinon reporter, sans effacer de données pour faire de la place.
2. Mettre un repère et une note `FIN-256` sur la dernière page, puis une note `DEBUT-1` sur la première. Ajouter AVANT-2 devant une seule fois ; chronométrer jusqu'à la fin et noter les pauses de l'interface.
3. Vérifier 258 pages : AVANT-01/02 en p. 1/2, DEBUT-1 en p. 3, FIN-256 en p. 258. Vérifier aussi les pages 4, 5, 6 et 130 (motif BASE-04 à la p. 130). Réouvrir deux fois et vérifier les liens des repères.
4. Relever espace libre après et durée. Les copies de secours PageShift restent conservées : une hausse de stockage est attendue ; ne pas les purger. Refaire sur une copie du lot ≥ 50 Mo si LONG-256 est plus petit, et consigner séparément taille/durée/résultat.

**Attendu :** total exact et annotations conservées ; aucune fermeture de l'app. On mesure les ralentissements, sans seuil de vitesse prétendument validé. Si l'écran reste sans progrès apparent pendant deux minutes, noter l'heure et demander conseil ; ne pas forcer l'arrêt ni relancer l'ajout. Manque d'espace, alerte de reprise ou crash : arrêter cette session et suivre la section 5.

Après une session réussie et toutes les tâches terminées, remettre « Lire les nouvelles pages avec OvisOCR2 » dans son état initial (le réactiver s'il était actif). Cela peut relancer la lecture des pages manquantes à la prochaine ouverture. Conserver les livres d'essai tant qu'une anomalie reste à examiner ; leur suppression éventuelle par NOxygen59 ne doit viser que les livres `QA02-…` identifiés, jamais toute la bibliothèque. Les copies de secours PageShift restent présentes et ne doivent pas être purgées.

## 5. Quand arrêter

Une note sur la mauvaise page, une perte de contenu, un total inattendu, un blocage de reprise ou un crash arrête les mutations sur ce livre. Noter le dernier geste et le texte de l'alerte, conserver les sources et l’installation dans leur état, sans extraction de conteneur, puis ouvrir une anomalie avec la fiche ci-dessous.

Ne pas effacer `page-shift.json`, les copies PageShift, les caches ou les résultats OCR pour « débloquer ». Ne pas revenir à l'ancien binaire : il ne sait pas reprendre le journal v2. Ne pas forcer une interruption, couper l'alimentation, remplir le disque ou injecter un journal corrompu sur iPad. Les tests de pannes Mac couvrent plusieurs de ces situations sans enjeu pour la bibliothèque.

## 6. Niveau B — sauvegarde/restauration : garde d'autorisation

**B0 — bloqué tant que la méthode iPad n'est pas qualifiée.** Il n'existe pas de bouton de sauvegarde intégrale dans l'app ajouté par ces travaux. L'outil `tools/backup_container.py` tourne sur Mac à partir d'une copie du conteneur. Il n'extrait ni ne réinstalle un conteneur TrollStore. Ne pas improviser de chemin système, de droits ou de commande d'écrasement.

L’accord de perte pour le niveau A **ne vaut pas** accord de restauration. Un conteneur de l’installation existante peut mélanger données personnelles et PDF synthétiques : ne pas l’extraire comme s’il était un corpus synthétique. Le protocole B ci-dessous attend un conteneur de test exclusivement synthétique qualifié séparément ; tout choix futur de l’installation existante pour B devra être décrit et autorisé explicitement, avec une nouvelle évaluation du périmètre.

Avant B1, faire consigner et approuver :

- l'identité de l'installation jetable et la preuve qu'elle ne partage pas la bibliothèque personnelle ;
- la méthode précise d'arrêt de l'app et des écritures, d'extraction complète de `Documents/` et `Library/`, puis de réimport avec droits/protections iOS compatibles ;
- la build et le schéma compatibles, les chemins locaux source/destination vérifiés, l'espace nécessaire, et une copie de constat intacte ;
- la marche à suivre en cas d'échec, sans désinstaller ni remplacer l'app personnelle ;
- l'accord explicite de NOxygen59 pour l'extraction puis, séparément, pour le réimport. Tout essai d'interruption volontaire demanderait encore un accord et un protocole propres ; il n'est pas proposé ici.

**B1 — sauvegarde puis restauration dans un dossier Mac neuf (accompagné par l'agent).** Après avoir reproduit A0–A2 dans le conteneur exclusivement synthétique qualifié pour B, relever les 8 pages et toutes les données de la table A2, les cartes/échéances, les lectures IA présentes et un réglage visuel de test. Attendre la fin des tâches, arrêter l'app suivant la méthode approuvée, puis exporter le seul conteneur synthétique complet. Préserver cette copie originale. Aucun journal PageShift en attente : s'il existe, l'outil doit refuser, sans qu'on le supprime.

Sur cette copie hors ligne seulement, appliquer les trois commandes de [PHASE2-SAUVEGARDE.md](PHASE2-SAUVEGARDE.md#utilisation-sur-une-copie-de-test), avec chemins explicitement vérifiés. Dossiers parents existants, destinations inexistantes. `--source-stopped` est une attestation humaine, pas une détection de l'arrêt. Garder les trois codes de sortie : backup, verify, restore doivent tous être 0. Vérifier le manifeste et ses exclusions. La restauration publie `destination/container` ; elle ne doit jamais écraser un dossier existant.

**Attendu :** empreintes/inventaire et contrôles SQLite valides, source intacte. Caches et temporaires exclus ; modèles inclus sauf omission explicitement choisie. Trousseau, connexions, droits iOS et installation ne sont pas restaurés par l'outil. Une erreur arrête B1 ; ne pas passer B2 en ignorant l'alerte.

**B2 — réimport et contrôle iPad, autorisation distincte.** Seulement après B1 réussi et méthode approuvée, réimporter le résultat dans l'installation jetable prévue. NOxygen59 ouvre le livre, refait toutes les observations A2 et vérifie en plus la carte, son échéance sans révision supplémentaire, les lectures IA existantes et le réglage visuel. Ajouter `APRES-RESTAURATION` sur BASE-02 (p. 4), fermer puis rouvrir : la note doit persister. Contrôler TEMOIN. Noter explicitement les fonctions non essayées (modèles, dictionnaires, connexions, historique FSRS non observable).

B1 réussi sur Mac ne valide pas B2. Une carte visible ne prouve pas à elle seule tout l'historique FSRS ; le test Swift vérifie cet état interne. QA-02/DATA-02 restent ouverts tant que B2 manque. Aucun succès synthétique n'autorise automatiquement une restauration de données personnelles.

## 7. Consigner dans GitHub sans données personnelles

Ouvrir une Issue de campagne via **New issue → Tâche**, titre `QA-02 — recette iPad — build …`, et y copier la fiche ci-dessous ; lier la PR de préparation. Aucun workflow n'est requis. Utiliser un commentaire par session ; un agent signe `[Codex]` ou `[Claude]`, NOxygen59 écrit en son nom. Ouvrir une Issue séparée par anomalie et reporter son lien dans le tableau. Ne pas créer de fausse campagne exécutée : les résultats initiaux sont « non essayé ».

```text
QA-02 — session [identifiant neutre, date]
Version/build affichés / SHA source externe / SHA-256 du .tipa :
iPad (modèle seulement) / iOS :
Installation A : existante, risque de perte accepté ; référence de la décision :
Précautions A0 effectuées par NOxygen59 / fichier .tipa identifié / installation confirmée :
Qualification du conteneur exclusivement synthétique pour B : bloquée / référence :
Corpus : noms synthétiques, pages, tailles, SHA-256 si disponible
OCR / modèles déjà présents ; Ovis automatique activé ou désactivé :
Diagnostic : activé / désactivé ; espace libre avant / après :
Accord de risque A : chat du 25/10/2026 ; build/installation : références / absentes
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
Session / version-build affichés / SHA source externe / SHA-256 du .tipa :
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

Révision après la [revue de Claude](https://github.com/NOxygen59/kyokasho/pull/7#issuecomment-6397411518), validée par NOxygen59 dans le chat du 25/10/2026 : niveau A sur installation existante avec risque accepté, libellés relus dans le code, égalisation automatique, diagnostic et identification externe. Cette correction ne lance aucune opération sur l’appareil.
