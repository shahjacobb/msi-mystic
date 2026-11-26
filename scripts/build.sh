#!/bin/bash
# Builds "build/MSI Monitor Lighting.app". Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/MSI Monitor Lighting.app"
BIN="$APP/Contents/MacOS/MSIMonitorLighting"
FLAGS=(-O -swift-version 5 -parse-as-library)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

swiftc "${FLAGS[@]}" -target arm64-apple-macos15.0 Sources/*.swift -o build/obj/MSIMonitorLighting-arm64
swiftc "${FLAGS[@]}" -target x86_64-apple-macos15.0 Sources/*.swift -o build/obj/MSIMonitorLighting-x86_64
lipo -create build/obj/MSIMonitorLighting-arm64 build/obj/MSIMonitorLighting-x86_64 -output "$BIN"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/*.png Resources/AppIcon.icns "$APP/Contents/Resources/"
rm -f "$APP/Contents/Resources/icon-preview.png"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/MSI Monitor Lighting.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/MSI Monitor Lighting.app"
fi
