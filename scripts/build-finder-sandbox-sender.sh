#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/.build/FinderSandboxSender.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.itools.test.finder-sandbox-sender</string>
<key>CFBundleExecutable</key><string>FinderSandboxSender</string>
<key>CFBundleName</key><string>FinderSandboxSender</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path "$ROOT/.build/module-cache" -target x86_64-apple-macosx12.0 \
  scripts/finder-sandbox-sender.swift Sources/IToolsCore/FinderLaunchEvent.swift \
  Sources/IToolsCore/FinderBridge.swift Sources/IToolsCore/FinderActions.swift \
  -o "$APP/Contents/MacOS/FinderSandboxSender"
codesign --force --sign - --entitlements Extensions/FinderSync/Finder.entitlements "$APP"
codesign --verify --strict "$APP"
echo "$APP/Contents/MacOS/FinderSandboxSender"
