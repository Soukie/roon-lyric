#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RoonLyric"
DISPLAY_NAME="Roon Lyric"
BUNDLE_ID="com.soukie.RoonLyric"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
ASSET_DIR="$ROOT_DIR/assets/releases"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

VERSION="0.1.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ALLOW_UNSIGNED=0
NOTARIZE=0
SWIFT_BUILD_FLAGS=(--disable-sandbox)

usage() {
  cat <<USAGE
Usage: $0 [--version VERSION] [--build BUILD] [--allow-unsigned] [--notarize]

Environment:
  DEVELOPER_ID_APPLICATION  Developer ID Application signing identity.
  NOTARY_PROFILE            notarytool keychain profile when --notarize is used.
  DEVELOPER_DIR             Defaults to /Applications/Xcode.app/Contents/Developer when present.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --allow-unsigned)
      ALLOW_UNSIGNED=1
      shift
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$SIGN_IDENTITY" && "$ALLOW_UNSIGNED" -ne 1 ]]; then
  echo "error: DEVELOPER_ID_APPLICATION is required for a signed release." >&2
  echo "       Use --allow-unsigned only for local smoke-test DMGs." >&2
  exit 2
fi

mkdir -p "$DIST_DIR" "$ASSET_DIR"
cd "$ROOT_DIR"

/usr/bin/swift build -c release "${SWIFT_BUILD_FLAGS[@]}"
BIN_DIR="$(/usr/bin/swift build -c release "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
/bin/cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/bin/cp "$ROOT_DIR/Resources/RoonLyric.icns" "$APP_BUNDLE/Contents/Resources/RoonLyric.icns"

/usr/bin/plutil -create xml1 "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "$DISPLAY_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIconFile -string "RoonLyric.icns" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$APP_BUNDLE/Contents/Info.plist"

if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
  echo "warning: building unsigned local DMG because --allow-unsigned was provided." >&2
fi

/usr/bin/touch "$APP_BUNDLE"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

DMG_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/roon-lyric-dmg.XXXXXX")"
trap '/bin/rm -rf "$DMG_ROOT"' EXIT
/bin/cp -R "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_ROOT/Applications"

DMG_PATH="$ASSET_DIR/RoonLyric-$VERSION-macOS.dmg"
/bin/rm -f "$DMG_PATH"
if ! /usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"; then
  echo "warning: hdiutil create failed; falling back to hdiutil makehybrid." >&2
  /bin/rm -f "$DMG_PATH"
  /usr/bin/hdiutil makehybrid \
    -hfs \
    -hfs-volume-name "$DISPLAY_NAME" \
    -o "$DMG_PATH" \
    "$DMG_ROOT"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "error: NOTARY_PROFILE is required when --notarize is used." >&2
    exit 3
  fi
  /usr/bin/xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$DMG_PATH"
fi

echo "Release DMG: $DMG_PATH"
