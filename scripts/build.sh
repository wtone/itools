#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIGURATION:-release}"
ARCH="${ARCH:-x86_64}"
IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" && "$ARCH" != "universal" ]]; then
  echo "ARCH must be x86_64, arm64 or universal" >&2; exit 2
fi
mkdir -p "$ROOT/.build/cache" "$ROOT/.build/module-cache" "$ROOT/dist"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
if [[ "$ARCH" == "universal" ]]; then ARCHES=(x86_64 arm64); else ARCHES=("$ARCH"); fi
if ! lipo Vendor/7zip/7zz -verify_arch "${ARCHES[@]}" >/dev/null 2>&1; then
  ARCH="$ARCH" ./scripts/build-7zip.sh
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for TARGET_ARCH in "${ARCHES[@]}"; do
  swift build --disable-sandbox --cache-path "$ROOT/.build/cache" --scratch-path "$ROOT/.build" --configuration "$CONFIG" --arch "$TARGET_ARCH"
done
APP="$ROOT/dist/iTools.app"
if [[ -e "$APP" ]]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns/IToolsFinder.appex/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Extensions/FinderSync/Info.plist "$APP/Contents/PlugIns/IToolsFinder.appex/Contents/Info.plist"
BINS=()
EXTENSIONS=()
for TARGET_ARCH in "${ARCHES[@]}"; do
  BIN="$(swift build --disable-sandbox --cache-path "$ROOT/.build/cache" --scratch-path "$ROOT/.build" --configuration "$CONFIG" --arch "$TARGET_ARCH" --show-bin-path)"
  BINS+=("$BIN/ITools")
  EXTENSION="$ROOT/.build/IToolsFinder-$TARGET_ARCH"
  xcrun swiftc -swift-version 5 -O -whole-module-optimization -sdk "$SDK" \
    -target "$TARGET_ARCH-apple-macosx12.0" -module-name IToolsFinder \
    -application-extension -parse-as-library -emit-executable -Xlinker -e -Xlinker _NSExtensionMain \
    -framework AppKit -framework FinderSync Extensions/FinderSync/FinderSync.swift Sources/IToolsCore/FinderActions.swift Sources/IToolsCore/FinderBridge.swift -o "$EXTENSION"
  EXTENSIONS+=("$EXTENSION")
done
if [[ "$ARCH" == "universal" ]]; then
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/ITools"
  lipo -create "${EXTENSIONS[@]}" -output "$APP/Contents/PlugIns/IToolsFinder.appex/Contents/MacOS/IToolsFinder"
else
  cp "${BINS[0]}" "$APP/Contents/MacOS/ITools"
  cp "${EXTENSIONS[0]}" "$APP/Contents/PlugIns/IToolsFinder.appex/Contents/MacOS/IToolsFinder"
fi
xcrun swift scripts/make-icon.swift "$ROOT/.build/AppIcon.iconset"
iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/ThirdParty/7zip"
cp Vendor/7zip/7zz "$APP/Contents/Helpers/7zz"
cp Vendor/7zip/License.txt Vendor/7zip/COPYING.LGPL.txt Vendor/7zip/7z2603-src.tar.xz Vendor/7zip/PROVENANCE.md "$APP/Contents/Resources/ThirdParty/7zip/"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Helpers/7zz"
WORKER="$APP/Contents/Helpers/iTools Finder Actions.app"
mkdir -p "$WORKER/Contents/MacOS" "$WORKER/Contents/Resources"
cp "$APP/Contents/MacOS/ITools" "$WORKER/Contents/MacOS/IToolsFinderActions"
cp Resources/FinderActions-Info.plist "$WORKER/Contents/Info.plist"
cp "$APP/Contents/Resources/AppIcon.icns" "$WORKER/Contents/Resources/AppIcon.icns"
codesign "${SIGN_FLAGS[@]}" "$WORKER"
codesign "${SIGN_FLAGS[@]}" --entitlements Extensions/FinderSync/Finder.entitlements "$APP/Contents/PlugIns/IToolsFinder.appex"
codesign "${SIGN_FLAGS[@]}" --entitlements Resources/ITools.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$APP/Contents/MacOS/ITools"
echo "Built: $APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
