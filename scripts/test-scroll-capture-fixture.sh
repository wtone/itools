#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/iTools.app}"
FIXTURE="$ROOT/.build/ScrollCaptureFixture.app"
OUTPUT="$ROOT/.build/scroll-capture-fixture-check"
mkdir -p "$FIXTURE/Contents/MacOS" "$ROOT/.build/module-cache" "$OUTPUT"
cat > "$FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ScrollFixture</string><key>CFBundleIdentifier</key><string>app.itools.scrollfixturedebug</string><key>CFBundleName</key><string>iTools Capture Fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$ROOT/.build/module-cache" "$ROOT/scripts/scroll-capture-fixture.swift" -o "$FIXTURE/Contents/MacOS/ScrollFixture"
"$FIXTURE/Contents/MacOS/ScrollFixture" > "$OUTPUT/fixture.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true' EXIT
sleep 2
ITOOLS_SMOKE_OUTPUT="$OUTPUT" "$APP/Contents/MacOS/ITools" --smoke-test --capture-editor-check --scroll-fixture-check
