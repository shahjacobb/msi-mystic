#!/bin/bash
# Builds "build/MSI Light.app". Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MSI Light.app"
BIN="$APP/Contents/MacOS/MSILight"
FLAGS=(-O -swift-version 5 -parse-as-library)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

swiftc "${FLAGS[@]}" -target arm64-apple-macos15.0 Sources/*.swift -o build/obj/MSILight-arm64
swiftc "${FLAGS[@]}" -target x86_64-apple-macos15.0 Sources/*.swift -o build/obj/MSILight-x86_64
lipo -create build/obj/MSILight-arm64 build/obj/MSILight-x86_64 -output "$BIN"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/msi-logo.png Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/MSI Light.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/MSI Light.app"
fi
