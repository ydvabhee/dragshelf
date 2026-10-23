#!/bin/bash
# Usage: scripts/make-dmg.sh  → build/DragShelf.dmg (release build, drag-to-Applications layout)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
scripts/build-app.sh release >/dev/null
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/DragShelf.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=build/DragShelf.dmg
hdiutil create -volname "DragShelf $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
echo "$DMG ($VERSION)"
