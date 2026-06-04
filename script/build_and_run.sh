#!/usr/bin/env bash
set -euo pipefail

APP_NAME="RoonLyric"
BUNDLE_ID="com.soukie.RoonLyric"
APP_VERSION="0.1.0"
APP_BUILD="1"
CONFIGURATION="debug"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

usage() {
  echo "Usage: $0 [--verify] [--logs]"
}

VERIFY=0
LOGS=0
SWIFT_BUILD_FLAGS=(--disable-sandbox)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)
      VERIFY=1
      ;;
    --logs)
      LOGS=1
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
  shift
done

cd "$ROOT_DIR"

/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
BIN_DIR="$(/usr/bin/swift build -c "$CONFIGURATION" "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
/bin/cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -f "$ROOT_DIR/Resources/RoonLyric.icns" ]]; then
  /bin/cp "$ROOT_DIR/Resources/RoonLyric.icns" "$APP_BUNDLE/Contents/Resources/RoonLyric.icns"
fi

/usr/bin/plutil -create xml1 "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Roon Lyric" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIconFile -string "RoonLyric.icns" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$APP_BUILD" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$APP_BUNDLE/Contents/Info.plist"

/usr/bin/touch "$APP_BUNDLE"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

/usr/bin/open -n "$APP_BUNDLE"

if [[ "$VERIFY" -eq 1 ]]; then
  sleep 2
  /usr/bin/pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running from $APP_BUNDLE"
fi

if [[ "$LOGS" -eq 1 ]]; then
  /usr/bin/log stream --info --predicate "process == '$APP_NAME'"
fi
