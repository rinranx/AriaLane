#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVES_DIR="${1:-$ROOT_DIR/outputs}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"

GENERATE_APPCAST=""
for search_root in \
  "$ROOT_DIR/.build/artifacts" \
  "${BUILD_ROOT:-/private/tmp/AriaLaneSwiftRelease}-arm64/artifacts" \
  "${BUILD_ROOT:-/private/tmp/AriaLaneSwiftRelease}-x86_64/artifacts"; do
  if [[ ! -d "$search_root" ]]; then
    continue
  fi
  GENERATE_APPCAST="$(
    find "$search_root" \
      -path "*/Sparkle/bin/generate_appcast" \
      -type f \
      -print \
      -quit
  )"
  if [[ -n "$GENERATE_APPCAST" ]]; then
    break
  fi
done
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "error: Sparkle generate_appcast tool not found; run swift package resolve first" >&2
  exit 1
fi
if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  echo "error: set DOWNLOAD_URL_PREFIX to the HTTPS release asset directory" >&2
  exit 1
fi
if [[ "$DOWNLOAD_URL_PREFIX" != https://* ]]; then
  echo "error: DOWNLOAD_URL_PREFIX must use HTTPS" >&2
  exit 1
fi

ARGUMENTS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --maximum-deltas 0
  --maximum-versions 3
)
if [[ -n "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  ARGUMENTS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi

"$GENERATE_APPCAST" "${ARGUMENTS[@]}" "$ARCHIVES_DIR"
