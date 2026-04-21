#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Keyspace"
EXECUTABLE_NAME="keyspace"
BUNDLE_ID="com.gigq.keyspace"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ARCHS="${ARCHS:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-0}"

cd "$ROOT_DIR"

# Prefer the full Xcode toolchain when the active developer directory points at
# older Command Line Tools. This avoids tool-version mismatches for local builds.
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$(xcode-select -p 2>/dev/null || true)" == "/Library/Developer/CommandLineTools" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

build_slice() {
  local arch="$1"
  local scratch_path="$ROOT_DIR/.build/$arch"
  local triple="${arch}-apple-macosx${MINIMUM_SYSTEM_VERSION}"

  rm -rf "$scratch_path"
  swift build \
    --triple "$triple" \
    --scratch-path "$scratch_path" \
    -c "$CONFIGURATION" \
    --product "$EXECUTABLE_NAME" \
    >/dev/null

  find "$scratch_path" -type f -path "*/$CONFIGURATION/$EXECUTABLE_NAME" -perm -111 | head -n 1
}

declare -a executable_slices=()
for arch in $ARCHS; do
  executable_slices+=("$(build_slice "$arch")")
done

for executable_path in "${executable_slices[@]}"; do
  if [[ ! -x "$executable_path" ]]; then
    echo "Built executable not found at:"
    echo "  $executable_path"
    exit 1
  fi
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

if [[ "${#executable_slices[@]}" -eq 1 ]]; then
  cp "${executable_slices[0]}" "$MACOS_DIR/$APP_NAME"
else
  lipo -create "${executable_slices[@]}" -output "$MACOS_DIR/$APP_NAME"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  "$ROOT_DIR/scripts/build_icon.sh"
fi
cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

codesign_args=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign_args+=(--timestamp)
  if [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
    codesign_args+=(--options runtime)
  fi
fi

codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null 2>&1

echo "Built app bundle at:"
echo "  $APP_DIR"
