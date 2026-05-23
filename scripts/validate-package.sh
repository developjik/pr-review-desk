#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/app-metadata.sh"

APP_DIR="${1:-$ROOT_DIR/.build/app/$APP_BUNDLE_NAME.app}"
PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
RESOURCE_BUNDLE="$APP_DIR/Contents/Resources/PRReviewDesk_PRReviewDeskApp.bundle"

clean_code_signing_xattrs() {
  /usr/bin/xattr -cr "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
  /usr/bin/xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
}

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "Missing Info.plist: $PLIST" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing executable: $EXECUTABLE" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

for locale in en ko; do
  if [[ ! -f "$RESOURCE_BUNDLE/$locale.lproj/Localizable.strings" ]]; then
    echo "Missing $locale Localizable.strings in resource bundle" >&2
    exit 1
  fi

  if [[ ! -f "$RESOURCE_BUNDLE/$locale.lproj/Localizable.stringsdict" ]]; then
    echo "Missing $locale Localizable.stringsdict in resource bundle" >&2
    exit 1
  fi
done

plutil -lint "$PLIST" >/dev/null

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"
}

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plist_value "$key")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $key=$expected, got $actual" >&2
    exit 1
  fi
}

assert_plist_value "CFBundleExecutable" "$APP_EXECUTABLE_NAME"
assert_plist_value "CFBundleIdentifier" "$APP_BUNDLE_IDENTIFIER"
assert_plist_value "CFBundlePackageType" "APPL"
assert_plist_value "CFBundleShortVersionString" "$APP_MARKETING_VERSION"
assert_plist_value "CFBundleVersion" "$APP_BUILD_NUMBER"
assert_plist_value "LSMinimumSystemVersion" "$APP_MINIMUM_SYSTEM_VERSION"
assert_plist_value "NSPrincipalClass" "NSApplication"
clean_code_signing_xattrs
codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null

echo "Validated package: $APP_DIR"
