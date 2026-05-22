#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/app-metadata.sh"

CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEFAULT_APP_OUTPUT_ROOT="$ROOT_DIR/.build/app"
APP_OUTPUT_ROOT="${APP_OUTPUT_ROOT:-$DEFAULT_APP_OUTPUT_ROOT}"

if [[ "$APP_OUTPUT_ROOT" == "$DEFAULT_APP_OUTPUT_ROOT" && "$ROOT_DIR" == *"/Mobile Documents/"* ]]; then
  REAL_APP_OUTPUT_ROOT="${TMPDIR:-/tmp}/pr-review-desk-app-output"
  rm -rf "$REAL_APP_OUTPUT_ROOT" "$DEFAULT_APP_OUTPUT_ROOT"
  mkdir -p "$REAL_APP_OUTPUT_ROOT" "$ROOT_DIR/.build"
  ln -s "$REAL_APP_OUTPUT_ROOT" "$DEFAULT_APP_OUTPUT_ROOT"
else
  mkdir -p "$APP_OUTPUT_ROOT"
fi

APP_DIR="$APP_OUTPUT_ROOT/$APP_BUNDLE_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/$CONFIGURATION/$APP_EXECUTABLE_NAME"
PLIST="$APP_DIR/Contents/Info.plist"

clean_code_signing_xattrs() {
  /usr/bin/xattr -cr "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
}

swift build -c "$CONFIGURATION" --product "$APP_EXECUTABLE_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_MARKETING_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$APP_MINIMUM_SYSTEM_VERSION</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null
clean_code_signing_xattrs
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
clean_code_signing_xattrs
codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null

echo "$APP_DIR"
