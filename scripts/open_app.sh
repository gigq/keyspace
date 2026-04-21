#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/Keyspace.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Installed app bundle not found:"
  echo "  $APP_PATH"
  echo "Run scripts/install_app.sh first."
  exit 1
fi

open "$APP_PATH"
