#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-$ROOT_DIR/.build/app/PRReviewDesk.app}"
PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/PRReviewDeskApp"

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

assert_plist_value "CFBundleExecutable" "PRReviewDeskApp"
assert_plist_value "CFBundleIdentifier" "com.developjik.PRReviewDesk"
assert_plist_value "CFBundlePackageType" "APPL"
assert_plist_value "NSPrincipalClass" "NSApplication"

short_version="$(plist_value "CFBundleShortVersionString")"
bundle_version="$(plist_value "CFBundleVersion")"

if [[ -z "$short_version" || -z "$bundle_version" ]]; then
  echo "Bundle version metadata must be present" >&2
  exit 1
fi

echo "Validated package: $APP_DIR"
