#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Keyspace"
SOURCE_APP="$ROOT_DIR/.build/app/$APP_NAME.app"
TARGET_DIR="/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME.app"
LEGACY_APP="$TARGET_DIR/Keysmith.app"

"$ROOT_DIR/scripts/build_app.sh"

rm -rf "$LEGACY_APP"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
codesign --force --sign - "$TARGET_APP" >/dev/null 2>&1 || true

echo "Installed app bundle to:"
echo "  $TARGET_APP"
