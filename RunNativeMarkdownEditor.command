#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="NativeMarkdownEditor.xcodeproj"
SCHEME="NativeMarkdownEditor"
CONFIGURATION="Debug"
LOG_FILE="/tmp/native-markdown-editor-build.log"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  build >"$LOG_FILE" 2>&1

BUILD_SETTINGS="$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null)"

TARGET_BUILD_DIR="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F'= ' '/ TARGET_BUILD_DIR = / { print $2; exit }')"
FULL_PRODUCT_NAME="$(printf '%s\n' "$BUILD_SETTINGS" | awk -F'= ' '/ FULL_PRODUCT_NAME = / { print $2; exit }')"
APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded, but the app bundle was not found."
  echo "Expected: $APP_PATH"
  echo "Build log: $LOG_FILE"
  exit 1
fi

pkill -x NativeMarkdownEditor >/dev/null 2>&1 || true
sleep 0.5
open -n "$APP_PATH"
