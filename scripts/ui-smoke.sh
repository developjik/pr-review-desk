#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BINARY="$ROOT_DIR/.build/debug/PRReviewDeskApp"

cd "$ROOT_DIR"

if [[ ! -x "$APP_BINARY" ]]; then
  swift build --product PRReviewDeskApp >/dev/null
fi

output="$("$APP_BINARY" --ui-smoke)"

required=(
  "ui_smoke=ready"
  "surface=first-run-setup"
  "surface=repository-sidebar"
  "surface=review-inbox"
  "surface=diff-workspace"
  "surface=review-inspector"
  "surface=submit-preview"
  "surface=command-panel"
  "surface=settings-readiness"
  "localization=Submit Review Preview"
  "localization=No matching repositories"
)

for needle in "${required[@]}"; do
  if ! grep -Fq "$needle" <<<"$output"; then
    echo "UI smoke manifest missing: $needle" >&2
    echo "$output" >&2
    exit 1
  fi
done

echo "$output"
