#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
# Construit dist/Kyokasho-<version>.tipa, installable avec TrollStore (iPad, iOS 16).
#
#   ./build_ipa.sh
#
# Étapes : génération du projet Xcode (XcodeGen) → archive Release sans signature → dossier
# Payload → pseudo-signature ldid avec les entitlements → zip en .tipa.
# Prérequis : Xcode, XcodeGen et ldid (brew install xcodegen ldid).
# Sorties : le .tipa, sa fiche d'identité `Kyokasho-<version>.manifeste.json` et ses symboles `.dSYM.zip` (lot B1).
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
BUILD_NUMBER="$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
# Recette 1.5.5 : la candidate est partie sans ses notes, et la fenêtre « Nouveautés » ne s'est pas affichée.
# On refuse donc de construire un paquet dont la version n'est pas celle de `ReleaseNotes.current`.
NOTES="$(grep -m1 'public static let current = ReleaseNotes(' Packages/KyokashoKit/Sources/ReaderCore/AppIntro.swift \
  | sed -E 's/.*ReleaseNotes\("([^"]+)".*/\1/')"
if [[ "$NOTES" != "$VERSION" ]]; then
  print -u2 "Notes de version absentes : ReleaseNotes.current est $NOTES, la version est $VERSION (AppIntro.swift)."
  exit 1
fi
# Décision de NOxygen59 du 13/11/2026 : une candidate exige la relecture finale de son commit par un modèle d'une
# autre famille (REVUE-FINALE-<sha>.md avec « VERDICT : OK », voir docs/GOUVERNANCE-ET-REPRISE.md, « Sécurité »).
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  print -u2 "Modifications non commitées : une candidate se construit sur un commit relu."
  exit 1
fi
python3 scripts/githooks/kyokasho_hooks.py final-review "$(git rev-parse HEAD)"
BUILD="$ROOT/build/ipa"
ARCHIVE="$BUILD/Kyokasho.xcarchive"
OUT="$ROOT/dist/Kyokasho-$VERSION.tipa"

print "==> 1/5 Projet Xcode (XcodeGen)"
xcodegen generate --quiet
# Le .xcodeproj est régénéré : reprendre les révisions déjà validées du paquet local.
PINS="$ROOT/Kyokasho.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$PINS"
cp "$ROOT/Packages/GLMOCRKit/Package.resolved" "$PINS/Package.resolved"

print "==> 2/5 Archive Release (sans signature)"
mkdir -p "$BUILD"
[[ ! -e "$ARCHIVE" ]] || trash "$ARCHIVE"
if ! xcodebuild archive \
  -project Kyokasho.xcodeproj -scheme Kyokasho -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD/DerivedData" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  > "$BUILD/archive.log" 2>&1; then
  tail -n 80 "$BUILD/archive.log" >&2
  print -u2 "Compilation échouée. Journal complet : $BUILD/archive.log"
  exit 1
fi
APP="$ARCHIVE/Products/Applications/Kyokasho.app"
[[ -d "$APP" ]] || { print -u2 "Archive introuvable : la compilation a échoué."; exit 1; }

print "==> 3/5 Dossier Payload"
[[ ! -e "$BUILD/Payload" ]] || trash "$BUILD/Payload"
mkdir -p "$BUILD/Payload"
cp -R "$APP" "$BUILD/Payload/"
# Lexique du design d'intérieur (#50, D4 piste B ; décision de NOxygen59 du 29/10/2026) : construit sur le Mac par
# tools/build_domain_lexicon.py, jamais versionné. Ajouté au paquet s'il existe ; sinon l'app indique qu'il manque.
LEXIQUE="${KYOKASHO_LEXIQUE:-$ROOT/../dictionnaires-construits/lexique-interieur/lexique-interieur.zip}"
# Conserver le chemin français historique ; ses variantes sont cherchées dans le même dossier.
# Lot B1 (13/11/2026) : la révision attendue est versionnée ; le bon dossier est trouvé, sinon refus (un ancien
# lexique était parti dans le premier paquet 1.5.8).
python3 "$ROOT/tools/copy_bundled_lexicons.py" --source "${LEXIQUE:h}" \
  --french "$LEXIQUE" --app "$BUILD/Payload/Kyokasho.app" --platform ios \
  --expected "$(<"$ROOT/packaging/lexique-attendu.txt")"

# Pas de chinois sur iPad (décision de NOxygen59, 04/11/2026) : le catalogue commun le produit, le paquet le retire.
find "$BUILD/Payload/Kyokasho.app" -type d -name 'zh-Hans.lproj' -prune -print0 | xargs -0 -r trash
/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$BUILD/Payload/Kyokasho.app/Info.plist" | grep -q zh-Hans && python3 -I - "$BUILD/Payload/Kyokasho.app/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
info["CFBundleLocalizations"] = [code for code in info["CFBundleLocalizations"] if code != "zh-Hans"]
with open(sys.argv[1], "wb") as target:
    plistlib.dump(info, target)
PY
python3 "$ROOT/tools/check_ipad_package.py" "$BUILD/Payload/Kyokasho.app"
# Fiche d'identité dans l'app (lot B1) : version, commit, outils, dépendances, lexiques, relecture finale.
python3 "$ROOT/tools/build_manifest.py" app --root "$ROOT" --app "$BUILD/Payload/Kyokasho.app" \
  --version "$VERSION" --build "$BUILD_NUMBER" --review "REVUE-FINALE-$(git rev-parse HEAD | cut -c1-7).md"

print "==> 4/5 Pseudo-signature (ldid)"
# Frameworks embarqués d'abord (s'il y en a), puis l'app avec ses entitlements.
for fw in "$BUILD/Payload/Kyokasho.app/Frameworks/"*(N); do ldid -S "$fw"; done
ldid -S"$ROOT/packaging/entitlements-trollstore.plist" "$BUILD/Payload/Kyokasho.app/Kyokasho"

print "==> 5/5 Paquet .tipa"
mkdir -p "$ROOT/dist"
[[ ! -e "$OUT" ]] || trash "$OUT"
(cd "$BUILD" && zip -qry "$OUT" Payload)
# Symboles de débogage gardés à côté du paquet, et fiche complète (taille, SHA-256, UUID contrôlés) (lot B1).
DSYM="$ARCHIVE/dSYMs/Kyokasho.app.dSYM"
DSYM_OUT="$ROOT/dist/Kyokasho-$VERSION.dSYM.zip"
[[ ! -e "$DSYM_OUT" ]] || trash "$DSYM_OUT"
[[ -d "$DSYM" ]] && (cd "${DSYM:h}" && zip -qry "$DSYM_OUT" "${DSYM:t}")
MANIFEST_OUT="$ROOT/dist/Kyokasho-$VERSION.manifeste.json"
[[ ! -e "$MANIFEST_OUT" ]] || trash "$MANIFEST_OUT"
python3 "$ROOT/tools/build_manifest.py" paquet --manifest "$BUILD/Payload/Kyokasho.app/MANIFESTE.json" \
  --tipa "$OUT" --binary "$BUILD/Payload/Kyokasho.app/Kyokasho" --dsym "$DSYM" --out "$MANIFEST_OUT"
print "OK : $OUT ($(du -h "$OUT" | cut -f1))"
print "Installation : ouvrir ce fichier avec TrollStore sur l'iPad."
