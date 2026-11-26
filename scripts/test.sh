#!/bin/bash
# Packet regression tests. No monitor needed.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos15.0" \
    Sources/MSIDevice.swift Sources/LightController.swift Tests/main.swift -o build/packet-tests
build/packet-tests "$PWD"
