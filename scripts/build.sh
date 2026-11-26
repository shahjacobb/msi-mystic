#!/bin/bash
# Builds "build/Lume.app". Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Lume.app"
BIN="$APP/Contents/MacOS/Lume"
FLAGS=(-O -swift-version 5 -parse-as-library)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

swiftc "${FLAGS[@]}" -target arm64-apple-macos15.0 Sources/*.swift -o build/obj/Lume-arm64
swiftc "${FLAGS[@]}" -target x86_64-apple-macos15.0 Sources/*.swift -o build/obj/Lume-x86_64
lipo -create build/obj/Lume-arm64 build/obj/Lume-x86_64 -output "$BIN"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/msi-logo.png Resources/msi-wordmark-2020.png Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/Lume.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Lume.app"
fi
