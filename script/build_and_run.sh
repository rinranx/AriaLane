#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="AriaLane"
BUNDLE_ID="dev.arialane.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
CACHE_DIR="$ROOT_DIR/.build/module-cache"
BUILD_ROOT="/private/tmp/AriaLaneSwiftBuild"
STAGE_DIR="/private/tmp/AriaLaneDevBundle"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
DIST_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

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

swift build --disable-sandbox --scratch-path "$BUILD_ROOT" --product "$APP_NAME"
BUILD_BINARY="$(swift build --disable-sandbox --scratch-path "$BUILD_ROOT" --show-bin-path)/$APP_NAME"
SPARKLE_FRAMEWORK="$(
  find "$BUILD_ROOT/artifacts" \
    -path "*/macos-arm64_x86_64/Sparkle.framework" \
    -type d \
    -print \
    -quit
)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework was not found in SwiftPM artifacts" >&2
  exit 1
fi

rm -rf "$STAGE_DIR" "$DIST_APP_BUNDLE"
mkdir -p "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
ditto "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$ROOT_DIR/Resources/AppIcon.png" "$APP_RESOURCES/AppIcon.png"
ditto "$ROOT_DIR/Resources/Fonts" "$APP_RESOURCES/Fonts"
ditto "$ROOT_DIR/Resources/en.lproj" "$APP_RESOURCES/en.lproj"
ditto "$ROOT_DIR/Resources/Licenses" "$APP_RESOURCES/Licenses"
cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/Licenses/AriaLane-GPL-3.0.txt"
cp "$ROOT_DIR/COPYRIGHT" "$APP_RESOURCES/Licenses/AriaLane-COPYRIGHT.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/Licenses/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
chmod +x "$APP_BINARY"

xattr -cr "$APP_BUNDLE"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -nE 's/.*"(Apple Development[^"]*|Developer ID Application[^"]*|Mac Developer[^"]*)".*/\1/p' |
      head -n 1
  )"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "warning: no Apple signing identity found; macOS notifications need a development or distribution signature" >&2
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noqtn "$APP_BUNDLE" "$DIST_APP_BUNDLE"

# Documents may be backed by File Provider, which can race to add Finder metadata
# while an app bundle is copied. Strip it and retry the strict verification.
DIST_SIGNATURE_VALID=false
DIST_VERIFY_OUTPUT=""
for _ in {1..5}; do
  xattr -cr "$DIST_APP_BUNDLE"
  xattr -rd com.apple.FinderInfo "$DIST_APP_BUNDLE" 2>/dev/null || true
  xattr -rd com.apple.ResourceFork "$DIST_APP_BUNDLE" 2>/dev/null || true
  if DIST_VERIFY_OUTPUT="$(
    codesign --verify --deep --strict --verbose=2 "$DIST_APP_BUNDLE" 2>&1
  )"; then
    DIST_SIGNATURE_VALID=true
    break
  fi
done
if [[ "$DIST_SIGNATURE_VALID" != true ]]; then
  if [[ "$DIST_VERIFY_OUTPUT" == *"resource fork, Finder information, or similar detritus not allowed"* ]] \
    && codesign --verify --deep --verbose=2 "$DIST_APP_BUNDLE"; then
    echo "warning: File Provider metadata prevents strict verification; the copied app signature is otherwise valid" >&2
  else
    printf '%s\n' "$DIST_VERIFY_OUTPUT" >&2
    exit 1
  fi
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build|build)
    echo "$DIST_APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not stay running" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
