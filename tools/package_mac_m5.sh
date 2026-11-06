#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Assemble l'app Mac à puce Apple (M5) : lexiques FR/EN/zh-Hans dans le paquet, signature locale (bac à sable), zip.
# Pas de moteur llama.cpp : l'IA locale passe par MLX, comme sur l'iPad.
# Usage : tools/package_mac_m5.sh <app construite> <lexique français> <dossier de sortie> <nom du zip>
set -euo pipefail
SRC=$1; LEXICON=$2; OUT=$3; ZIP=$4
ROOT=${0:A:h:h}
mkdir -p "$OUT"
[[ -e "$OUT/Kyokasho.app" ]] && trash "$OUT/Kyokasho.app"
ditto "$SRC" "$OUT/Kyokasho.app"
[[ "$(lipo -archs "$OUT/Kyokasho.app/Contents/MacOS/Kyokasho")" == arm64 ]]
python3 "$ROOT/tools/copy_bundled_lexicons.py" --source "${LEXICON:h}" --french "$LEXICON" \
  --app "$OUT/Kyokasho.app/Contents/Resources" --platform macos
codesign --force --deep -s - --entitlements "$ROOT/App/Kyokasho-Mac.entitlements" "$OUT/Kyokasho.app"
codesign --verify --deep --strict "$OUT/Kyokasho.app"
(cd "$OUT" && ditto -c -k --keepParent Kyokasho.app "$ZIP")
echo "$OUT/$ZIP"
