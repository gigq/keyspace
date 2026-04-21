#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Keyspace"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_DIR="${APP_DIR:-$BUILD_DIR/$APP_NAME.app}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/.build/dist}"
STAGING_DIR="$ROOT_DIR/.build/dmg"
VERSION="${VERSION:-0.1.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
DMG_NAME="${DMG_NAME:-Keyspace-${VERSION}-universal.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Keyspace}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found at:"
  echo "  $APP_DIR"
  exit 1
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  >/dev/null

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH" >/dev/null
fi

echo "Built disk image at:"
echo "  $DMG_PATH"
