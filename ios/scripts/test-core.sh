#!/usr/bin/env bash
# Builds the app's non-UI code (models, pricing, availability, search, demo backend) as a Swift
# package and runs EasySeshTests. Works on macOS and Linux (no Xcode or simulator needed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Sources/EasySeshCore" "$WORK/Tests/EasySeshTests"
cp "$ROOT"/EasySesh/Models/*.swift "$ROOT"/EasySesh/Core/*.swift "$ROOT"/EasySesh/Services/Backend.swift "$WORK/Sources/EasySeshCore/"
if [[ "$(uname)" != "Darwin" ]]; then
  cp "$ROOT/LinuxSupport/CoreLocationShim.swift" "$WORK/Sources/EasySeshCore/"
  sed -i 's/^import CoreLocation$//; s/^import UIKit$//' "$WORK"/Sources/EasySeshCore/*.swift
fi
for f in "$ROOT"/EasySeshTests/*.swift; do
  sed 's/@testable import EasySesh$/@testable import EasySeshCore/' "$f" > "$WORK/Tests/EasySeshTests/$(basename "$f")"
done
if [[ "$(uname)" != "Darwin" ]]; then sed -i 's/^import CoreLocation$//' "$WORK"/Tests/EasySeshTests/*.swift; fi

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "EasySeshCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "EasySeshCore"),
        .testTarget(name: "EasySeshTests", dependencies: ["EasySeshCore"]),
    ]
)
SWIFT
cd "$WORK" && swift test
