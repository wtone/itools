#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache
xcrun swiftc -module-cache-path .build/module-cache -framework AppKit \
  scripts/LoginItemTests/main.swift Sources/IToolsCore/LoginLaunch.swift -o .build/test-login-item
exec .build/test-login-item "${1:?Pass the app bundle path}" "${2:?Pass a fresh output directory}"
