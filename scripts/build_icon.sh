#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$ROOT_DIR/Resources"
BUILD_DIR="$ROOT_DIR/.build/icon"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
MASTER_PNG="$BUILD_DIR/AppIcon.png"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"

if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$(xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$BUILD_DIR" "$ICONSET_DIR" "$RESOURCES_DIR"

swift "$ROOT_DIR/scripts/make_icon.swift" "$MASTER_PNG"

sizes=(16 32 64 128 256 512 1024)
for px in "${sizes[@]}"; do
  sips -z "$px" "$px" "$MASTER_PNG" --out "$BUILD_DIR/icon_${px}.png" >/dev/null
done

cp "$BUILD_DIR/icon_16.png"   "$ICONSET_DIR/icon_16x16.png"
cp "$BUILD_DIR/icon_32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
cp "$BUILD_DIR/icon_32.png"   "$ICONSET_DIR/icon_32x32.png"
cp "$BUILD_DIR/icon_64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
cp "$BUILD_DIR/icon_128.png"  "$ICONSET_DIR/icon_128x128.png"
cp "$BUILD_DIR/icon_256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
cp "$BUILD_DIR/icon_256.png"  "$ICONSET_DIR/icon_256x256.png"
cp "$BUILD_DIR/icon_512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
cp "$BUILD_DIR/icon_512.png"  "$ICONSET_DIR/icon_512x512.png"
cp "$BUILD_DIR/icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Built icon at:"
echo "  $ICNS_PATH"
