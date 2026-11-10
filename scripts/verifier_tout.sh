#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
# Vérification complète locale, reproductible, d'un commit Kyōkasho (GitHub Actions reste désactivé, CI-0).
#
#   ./scripts/verifier_tout.sh
#
# Enchaîne, depuis la racine du dépôt : génération du projet Xcode (si `xcodegen` existe), tests Swift
# (`Packages/KyokashoKit`), tests Python (`tests/`), compilation iOS générique (simulateur, sans signature)
# et contrôle documentaire. Écrit `build/verif/RESUME-<date>.md` avec le SHA, la branche, les compteurs lus
# dans les journaux, et laisse chaque journal dans `build/verif/journaux/`.
#
# Choix assumés :
# - toutes les étapes sont exécutées même si l'une échoue, pour que le résumé dise ce qui a réellement
#   tourné (un arrêt à la première erreur rendrait la fiche incomplète) ; le script sort en erreur à la fin
#   si une seule étape a échoué ;
# - aucun réseau, aucune suppression hors `build/verif` (les journaux du run précédent sont réécrits) ;
# - ce script ne remplace ni la compilation iOS générique ciblée d'un lot, ni la validation sur l'iPad par
#   NOxygen59 : c'est une preuve Mac, pas une recette.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OUT="build/verif"
JOURNAUX="$OUT/journaux"
mkdir -p "$JOURNAUX" || exit 2

DATE="$(date +%Y-%m-%d)"
HEURE="$(date '+%H:%M')"
RESUME="$OUT/RESUME-$DATE.md"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'inconnu')"
SHA_LONG="$(git rev-parse HEAD 2>/dev/null || echo 'inconnu')"
BRANCHE="$(git branch --show-current 2>/dev/null)"
[ -n "$BRANCHE" ] || BRANCHE="(tête détachée)"
MODIFIES="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

XCODEGEN_RESULTAT="non exécuté (xcodegen absent)"
SWIFT_RESULTAT="non exécuté"
SWIFT_TOTAL="non mesuré"
SWIFT_IGNORES="non mesuré"
SWIFT_ECHECS="non mesuré"
SWIFT_CLARIFIE="non mesuré"
PYTHON_RESULTAT="non exécuté"
PYTHON_TOTAL="non mesuré"
PYTHON_DETAIL="non mesuré"
IOS_RESULTAT="non exécutée"
IOS_ERREURS="non mesuré"
DOC_RESULTAT="non exécuté"
DOC_LIENS="non mesuré"
ECHECS_NOMBRE=0
ECHECS_LISTE=""

ajouter_echec() {
  ECHECS_NOMBRE=$((ECHECS_NOMBRE + 1))
  if [ -z "$ECHECS_LISTE" ]; then
    ECHECS_LISTE="$1"
  else
    ECHECS_LISTE="$ECHECS_LISTE, $1"
  fi
}

DEBUT=$SECONDS

# 1. Projet Xcode -----------------------------------------------------------
if command -v xcodegen >/dev/null 2>&1; then
  printf '==> 1/5 Projet Xcode (xcodegen generate -q)\n'
  if xcodegen generate -q >"$JOURNAUX/xcodegen.log" 2>&1; then
    XCODEGEN_RESULTAT="réussi"
  else
    XCODEGEN_RESULTAT="échec (voir journaux/xcodegen.log)"
    ajouter_echec "xcodegen"
  fi
fi

# 2. Tests Swift (paquet KyokashoKit) ---------------------------------------
printf '==> 2/5 Tests Swift (Packages/KyokashoKit)\n'
if ( cd "$ROOT/Packages/KyokashoKit" && swift test ) >"$JOURNAUX/swift.log" 2>&1; then
  SWIFT_RESULTAT="réussi"
else
  SWIFT_RESULTAT="échec (voir journaux/swift.log)"
  ajouter_echec "swift test"
fi
# `swift test` lance un processus XCTest par cible : la ligne « All tests » apparaît deux fois par cible
# (« started » puis « passed »/« failed ») et seul le total de la cible est porté par la ligne
# « Executed … » qui suit le verdict. On ne retient donc que la ligne suivant « passed »/« failed » : la
# prendre après « started » ramènerait la ligne du bundle et donnerait un total faux (piège rencontré).
sed -nE "/^Test Suite 'All tests' (passed|failed) at/ { n; p; }" "$JOURNAUX/swift.log" >"$JOURNAUX/swift-totaux.txt"
if grep -q '^[[:space:]]*Executed ' "$JOURNAUX/swift-totaux.txt"; then
  SWIFT_TOTAL="$(awk '{ if ($1 == "Executed") total += $2 } END { printf "%d", total }' "$JOURNAUX/swift-totaux.txt")"
  SWIFT_IGNORES="$(grep -oE '[0-9]+ tests? skipped' "$JOURNAUX/swift-totaux.txt" | awk '{ total += $1 } END { printf "%d", total }')"
  SWIFT_ECHECS="$(grep -oE '[0-9]+ failures?' "$JOURNAUX/swift-totaux.txt" | awk '{ total += $1 } END { printf "%d", total }')"
fi
# Contrôle croisé indépendant des lignes « Executed » : une ligne par cas de test. Si les deux comptages
# divergent, le résumé le dit au lieu d'annoncer un chiffre unique non vérifiable.
SWIFT_CAS_PASSES="$(grep -cE '^Test Case .* passed' "$JOURNAUX/swift.log" || true)"
SWIFT_CAS_ECHECS="$(grep -cE '^Test Case .* failed' "$JOURNAUX/swift.log" || true)"
SWIFT_CAS_IGNORES="$(grep -cE '^Test Case .* skipped' "$JOURNAUX/swift.log" || true)"
SWIFT_CAS_TOTAL=$((SWIFT_CAS_PASSES + SWIFT_CAS_ECHECS + SWIFT_CAS_IGNORES))
if [ "$SWIFT_TOTAL" = "non mesuré" ]; then
  SWIFT_CLARIFIE="non mesuré (aucune ligne « Executed » : voir journaux/swift.log)"
elif [ "$SWIFT_TOTAL" = "$SWIFT_CAS_TOTAL" ]; then
  SWIFT_CLARIFIE="$SWIFT_TOTAL exécutés, $SWIFT_IGNORES ignorés, $SWIFT_ECHECS échec(s) ; $SWIFT_CAS_PASSES cas passés comptés un à un"
else
  SWIFT_CLARIFIE="$SWIFT_TOTAL exécutés (lignes « Executed »), $SWIFT_IGNORES ignorés, $SWIFT_ECHECS échec(s) ; $SWIFT_CAS_TOTAL cas comptés un à un (écart à expliquer)"
fi

# 3. Tests Python (outil de sauvegarde, catalogues, gardes de câblage) ------
printf '==> 3/5 Tests Python (tests/)\n'
if python3 -m unittest discover -s tests >"$JOURNAUX/python.log" 2>&1; then
  PYTHON_RESULTAT="réussi"
else
  PYTHON_RESULTAT="échec (voir journaux/python.log)"
  ajouter_echec "tests Python"
fi
PYTHON_TOTAL="$(grep -E '^Ran [0-9]+ tests?' "$JOURNAUX/python.log" | tail -1 | sed -E 's/^Ran ([0-9]+) tests?.*/\1/')"
[ -n "$PYTHON_TOTAL" ] || PYTHON_TOTAL="non mesuré"
PYTHON_DETAIL="$(grep -E '^(OK|FAILED)' "$JOURNAUX/python.log" | tail -1)"
[ -n "$PYTHON_DETAIL" ] || PYTHON_DETAIL="pas de ligne de résultat"

# 4. Compilation iOS générique (simulateur, sans signature) -----------------
printf '==> 4/5 Compilation iOS générique\n'
if xcodebuild -project Kyokasho.xcodeproj -scheme Kyokasho \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/verif \
  build CODE_SIGNING_ALLOWED=NO -quiet >"$JOURNAUX/ios.log" 2>&1; then
  IOS_RESULTAT="réussie"
else
  IOS_RESULTAT="échec (voir journaux/ios.log)"
  ajouter_echec "compilation iOS"
fi
IOS_ERREURS="$(grep -cE '(^| )error:' "$JOURNAUX/ios.log")"

# 5. Contrôle documentaire --------------------------------------------------
printf '==> 5/5 Contrôle documentaire (scripts/check_documentation.py)\n'
if python3 scripts/check_documentation.py >"$JOURNAUX/documentation.log" 2>&1; then
  DOC_RESULTAT="réussi"
else
  DOC_RESULTAT="échec (voir journaux/documentation.log)"
  ajouter_echec "contrôle documentaire"
fi
DOC_LIENS="$(tail -1 "$JOURNAUX/documentation.log")"
[ -n "$DOC_LIENS" ] || DOC_LIENS="pas de ligne de résultat"

DUREE=$((SECONDS - DEBUT))
if [ "$ECHECS_NOMBRE" -eq 0 ]; then
  VERDICT="toutes les étapes ont réussi"
  CODE=0
else
  VERDICT="$ECHECS_NOMBRE étape(s) en échec : $ECHECS_LISTE"
  CODE=1
fi

cat >"$RESUME" <<EOF
<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 NOxygen59 -->

# Résumé de vérification locale — $DATE $HEURE

Généré par \`scripts/verifier_tout.sh\`. Preuve **Mac** : elle ne remplace ni la compilation iOS d'un lot
précis, ni la validation sur l'iPad par NOxygen59. Aucun réseau, GitHub Actions désactivé (CI-0).

- Commit : \`$SHA\` (\`$SHA_LONG\`)
- Branche : \`$BRANCHE\`
- Fichiers modifiés ou non suivis au lancement : $MODIFIES
- Machine : $(sw_vers -productName 2>/dev/null || echo macOS) $(sw_vers -productVersion 2>/dev/null) $(uname -m)
- Xcode : $(xcodebuild -version 2>/dev/null | head -1)
- Swift : $(swift --version 2>/dev/null | head -1)
- Durée : ${DUREE}s

| Étape | Résultat | Détail |
|---|---|---|
| Projet Xcode | $XCODEGEN_RESULTAT | \`xcodegen generate -q\` |
| Tests Swift | $SWIFT_RESULTAT | $SWIFT_CLARIFIE |
| Tests Python | $PYTHON_RESULTAT | $PYTHON_TOTAL tests ; $PYTHON_DETAIL |
| Compilation iOS générique | $IOS_RESULTAT | $IOS_ERREURS ligne(s) \`error:\` dans le journal |
| Contrôle documentaire | $DOC_RESULTAT | $DOC_LIENS |

**Verdict : $VERDICT** (code de sortie $CODE).

Étapes non exécutées par choix, à ne pas lire comme des succès : tests Swift/ASan d'un lot précis, essais
MLX/ONNX avec poids, extraction ou restauration TrollStore. Ce résumé décrit ce qui a réellement tourné.

Journaux complets : \`build/verif/journaux/\` (\`xcodegen.log\`, \`swift.log\`, \`swift-totaux.txt\`, \`python.log\`,
\`ios.log\`, \`documentation.log\`).

Non couvert par ce résumé : recette iPad (iOS 16.6.1, TrollStore), MLX/Metal sur l'appareil, mémoire réelle,
ASan/LSan, essais MLX/ONNX avec poids. Ces preuves restent à la charge de NOxygen59 et des lots qui les exigent.
EOF

printf '\nRésumé : %s\n%s\n' "$RESUME" "$VERDICT"
exit "$CODE"
