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
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')"
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
python3 "$ROOT/tools/copy_bundled_lexicons.py" --source "${LEXIQUE:h}" \
  --french "$LEXIQUE" --app "$BUILD/Payload/Kyokasho.app" --platform ios

print "==> 4/5 Pseudo-signature (ldid)"
# Frameworks embarqués d'abord (s'il y en a), puis l'app avec ses entitlements.
for fw in "$BUILD/Payload/Kyokasho.app/Frameworks/"*(N); do ldid -S "$fw"; done
ldid -S"$ROOT/packaging/entitlements-trollstore.plist" "$BUILD/Payload/Kyokasho.app/Kyokasho"

print "==> 5/5 Paquet .tipa"
mkdir -p "$ROOT/dist"
[[ ! -e "$OUT" ]] || trash "$OUT"
(cd "$BUILD" && zip -qry "$OUT" Payload)
print "OK : $OUT ($(du -h "$OUT" | cut -f1))"
print "Installation : ouvrir ce fichier avec TrollStore sur l'iPad."
