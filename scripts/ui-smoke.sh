#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BINARY="$ROOT_DIR/.build/debug/PRReviewDeskApp"

cd "$ROOT_DIR"

if [[ ! -x "$APP_BINARY" ]]; then
  swift build --product PRReviewDeskApp >/dev/null
fi

output_en="$("$APP_BINARY" --ui-smoke --ui-smoke-language en)"
output_ko="$("$APP_BINARY" --ui-smoke --ui-smoke-language ko)"
output_ko_sample="$("$APP_BINARY" --ui-smoke-localization ko)"
output_command="$("$APP_BINARY" --ui-smoke-command-interaction)"
output="${output_en}"$'\n'"${output_ko}"$'\n'"${output_ko_sample}"$'\n'"${output_command}"

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
  "ui_language=en"
  "ui_language=ko"
  "localized_sample=submit-preview-title:Submit Review Preview"
  "localized_sample=submit-preview-title:리뷰 제출 미리보기"
  "localization=Submit Review Preview"
  "localization=No matching repositories"
  "render=first-run-setup:desktop"
  "render=first-run-setup:compact"
  "render=repository-sidebar:desktop"
  "render=review-inbox:desktop"
  "render=diff-workspace:desktop"
  "render=review-inspector:desktop"
  "render=submit-preview:desktop"
  "render=submit-preview:compact"
  "render=command-panel:desktop"
  "render=settings-readiness:desktop"
  "semantic=first-run-setup:desktop"
  "semantic=submit-preview:desktop"
  "semantic=command-panel:desktop"
  "interaction=command-panel:filtered=1"
  "interaction=command-panel:selected=select-section-stale"
  "interaction=command-panel:return=select-section-stale"
  "assert=first-run-setup:finish-setup,guided-setup,github-codex-privacy"
  "assert=submit-preview:submit-preview,preflight-state,last-checked,refresh-action,regenerate-action,submit-disabled"
  "assert=command-panel:command-panel,shortcut-hints,selected-row,return-execution"
)

for needle in "${required[@]}"; do
  if ! grep -Fq "$needle" <<<"$output"; then
    echo "UI smoke manifest missing: $needle" >&2
    echo "$output" >&2
    exit 1
  fi
done

echo "$output"
