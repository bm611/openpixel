#!/bin/bash
# Packages dist/OpenPixel.app into a drag-to-Applications disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/OpenPixel.app"
[[ -d "$app" ]] || bash scripts/build.sh
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' AppInfo.plist)"
dmg="$PWD/dist/OpenPixel-$version.dmg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/OpenPixel.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "OpenPixel" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
echo "Built: $dmg"
