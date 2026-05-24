#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/app-metadata.sh"

kill_existing_app() {
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
}

package_app() {
  local package_output
  package_output="$(CONFIGURATION=debug "$ROOT_DIR/scripts/package-app.sh")"
  printf '%s\n' "$package_output" >&2
  printf '%s\n' "$package_output" | tail -n 1
}

open_app() {
  local app_bundle="$1"
  /usr/bin/open -n "$app_bundle"
}

kill_existing_app
APP_BUNDLE="$(package_app)"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE_NAME"

case "$MODE" in
  run)
    open_app "$APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$APP_BUNDLE_IDENTIFIER\""
    ;;
  --verify|verify)
    open_app "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
