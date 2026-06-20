#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_NAME="Moye"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/$APP_NAME-macOS"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS.zip"

APP_PATH="$("$ROOT_DIR/scripts/build-app.sh" Release | tail -n 1)"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

rm -rf "$WORK_DIR" "$ZIP_PATH"
mkdir -p "$WORK_DIR"

ditto "$APP_PATH" "$WORK_DIR/$APP_NAME.app"

pushd "$DIST_DIR" >/dev/null
ditto -c -k --norsrc --keepParent "$APP_NAME-macOS/$APP_NAME.app" "$ZIP_PATH"
popd >/dev/null

echo "$ZIP_PATH"
