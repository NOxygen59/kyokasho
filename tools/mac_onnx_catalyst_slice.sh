#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Version Mac (#55) : ONNX Runtime est livré pour iOS et macOS, pas pour Mac Catalyst. Ce script ajoute une tranche
# Catalyst à l'xcframework téléchargé par SwiftPM, dans le dossier de build seulement, à partir de la tranche macOS :
# même code, seule l'étiquette de plateforme des objets change. Rien n'entre dans le dépôt et l'iPad n'est pas touché.
# Usage : tools/mac_onnx_catalyst_slice.sh <derivedDataPath>, après une résolution des paquets.
set -euo pipefail
DD=$1
XC="$DD/SourcePackages/artifacts/onnxruntime-swift-package-manager/onnxruntime/onnxruntime.xcframework"
SLICE="ios-arm64_x86_64-maccatalyst"
[[ -d "$XC/macos-arm64_x86_64" ]] || { echo "xcframework introuvable : $XC" >&2; exit 1; }
INDEXED=$(python3 -I -c 'import plistlib,sys; print(any(e.get("LibraryIdentifier")==sys.argv[2] for e in plistlib.load(open(sys.argv[1],"rb"))["AvailableLibraries"]))' "$XC/Info.plist" "$SLICE")
if [[ -d "$XC/$SLICE" && "$INDEXED" == True ]]; then echo "Tranche déjà présente"; exit 0; fi
# Reste d'une tentative interrompue : le dossier seul ne prouve pas qu'elle a abouti.
[[ -d "$XC/$SLICE" ]] && trash "$XC/$SLICE"
WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || true' EXIT
ditto "$XC/macos-arm64_x86_64/onnxruntime.framework" "$WORK/onnxruntime.framework"
SRC="$XC/macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime"
DST="$WORK/onnxruntime.framework/Versions/A/onnxruntime"
THIN=()
for ARCH in x86_64 arm64; do
  lipo -thin $ARCH "$SRC" -output "$WORK/$ARCH.a"
  mkdir "$WORK/$ARCH"
  (cd "$WORK/$ARCH" && ar -x "../$ARCH.a")
  for O in "$WORK/$ARCH"/*.o; do
    vtool -set-build-version maccatalyst 16.0 16.0 -replace -output "$O.tag" "$O"
    mv "$O.tag" "$O"
  done
  libtool -static -o "$WORK/$ARCH-cat.a" "$WORK/$ARCH"/*.o 2>/dev/null
  THIN+=("$WORK/$ARCH-cat.a")
done
lipo -create "${THIN[@]}" -output "$DST"
[[ "$(lipo -archs "$DST")" == *x86_64*arm64* || "$(lipo -archs "$DST")" == *arm64*x86_64* ]]
# Installation en un geste, puis index : un arrêt entre les deux est repris au prochain lancement.
mkdir "$WORK/$SLICE"
mv "$WORK/onnxruntime.framework" "$WORK/$SLICE/"
mv "$WORK/$SLICE" "$XC/$SLICE"
python3 -I - "$XC/Info.plist" "$SLICE" <<'PY'
import plistlib, sys
path, slice_id = sys.argv[1:]
with open(path, "rb") as source:
    info = plistlib.load(source)
info["AvailableLibraries"].append({
    "BinaryPath": "onnxruntime.framework/onnxruntime",
    "LibraryIdentifier": slice_id,
    "LibraryPath": "onnxruntime.framework",
    "SupportedArchitectures": ["arm64", "x86_64"],
    "SupportedPlatform": "ios",
    "SupportedPlatformVariant": "maccatalyst",
})
with open(path, "wb") as target:
    plistlib.dump(info, target)
PY
echo "Tranche ajoutée : $XC/$SLICE"
