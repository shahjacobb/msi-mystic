#!/bin/bash
# Builds "build/MSI Mystic.app". Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MSI Mystic.app"
BIN="$APP/Contents/MacOS/MSIMystic"
FLAGS=(-O -swift-version 5 -parse-as-library)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

swiftc "${FLAGS[@]}" -target arm64-apple-macos15.0 Sources/*.swift -o build/obj/MSIMystic-arm64
swiftc "${FLAGS[@]}" -target x86_64-apple-macos15.0 Sources/*.swift -o build/obj/MSIMystic-x86_64
lipo -create build/obj/MSIMystic-arm64 build/obj/MSIMystic-x86_64 -output "$BIN"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/*.png Resources/AppIcon.icns "$APP/Contents/Resources/"
rm -f "$APP/Contents/Resources/icon-preview.png"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/MSI Mystic.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/MSI Mystic.app"
fi
