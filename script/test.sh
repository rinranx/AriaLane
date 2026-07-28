#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$ROOT_DIR/.build/module-cache"
BUILD_ROOT="${ARIALANE_TEST_BUILD_ROOT:-/private/tmp/AriaLaneSwiftBuild}"

cd "$ROOT_DIR"
mkdir -p "$CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [[ -d "/Applications/Xcode-beta 2.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta 2.app/Contents/Developer"
elif [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

swift test \
  --disable-sandbox \
  --scratch-path "$BUILD_ROOT" \
  "$@"
