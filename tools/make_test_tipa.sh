#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Fait d'un .tipa une app « Kyōkasho Test », installable à côté de la vraie avec sa propre bibliothèque :
# autre identifiant, donc autre conteneur de données. Pour essayer sauvegarde, restauration et retour vers une ancienne
# version sans toucher à la bibliothèque réelle. Usage : tools/make_test_tipa.sh Kyokasho-1.4.7.tipa [dossier de sortie]
set -euo pipefail
ROOT="${0:A:h:h}"
SOURCE="${1:?Paquet .tipa à transformer}"
OUTPUT="${2:-${SOURCE:h}}"
WORK="$(mktemp -d)"
trap 'trash "$WORK"' EXIT
NAME="${SOURCE:t:r}"
unzip -q "$SOURCE" -d "$WORK"
APP="$WORK/Payload/Kyokasho.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.noxygen59.kyokasho.test" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Kyōkasho Test" "$APP/Info.plist"
# Les droits nomment l'identifiant de l'app : ils doivent suivre, sinon iOS confondrait les deux installations.
sed 's/fr\.noxygen59\.kyokasho/fr.noxygen59.kyokasho.test/g' "$ROOT/packaging/entitlements-trollstore.plist" > "$WORK/droits.plist"
ldid -S"$WORK/droits.plist" "$APP/Kyokasho"
TARGET="${OUTPUT:A}/${NAME/Kyokasho/Kyokasho-Test}.tipa"
(cd "$WORK" && zip -qry "$TARGET" Payload)
print "OK : $TARGET"
