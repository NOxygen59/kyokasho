#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Assemble l'app Mac Intel : lexiques FR/EN/zh-Hans (cherchés à côté du français) et moteur llama-server dans le paquet, signature du moteur (bac à sable hérité) puis
# de l'app, zip. Usage : tools/package_mac_intel.sh <app construite> <llama-server> <lexique> <dossier de sortie> <nom du zip>
set -euo pipefail
SRC=$1; ENGINE=$2; LEXICON=$3; OUT=$4; ZIP=$5
ROOT=${0:A:h:h}
mkdir -p "$OUT"
ditto "$SRC" "$OUT/Kyokasho.app"
python3 "$ROOT/tools/copy_bundled_lexicons.py" --source "${LEXICON:h}" --french "$LEXICON" \
  --app "$OUT/Kyokasho.app/Contents/Resources" --platform macos
cp "$ENGINE" "$OUT/Kyokasho.app/Contents/MacOS/llama-server"
codesign --force --deep -s - --entitlements "$ROOT/App/Kyokasho-Mac.entitlements" "$OUT/Kyokasho.app"
codesign --force -s - --entitlements "$ROOT/App/LlamaServer-Mac.entitlements" "$OUT/Kyokasho.app/Contents/MacOS/llama-server"
codesign --force -s - --entitlements "$ROOT/App/Kyokasho-Mac.entitlements" "$OUT/Kyokasho.app"
codesign --verify --deep --strict "$OUT/Kyokasho.app"
(cd "$OUT" && ditto -c -k --keepParent Kyokasho.app "$ZIP")
echo "$OUT/$ZIP"
