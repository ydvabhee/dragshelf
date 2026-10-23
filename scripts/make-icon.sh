#!/bin/bash
# Usage: scripts/make-icon.sh  → Resources/AppIcon.icns (app bundle) + Resources/AppIcon.png (README)
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swift scripts/make-icon.swift "$TMP/icon-1024.png" >/dev/null
SET="$TMP/AppIcon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 256 256 "$TMP/icon-1024.png" --out Resources/AppIcon.png >/dev/null
echo "Resources/AppIcon.icns Resources/AppIcon.png"
