#!/usr/bin/env bash
# Builds the app's non-UI code (models, pricing, availability, search, demo backend) as a Swift
# package and runs SonoraTests. Works on macOS and Linux (no Xcode or simulator needed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Sources/SonoraCore" "$WORK/Tests/SonoraTests"
cp "$ROOT"/Sonora/Models/*.swift "$ROOT"/Sonora/Core/*.swift \
   "$ROOT"/Sonora/Services/Backend.swift "$ROOT"/Sonora/Services/MockData.swift "$ROOT"/Sonora/Services/MockBackend.swift \
   "$WORK/Sources/SonoraCore/"
if [[ "$(uname)" != "Darwin" ]]; then
  cp "$ROOT/LinuxSupport/CoreLocationShim.swift" "$WORK/Sources/SonoraCore/"
  sed -i 's/^import CoreLocation$//; s/^import UIKit$//' "$WORK"/Sources/SonoraCore/*.swift
fi
sed 's/@testable import Sonora/@testable import SonoraCore/' "$ROOT/SonoraTests/CoreTests.swift" > "$WORK/Tests/SonoraTests/CoreTests.swift"
if [[ "$(uname)" != "Darwin" ]]; then sed -i 's/^import CoreLocation$//' "$WORK/Tests/SonoraTests/CoreTests.swift"; fi

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "SonoraCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SonoraCore"),
        .testTarget(name: "SonoraTests", dependencies: ["SonoraCore"]),
    ]
)
SWIFT
cd "$WORK" && swift test
