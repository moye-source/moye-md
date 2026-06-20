#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/NativeMarkdownEditor.xcodeproj"
SCHEME="NativeMarkdownEditor"
CONFIGURATION="${1:-Release}"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ TARGET_BUILD_DIR = / { target=$2 } / FULL_PRODUCT_NAME = / { product=$2 } END { print target "/" product }'
