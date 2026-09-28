#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == "arm64" ]] || { echo "OpenPixel requires Apple Silicon." >&2; exit 1; }
bash scripts/bootstrap.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
swift build --disable-sandbox -c release --scratch-path .build/swift
app="$PWD/dist/OpenPixel.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Worker"
cp .build/swift/release/OpenPixel "$app/Contents/MacOS/OpenPixel"
cp AppInfo.plist "$app/Contents/Info.plist"
cp Worker/worker.py Worker/catalog.json Worker/requirements.lock "$app/Contents/Resources/Worker/"
ditto .build/runtime "$app/Contents/Resources/Runtime"
swift scripts/make_icon.swift
iconutil -c icns .build/OpenPixel.iconset -o "$app/Contents/Resources/OpenPixel.icns"
# Local development signature. Public distribution needs Developer ID/notarization.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built: $app"

