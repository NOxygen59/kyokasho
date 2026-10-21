# Grammaire — conception proposée (22/10/2026, rien de codé)

But : dans le texte de la page, repérer les points de grammaire (ex. 〜にかかわらず, 〜によっては, 〜ことが多い),
les souligner par niveau JLPT et ouvrir une fiche explicative au toucher. Tout hors ligne, iOS 16.

## 1. Découpage morphologique (le socle)

On a besoin, pour chaque mot : forme écrite, **forme de base**, lecture, **catégorie** (nom, verbe, particule,
auxiliaire…) et **forme de conjugaison**. `CFStringTokenizer` (déjà utilisé pour les furigana) ne donne pas les
catégories : il ne suffit pas.

| Choix | Pour | Contre |
|---|---|---|
| **MeCab + UniDic-lite** (recommandé) | C++ léger, rapide sur iPad, paquets Swift existants pour iOS ; UniDic donne les formes de conjugaison | dictionnaire ≈ 50 Mo à télécharger à la demande |
| MeCab + IPADIC | plus petit, très répandu | découpage plus ancien, moins fin sur les auxiliaires |
| Sudachi (sudachi.rs) | découpage A/B/C, très bon | Rust à compiler pour iOS, dictionnaire 70-200 Mo |

Licences à vérifier et à ajouter dans `THIRD_PARTY_NOTICES.md` + `AboutView` ; dictionnaire **jamais** dans le
dépôt (téléchargé par `ModelStore`, comme les modèles OCR).

## 2. Module `GrammarKit` (dans `Packages/KyokashoKit`, testable sur Mac)

```
GrammarKit/
  Token.swift            struct Token { surface, lemma, reading, pos: [String], conjForm, range }
  Morphology.swift       protocol Morphology { func tokenize(_ text: String) -> [Token] }
  MeCabMorphology.swift  implémentation (dictionnaire passé par son dossier)
  GrammarPattern.swift   struct GrammarPattern: Codable { id, level (N5…N1), title, steps: [Step], sheet }
                         enum Step { lemma(String), surface(String), pos(String), conj(String), any(max: Int) }
  GrammarMatcher.swift   parcours des jetons, chaque motif = petit automate ; renvoie [GrammarMatch]
  GrammarMatch.swift     struct GrammarMatch { patternID, tokenRange, textRange }
```

- Un motif décrit des **jetons**, pas du texte : 〜によっては = `lemma(に) · lemma(よる) conj(て形) · surface(は)`.
  Ainsi les conjugaisons et les variantes (によって / により) sont trouvées sans liste sans fin.
- Motifs et fiches : un fichier JSON (motifs) + Markdown (fiches). **Écrits par toi ou par moi**, pas copiés de
  Bunpro, DoJG ou d'un livre (droits d'auteur ; règle « aucune donnée tierce dans le dépôt »). Une source libre
  ajoutée plus tard = téléchargée à la demande, avec sa licence.
- Cache par page et version (comme l'OCR, `OCRPage.currentVersion`) : jetons + correspondances en SQLite.

## 3. Dans l'app

- Panneau d'étude, onglet Texte : soulignement fin coloré par niveau (N5 clair → N1 foncé), interrupteur
  « Grammaire » à côté de ふりがな. Toucher → feuille : titre, niveau, explication, la phrase de la page en exemple,
  bouton « Créer une carte » (type de carte « grammaire » dans ReviewKit).
- Le dictionnaire profite aussi du découpage : mot entier au toucher (sous-étape E) plus fiable avec MeCab.
- Plus tard : liste des points de la page / du livre, filtre par niveau, statistiques « points vus ».

## 4. Ordre de travail proposé

1. `Token` + `Morphology` + MeCab (téléchargement UniDic-lite, avec accord) + tests sur Mac.
2. `GrammarMatcher` + 30 motifs N3-N2 écrits à la main + tests.
3. Soulignement et fiche dans le panneau.
4. Cartes de grammaire.
