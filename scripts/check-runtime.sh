#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/runtime-checks
swiftc -swift-version 5 -module-cache-path .build/clang-cache Sources/LocalWriter/LocalRuntime.swift Tests/RuntimeChecks/RuntimeChecks.swift -o .build/runtime-checks/check
.build/runtime-checks/check
