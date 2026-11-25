<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Débogage et incidents

## Recueillir un signal utile

Le mode diagnostic de l'app est utilisable quel que soit l'assistant qui aide à analyser le problème. Il n'est pas réservé à Claude. `App/Settings/Diagnostics.swift` définit le journal ; le chemin est **Réglages → Aide et informations → Aide au diagnostic → Mode diagnostic**. La recherche « diagnostic » dans les réglages mène aussi à cet écran. L’activation enrichit le journal sans ajouter d’indicateur au lecteur : elle ne produit pas forcément de changement visuel. Les erreurs sont toujours notées, même si le mode est désactivé.

Activer le diagnostic, reproduire le problème une fois, puis « Voir le journal » sur le même écran. « Partager le journal » transmet le fichier complet et ne le nettoie pas : pour GitHub, recopier manuellement seulement un extrait relu et expurgé ; le fichier est aussi dans `Documents/Diagnostics/journal.txt` du conteneur. Relever version/build, iOS, livre/page, moteur/modèle, langue, orientation et périphérique. Vérifier le contenu avant de le publier : un journal ou une capture peut révéler des chemins, textes ou titres personnels.

Un bon rapport contient : étapes exactes, attendu, observé, fréquence, dernière version où cela fonctionnait, opération en cours et premier message d'erreur. Une capture aide au rendu ; le journal aide aux tâches et à Metal ; le `.ips` aide au crash. N'envoyer ni clé ni mot de passe. Utiliser un exemple synthétique dès que possible.

## Format des fichiers de diagnostic (10/11/2026)

- `journal.txt` : une ligne par événement, `heure ISO · [info|alerte|erreur] · [zone] · message`, et un en-tête `=== Lancement Kyōkasho …` à chaque lancement (version, appareil, iOS, mémoire, batterie, luminosité, lecture IA auto `scan.auto`, relecture GLM-OCR `ocr.aiReread`, furigana).
- **Depuis PLAN-DIAG-001 E1 (25/11/2026)** : les zones forment une liste fermée (`DiagnosticZone`, mêmes noms qu'avant ; une zone inconnue devient `app`). Les paquets émettent des **événements typés** : `heure ISO [niveau] [zone] op=… parent=… étape=… issue=debut|etape|succes|erreur|annule|refus|repli cause=… t=…ms mem=…Mo doc=… nom=valeur`. **Aucune donnée personnelle** : jamais de titre (un document est cité `doc xxxxxx`, référence salée propre à l'installation), de chemin, de nom de fichier, de texte, de nom de modèle importé, ni de message d'erreur système (`domaine#numéro` à la place) ; garde `tests/test_diagnostics_privacy.py`. Au-delà de 5 Mo, le journal devient `journal.1.txt` (partagé et effacé avec lui) et un nouveau commence par une ligne `Rotation du journal`. Au premier lancement, `journal.txt`, `journal.1.txt` et `energie.csv` de l'ancien format sont **déplacés** vers un nom libre (`journal-avant-diagnostics[-N].txt`, `energie-avant-diagnostics[-N].csv`), jamais effacés ni écrasés ; jamais partagés ; effacés seulement par « Effacer le journal » / « Effacer le relevé ». **Tant que ce déplacement n'a pas réussi, l'app n'écrit, ne lit ni ne partage aucun fichier de diagnostic** (message dans Réglages › Diagnostic) et réessaie au lancement suivant (révision `diagnostics.migrationRevision` = 3). Ne jamais publier ces anciens fichiers ni une copie brute du conteneur. Les noms de fils et de files du moniteur CPU sont des étiquettes fermées (`kyo.<travail>`, noms connus, `apple.*`, sinon `autre`). Les relevés du moniteur CPU portent `op=` (une par relevé) et `étape=releve_cpu` ou `fil_persistant`. Une erreur fatale MLX n'écrit que la longueur de son message natif. Lignes perdues (file pleine) : une ligne `Lignes perdues : …` le dit.
- **Session non clôturée (PLAN-DIAG-001 E2a)** : l'app note dans `Library/Application Support/KyokashoDiagnosticState/session.json` (hors Fichiers, hors sauvegardes) si elle est au premier plan (« armée ») ou passée au vrai arrière-plan (« close »). Retrouvée armée au lancement suivant, elle écrit **une** ligne `[alerte] [diagnostic] étape=session_precedente_non_cloturee … generation=N age_s=S` (âge depuis le dernier état écrit, absent si l'horloge n'est pas crédible) et l'affiche dans Réglages › Diagnostic. Cela veut dire « aucune clôture n'a été enregistrée avant l'arrêt » (arrêt forcé au premier plan, mémoire, plantage, débogueur, ou écriture de clôture impossible) : **jamais** une cause. Fichier illisible ou invalide : `étape=etat_session_precedente_inconnu`, sans alerte d'interruption. Centre de contrôle, Split View et sélecteur ne changent rien. **Détail automatique (E2b, DEC-02 B)** : après ce constat, le journal passe en détail (lignes `[info]`) pendant **24 h** exactement (ligne `étape=detail_automatique_24h`, échéance affichée dans Réglages › Diagnostic), même si « Mode diagnostic » est éteint ; le réglage ne change pas, et ni le moniteur CPU, ni le relevé de batterie ne s'allument. Une simple relance ne prolonge pas la fenêtre ; une horloge reculée ne l'ouvre pas.
- `energie.csv` : une ligne par minute, 17 colonnes `date,batterie,en_charge,chaleur,economie,luminosite,cpu_s,memoire_mo,activite,cpu_pct,ecran,etat_thermique,teinte,ia_chargees,taches_ia,document,version_app`. Les 9 premières sont celles du départ : un fichier de 9 colonnes reste lisible. Une batterie inconnue s'écrit **vide**, jamais `-1`. `document` est une référence salée propre à l'installation (jamais l'identifiant du fichier), et `ia_chargees` / `taches_ia` ne reprennent jamais un titre de livre ni le nom d'un modèle importé (« modèle importé »).
- « Partager le relevé et le journal » envoie les deux fichiers ensemble. Au-delà de 1,5 Mo (journal) ou 1 Mo (relevé), une bannière **permanente**, dans la bibliothèque comme dans le lecteur, propose de les partager puis de les effacer ; elle disparaît d'elle-même une fois les deux fichiers sous les seuils (décision testée : `DiagnosticFiles.warning`). Si d'anciens fichiers n'ont pas pu être mis à l'écart, la bannière dit au contraire de **ne pas** les partager (ni depuis l'app Fichiers), seulement de les effacer.

## Orienter l'enquête

| Symptôme | Premiers éléments à vérifier |
|---|---|
| Mot faux ou absent | PDF texte/image, moteur OCR, texte brut, langue, dictionnaire et MeCab |
| Furigana panneau présents mais absents sur page | OCR géométrique, boîtes/caractères, alignement, orientation et réglage page |
| Chat sur de mauvaises pages | Étiquettes des pages, question exacte, lectures Ovis disponibles et passages sélectionnés |
| App lente | Phase : chargement, lecture image, génération, rendu ; modèle et froid/chaud |
| Fermeture pendant IA | Première erreur MLX/Metal, mémoire disponible, rapport `.ips` ou jetsam |
| Notes/repères décalés | Taille/rotation/égalisation, ajout de pages, versions avant/après |
| Travail bloqué | Tâche active, chargement partagé, annulation, état après changement de vue |
| Bibliothèque qui ne persiste plus | Erreur d'ouverture de base : AppModel prévoit un repli en mémoire, à distinguer d'une base persistante réparée |

Le repli en mémoire après échec d'ouverture de base maintient une interface utilisable, mais ne prouve pas la conservation des nouvelles écritures. Préserver la base sur disque avant une réparation.

## Symboliser un crash

Conserver le `.ips`, le binaire exact et son dSYM **avant** de reconstruire avec `build_ipa.sh`, qui remplace l'archive. Une archive d'une autre compilation peut porter le même numéro de version et être inutilisable pour cette symbolisation.

```sh
dwarfdump --uuid build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM
```

Comparer l'UUID arm64 au `slice_uuid` de l'image Kyokasho du rapport. Puis adapter la base de chargement et les adresses du même rapport :

```sh
atos -arch arm64 \
  -o build/ipa/Kyokasho.xcarchive/dSYMs/Kyokasho.app.dSYM/Contents/Resources/DWARF/Kyokasho \
  -l <base-de-chargement> <adresse-du-rapport>
```

Les marqueurs entre chevrons sont à remplacer, pas à coller tels quels dans le terminal. Consigner la pile et la fonction responsable ; ne pas inventer de symbole en l'absence du bon UUID. Un arrêt jetsam se traite par analyse de pression mémoire et contexte d'utilisation, pas seulement avec `atos`.

## Enquête MLX et Metal

Lire [IA locale](IA-LOCALE.md). Les deux compilations des kernels — précompilation Mac et compilation à la volée sur iPad — doivent rester compatibles. Un essai Mac forcé Metal 3.0 ne reproduit pas toutes les absences du compilateur iOS 16 ; cela a déjà masqué `remove_addrspace_t` et `simdgroup_matrix<bool>`.

Garder la première erreur, identifier le kernel et les motifs similaires, comparer les API disponibles puis appliquer un équivalent dans le fork. Ne pas couper les contrôles libc++ ni transformer une erreur de chargement en succès silencieux. Une modification du fork doit être poussée et épinglée avant la compilation du paquet qui la revendique.

## Ajouter de l'observabilité

Sur un nouveau chemin lourd, employer `Diagnostics.log`, `measure` et `error` aux frontières : début/fin/échec/annulation, identifiant de tâche, document/page, modèle, durée et catégorie d'erreur. Éviter le contenu intégral d'un manuel et les identifiants de compte. Ne pas enregistrer chaque token ou chaque image en production sans nécessité.

Pour un incident de données, arrêter les opérations qui modifient la ressource, garder une copie cohérente, reproduire sur une copie et distinguer cause démontrée de piste. Le marqueur `page-shift.json` est une preuve de l'état de reprise ; ne pas l'effacer arbitrairement.

## Clôturer

Une correction est terminée lorsque le cas réduit échoue avant, réussit après, que les comportements proches sont préservés et que le statut iPad est explicitement renseigné. Conserver dans la PR le symptôme, la cause prouvée, la correction, les tests et les limites ; l'historique de chat seul ne suffit pas à la prochaine reprise.

## Relevé CPU en mode diagnostic

Mode diagnostic activé (Réglages › Aide), l'app échantillonne ses fils une fois par seconde et écrit deux familles de lignes. Elles servent à mesurer un gel, pas à le corriger.

`[cpu]` est écrite quand le total de l'app dépasse 60 %, monte de 25 points, toutes les 30 s de mesure, ou à la fin d'un travail long. Chaque fil retenu est décrit par :

- `fils` : les fils à **5 % ou plus**, **12 au maximum**, du plus chargé au moins chargé ; `fils_omis` compte ceux qui dépassent ce plafond.
- `nom` (et `file`) : **étiquette fermée** (PLAN-DIAG-001 E1) : nom connu exact (fils et files de l'app, fil principal), `kyo.<travail>` pour un fil nommé par l'app, `apple.cooperative` / `apple.root` / `apple.autre` pour le système, sinon `autre` ; `sans-nom` / `?` s'il n'y en a pas. Le filtre d'alphabet et la coupe à 40 caractères s'appliquent avant.
- `âge_s` : temps écoulé depuis la **première fois que ce fil a été vu** dans la session de mesure. Il repart de zéro seulement si le fil disparaît d'un relevé réussi ; un relevé manqué ne le remet pas à zéro (il coupe seulement la mesure de persistance). Ce n'est pas l'âge réel du fil.
- `moy10s` : moyenne sur les 10 dernières secondes, calculée sur les compteurs cumulés du fil, pas sur l'estimation instantanée de Mach.
- `fonction` : type du travail mesuré en cours sur ce fil (par exemple `aiGenerate`), sinon `inconnue`. Pendant une mesure synchrone, l'app renomme aussi le fil en `kyo.` suivi de ce type, puis restaure le nom précédent : on peut donc voir `kyo.<type>` dans `nom`.
- `doc` : alias tiré au hasard (12 caractères hexadécimaux) du document ; jamais son titre ni son chemin. `page` : page de la mesure quand elle est connue.

`[cpu-persistant]` n'apparaît que si un fil reste à **80 % ou plus pendant plus de 10 s**. Une même ligne ne revient pas plus d'une fois par minute et par fil. Elle ajoute `âge_s` et `événements` : les **3 dernières catégories** du journal (hors `cpu`) écrites juste avant la détection. Un relevé manqué ou un trou de plus de 2,5 s remet le compteur à zéro : la preuve de chauffe doit être continue.

Ce qu'on ne peut pas conclure :

- **Un nom ne prouve pas l'origine.** `kyo.<type>` dit seulement qu'un travail mesuré tournait sur ce fil ; les autres noms ne disent pas quel appelant a lancé le travail.
- `fonction:inconnue` est normal pour les fils internes de PDFKit, ONNX Runtime, Vision et MLX : ces bibliothèques créent leurs propres fils et ne passent pas par nos mesures. Le fil inconnu peut être la cause du gel.
- `fil#…` avec `sans-nom` signifie « aucun nom exploitable », pas « fil inactif ».
- L'absence de `[cpu-persistant]` ne disculpe pas le CPU : il faut le seuil de 80 %, plus de 10 s, et des relevés continus.

Avant de partager un extrait, le relire : `événements` donne du contexte, pas une cause, et, dans un journal écrit avant PLAN-DIAG-001 E1 (mis à l'écart sous `journal-avant-diagnostics*.txt`), d'autres zones écrivaient des titres de documents. Ne transmettre que les lignes utiles, jamais le journal brut ni une capture non recadrée.

Vérifié dans `Packages/KyokashoKit/Sources/ReaderCore/DiagnosticThreadMonitor.swift`, `DiagnosticCPULog.swift`, `DiagnosticMachCPU.swift`, `DiagnosticThreadHook.swift`, `App/Settings/DiagnosticCPU.swift` et `App/Reader/ActivityCenter.swift` (22/11/2026).

## Mesurer le retard de défilement OCR (QA02)

Mode diagnostic : `ocr-scroll` distingue événements HTML passifs (wheel/touch/scroll), délai du
pont JavaScript→Swift, offset natif WebKit et position du conteneur web dans la fenêtre SwiftUI.
Traces limitées à deux événements par seconde et par catégorie. Le délai du pont n'est pas la
latence visuelle ; la vidéo/observation iPad reste nécessaire. Aucun geste n'est intercepté ou
réacheminé par cette instrumentation. `ocr-panel` décrit le rectangle au relâchement du panneau.
Voir les [preuves et limites du panneau](QA02-CORRECTIONS-PANNEAU.md).

## Consultation après correction QA02 (non validée sur iPad)

« Voir le journal » lit un instantané après ouverture. « Actualiser » relit les écritures déjà
en file ; il n'y a pas de suivi continu. Journal absent, vide et erreur de lecture sont distincts.
Une rotation coupant un caractère UTF-8 laisse le reste lisible ; l'export brut reste inchangé.
Les pastilles IA proposent aussi ce journal. Leur « Voir le détail » reste réservé aux tâches
actives : absence de tâche ne signifie pas absence de journal. Voir les [preuves](QA02-CORRECTIONS-DIAGNOSTICS.md).
