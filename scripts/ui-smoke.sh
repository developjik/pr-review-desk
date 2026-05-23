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
output_preference_ko="$("$APP_BINARY" --ui-smoke --ui-smoke-language-preference ko)"
output_language_switch="$("$APP_BINARY" --ui-smoke --ui-smoke-language-switch-defaults ko)"
output_ko_sample="$("$APP_BINARY" --ui-smoke-localization ko)"
output_command="$("$APP_BINARY" --ui-smoke-command-interaction)"
output_keyboard="$("$APP_BINARY" --ui-smoke-command-keyboard)"
output_selection_visual="$("$APP_BINARY" --ui-smoke-command-selection-visual)"
output_layout="$("$APP_BINARY" --ui-smoke-layout-contract)"
output_accessibility="$("$APP_BINARY" --ui-smoke-accessibility-contract)"
output="${output_en}"$'\n'"${output_ko}"$'\n'"${output_preference_ko}"$'\n'"${output_language_switch}"$'\n'"${output_ko_sample}"$'\n'"${output_command}"$'\n'"${output_keyboard}"$'\n'"${output_selection_visual}"$'\n'"${output_layout}"$'\n'"${output_accessibility}"

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
  "ui_preference_language=ko"
  "preference_localized_sample=submit-preview-title:리뷰 제출 미리보기"
  "language_switch_default=credentialKindDescription:없음"
  "language_switch_default=tokenValidationStatus:검증 안 됨."
  "language_switch_default=codexCLIStatus:확인하지 않음."
  "language_switch_default=codexLoginStatus:확인하지 않음."
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
  "interaction=command-panel-keyboard:selected-section=stale"
  "interaction=command-panel-keyboard:is-presented=false"
  "interaction=command-panel-keyboard:deferred-submit=0"
  "visual=command-panel:selected-row=select-section-stale"
  "layout=review-inbox:top-content-y="
  "layout=repository-sidebar:top-content-y="
  "accessibility=first-run-setup.no-token:rendered-controls=first-run.codex-login.copy,first-run.codex.check,first-run.github.oauth,first-run.privacy.acknowledge"
  "accessibility=first-run-setup.loaded-token:rendered-controls=first-run.codex-login.copy,first-run.codex.check,first-run.github.reload,first-run.github.validate,first-run.privacy.acknowledge"
  "accessibility=submit-preview:rendered-controls=submit-preview.refresh-safety[enabled],submit-preview.regenerate[enabled],submit-preview.submit[disabled]"
  "accessibility=command-panel:rendered-controls=command-panel.action.select-section-stale[selected],command-panel.search"
  "accessibility=settings.loaded-token:rendered-controls=settings.github.delete,settings.github.oauth,settings.github.validate"
  "accessibility=review-inbox:rendered-controls=review-inbox.pull-request.74[selected]"
)

for needle in "${required[@]}"; do
  if ! grep -Fq "$needle" <<<"$output"; then
    echo "UI smoke manifest missing: $needle" >&2
    echo "$output" >&2
    exit 1
  fi
done

echo "$output"
