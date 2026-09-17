#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/overlay-checks
swiftc -swift-version 5 -module-cache-path .build/clang-cache Sources/LocalWriter/Overlay.swift Tests/OverlayChecks/OverlayChecks.swift -o .build/overlay-checks/check
.build/overlay-checks/check
