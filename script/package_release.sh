#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AriaLane"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")}"

BUILD_ROOT="${BUILD_ROOT:-/private/tmp/AriaLaneSwiftRelease}"
ARM_BUILD_ROOT="${BUILD_ROOT}-arm64"
X86_BUILD_ROOT="${BUILD_ROOT}-x86_64"
SPM_CACHE_ROOT="${SPM_CACHE_ROOT:-/private/tmp/AriaLaneSwiftPMCache}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/outputs}"
OUTPUT_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS-universal.zip"
DMG_OUTPUT_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION-macOS-universal.dmg"
PACKAGE_STAGE="$(mktemp -d /private/tmp/AriaLanePackage.XXXXXX)"
APP_BUNDLE="$PACKAGE_STAGE/$APP_NAME.app"

cleanup() {
  rm -rf "$PACKAGE_STAGE"
}
trap cleanup EXIT

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode-beta 2.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta 2.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p \
  "$OUTPUT_DIR" \
  "$SPM_CACHE_ROOT/cache" \
  "$SPM_CACHE_ROOT/config" \
  "$SPM_CACHE_ROOT/security" \
  "$SPM_CACHE_ROOT/modules"

export CLANG_MODULE_CACHE_PATH="$SPM_CACHE_ROOT/modules/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$SPM_CACHE_ROOT/modules/swift"

build_architecture() {
  local architecture="$1"
  local scratch_path="$2"
  local triple="${architecture}-apple-macosx14.0"

  swift build \
    --disable-sandbox \
    --disable-keychain \
    --cache-path "$SPM_CACHE_ROOT/cache" \
    --config-path "$SPM_CACHE_ROOT/config" \
    --security-path "$SPM_CACHE_ROOT/security" \
    --configuration release \
    --scratch-path "$scratch_path" \
    --triple "$triple" \
    --sdk "$SDK_PATH" \
    --product "$APP_NAME" \
    --only-use-versions-from-resolved-file \
    -debug-info-format none
}

binary_path() {
  local architecture="$1"
  local scratch_path="$2"
  local triple="${architecture}-apple-macosx14.0"

  swift build \
    --disable-sandbox \
    --disable-keychain \
    --cache-path "$SPM_CACHE_ROOT/cache" \
    --config-path "$SPM_CACHE_ROOT/config" \
    --security-path "$SPM_CACHE_ROOT/security" \
    --configuration release \
    --scratch-path "$scratch_path" \
    --triple "$triple" \
    --sdk "$SDK_PATH" \
    --show-bin-path
}

cd "$ROOT_DIR"
build_architecture "arm64" "$ARM_BUILD_ROOT"
build_architecture "x86_64" "$X86_BUILD_ROOT"

ARM_BINARY="$(binary_path "arm64" "$ARM_BUILD_ROOT")/$APP_NAME"
X86_BINARY="$(binary_path "x86_64" "$X86_BUILD_ROOT")/$APP_NAME"

mkdir -p \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources" \
  "$APP_BUNDLE/Contents/Frameworks"

xcrun lipo -create \
  "$ARM_BINARY" \
  "$X86_BINARY" \
  -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

ARCHITECTURES="$(xcrun lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
if [[ "$ARCHITECTURES" != *"arm64"* || "$ARCHITECTURES" != *"x86_64"* ]]; then
  echo "error: expected arm64 and x86_64 slices, found: $ARCHITECTURES" >&2
  exit 1
fi

SPARKLE_FRAMEWORK="$(
  find "$ARM_BUILD_ROOT/artifacts" \
    -path "*/macos-arm64_x86_64/Sparkle.framework" \
    -type d \
    -print \
    -quit
)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework was not found in SwiftPM artifacts" >&2
  exit 1
fi

ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
cp "$ROOT_DIR/Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
ditto "$ROOT_DIR/Resources/Fonts" "$APP_BUNDLE/Contents/Resources/Fonts"
ditto "$ROOT_DIR/Resources/en.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"
ditto "$ROOT_DIR/Resources/Licenses" "$APP_BUNDLE/Contents/Resources/Licenses"
cp "$ROOT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/Licenses/AriaLane-GPL-3.0.txt"
cp "$ROOT_DIR/COPYRIGHT" "$APP_BUNDLE/Contents/Resources/Licenses/AriaLane-COPYRIGHT.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
if [[ -n "$SPARKLE_FEED_URL" || -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY must be supplied together" >&2
    exit 1
  fi
  if [[ "$SPARKLE_FEED_URL" != https://* ]]; then
    echo "error: SPARKLE_FEED_URL must use HTTPS" >&2
    exit 1
  fi

  plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$APP_BUNDLE/Contents/Info.plist"
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$APP_BUNDLE/Contents/Info.plist"
  plutil -replace SUVerifyUpdateBeforeExtraction -bool true "$APP_BUNDLE/Contents/Info.plist"
fi

xattr -cr "$APP_BUNDLE"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -nE 's/.*"(Developer ID Application[^"]*)".*/\1/p' |
      head -n 1
  )"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      sed -nE 's/.*"(Apple Development[^"]*|Mac Developer[^"]*)".*/\1/p' |
      head -n 1
  )"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi

IDENTITY_DESCRIPTION="$SIGNING_IDENTITY"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  MATCHED_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null |
      grep -F "$SIGNING_IDENTITY" |
      head -n 1 ||
      true
  )"
  if [[ -n "$MATCHED_IDENTITY" ]]; then
    IDENTITY_DESCRIPTION="$MATCHED_IDENTITY"
  fi
fi

IS_DEVELOPER_ID=false
if [[ "$IDENTITY_DESCRIPTION" == *"Developer ID Application"* ]]; then
  IS_DEVELOPER_ID=true
fi

if [[ "${REQUIRE_DISTRIBUTION_SIGNING:-0}" == "1" && "$IS_DEVELOPER_ID" != true ]]; then
  echo "error: a Developer ID Application certificate is required for this release" >&2
  exit 1
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "warning: using an ad-hoc signature; this archive is for local testing only" >&2
  codesign --force --sign - "$APP_BUNDLE"
else
  SPARKLE_VERSION="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
  TIMESTAMP_ARGUMENT="--timestamp=none"
  if [[ "$IS_DEVELOPER_ID" == true ]]; then
    TIMESTAMP_ARGUMENT="--timestamp"
  fi

  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    "$SPARKLE_VERSION/XPCServices/Installer.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    --preserve-metadata=entitlements \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    "$SPARKLE_VERSION/Autoupdate"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    "$SPARKLE_VERSION/Updater.app"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$TIMESTAMP_ARGUMENT" \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if ! otool -L "$APP_BUNDLE/Contents/MacOS/$APP_NAME" |
  grep -q "@rpath/Sparkle.framework/Versions/B/Sparkle"; then
  echo "error: packaged executable does not link to embedded Sparkle.framework" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"
if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$IS_DEVELOPER_ID" != true ]]; then
    echo "error: notarization requires Developer ID Application signing" >&2
    exit 1
  fi

  NOTARY_ARCHIVE="$PACKAGE_STAGE/$APP_NAME-notarization.zip"
  COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr --noqtn \
    "$APP_BUNDLE" "$NOTARY_ARCHIVE"

  NOTARY_ARGUMENTS=(
    submit
    "$NOTARY_ARCHIVE"
    --keychain-profile "$NOTARY_PROFILE"
    --wait
    --timeout 30m
  )
  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
  fi
  xcrun notarytool "${NOTARY_ARGUMENTS[@]}"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
fi

ARCHIVE_PATH="$PACKAGE_STAGE/$APP_NAME-$VERSION-macOS-universal.zip"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr --noqtn \
  "$APP_BUNDLE" "$ARCHIVE_PATH"
cp "$ARCHIVE_PATH" "$OUTPUT_PATH"

DMG_ROOT="$PACKAGE_STAGE/dmg-root"
DMG_PATH="$PACKAGE_STAGE/$APP_NAME-$VERSION-macOS-universal.dmg"
mkdir -p "$DMG_ROOT"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noqtn \
  "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"
cp "$DMG_PATH" "$DMG_OUTPUT_PATH"

echo "Archive: $OUTPUT_PATH"
echo "Disk image: $DMG_OUTPUT_PATH"
echo "Architectures: $ARCHITECTURES"
echo "Signing identity: $IDENTITY_DESCRIPTION"
if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "Notarization: stapled"
else
  echo "Notarization: not requested"
fi
shasum -a 256 "$OUTPUT_PATH" "$DMG_OUTPUT_PATH"
