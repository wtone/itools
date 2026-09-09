#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-x86_64}"
SOURCE="$ROOT/.build/7zip-source"
mkdir -p "$SOURCE"
tar -xJf "$ROOT/Vendor/7zip/7z2603-src.tar.xz" -C "$SOURCE"
cd "$SOURCE/CPP/7zip/Bundles/Alone2"
if [[ "$ARCH" == "universal" ]]; then ARCHES=(x86_64 arm64); else ARCHES=("$ARCH"); fi
BINS=()
for ITEM in "${ARCHES[@]}"; do
  case "$ITEM" in
    x86_64) MAKEFILE="../../cmpl_mac_x64.mak"; OUTPUT="b/m_x64/7zz" ;;
    arm64) MAKEFILE="../../cmpl_mac_arm64.mak"; OUTPUT="b/m_arm64/7zz" ;;
    *) echo "Unsupported architecture" >&2; exit 2 ;;
  esac
  MACOSX_DEPLOYMENT_TARGET=12.0 make -j4 -f "$MAKEFILE" MY_ARCH="-arch $ITEM -mmacosx-version-min=12.0"
  BINS+=("$OUTPUT")
done
if [[ "$ARCH" == "universal" ]]; then
  lipo -create "${BINS[@]}" -output "$ROOT/Vendor/7zip/7zz"
else
  cp "${BINS[0]}" "$ROOT/Vendor/7zip/7zz"
fi
