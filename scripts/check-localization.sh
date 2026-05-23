#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Sources/PRReviewDeskApp"
EN_STRINGS="$APP_DIR/Resources/en.lproj/Localizable.strings"
KO_STRINGS="$APP_DIR/Resources/ko.lproj/Localizable.strings"
EN_STRINGSDICT="$APP_DIR/Resources/en.lproj/Localizable.stringsdict"
KO_STRINGSDICT="$APP_DIR/Resources/ko.lproj/Localizable.stringsdict"

cd "$ROOT_DIR"

plutil -lint "$EN_STRINGS" "$KO_STRINGS" "$EN_STRINGSDICT" "$KO_STRINGSDICT" >/dev/null

extract_strings_keys() {
  perl -ne 'while (/"((?:\\.|[^"\\])*)"\s*=/g) { $key = $1; $key =~ s/\\"/"/g; print "$key\n"; }' "$1" | sort -u
}

extract_source_keys() {
  perl -0777 -ne 'while (/AppL10n\.string\(\s*"((?:\\.|[^"\\])*)"/g) { $key = $1; $key =~ s/\\"/"/g; print "$key\n"; }' "$APP_DIR"/*.swift | sort -u
}

extract_dynamic_keys() {
  printf "%s\n" \
    "Draft Ready" \
    "Stale" \
    "Running" \
    "Needs Setup" \
    "Submitted" \
    "Recents/Favorites" \
    "No draft" \
    "Queued" \
    "Generating" \
    "Draft ready" \
    "Failed" |
    sort -u
}

missing_keys() {
  local locale="$1"
  local strings_file="$2"
  local source_keys
  local dynamic_keys
  local required_keys
  local strings_keys
  source_keys="$(mktemp)"
  dynamic_keys="$(mktemp)"
  required_keys="$(mktemp)"
  strings_keys="$(mktemp)"
  trap 'rm -f "$source_keys" "$dynamic_keys" "$required_keys" "$strings_keys"' RETURN

  extract_source_keys >"$source_keys"
  extract_dynamic_keys >"$dynamic_keys"
  cat "$source_keys" "$dynamic_keys" | sort -u >"$required_keys"
  extract_strings_keys "$strings_file" >"$strings_keys"

  if ! comm -23 "$required_keys" "$strings_keys" | sed "s/^/$locale missing key: /" >&2; then
    return 1
  fi

  local missing_count
  missing_count="$(comm -23 "$required_keys" "$strings_keys" | wc -l | tr -d ' ')"
  [[ "$missing_count" == "0" ]]
}

compare_locale_keys() {
  local left="$1"
  local right="$2"
  local left_keys
  local right_keys
  left_keys="$(mktemp)"
  right_keys="$(mktemp)"
  trap 'rm -f "$left_keys" "$right_keys"' RETURN

  extract_strings_keys "$left" >"$left_keys"
  extract_strings_keys "$right" >"$right_keys"

  local diff_count
  diff_count="$(comm -3 "$left_keys" "$right_keys" | wc -l | tr -d ' ')"
  if [[ "$diff_count" != "0" ]]; then
    echo "English and Korean localization keys differ:" >&2
    comm -3 "$left_keys" "$right_keys" >&2
    return 1
  fi
}

reject_raw_ui_copy() {
  local matches status_matches
  matches="$(
    rg -n \
      'Text\("Draft |Text\("No draft SHA"|Text\("pos |accessibilityLabel\("Pull request|accessibilityLabel\("Inline comment for|\.(help|accessibility(Label|Hint|Value))\(".*(selected of|inline comments|additions|deletions|position|private|public)| \? "private" : "public"' \
      "$APP_DIR"/*.swift || true
  )"
  status_matches="$(
    rg -n \
      '(^|[[:space:]])(statusMessage|tokenValidationStatus|oauthStatus) = "[^"]+|@Published var (statusMessage|tokenValidationStatus|oauthStatus) = "[^"]+' \
      "$APP_DIR/AppModel.swift" || true
  )"

  if [[ -n "$matches" || -n "$status_matches" ]]; then
    echo "Raw user-facing English must go through AppL10n:" >&2
    printf "%s\n%s\n" "$matches" "$status_matches" | sed '/^$/d' >&2
    return 1
  fi
}

reject_awkward_korean_copy() {
  local matches
  matches="$(
    rg -n \
      '= ".*(GitHub 로그인 정보과|GitHub 로그인 정보이|로그인 정보을|접근 권한를|접근 권한가|GitHub GitHub|OAuth|Keychain|키체인|PATH|Homebrew|npm|CLI|codex login|터미널|메타데이터|패치|컨텍스트|디바이스 코드|SHA|토큰)' \
      "$KO_STRINGS" "$KO_STRINGSDICT" || true
  )"

  if [[ -n "$matches" ]]; then
    echo "Korean localization contains awkward or technical setup copy:" >&2
    printf "%s\n" "$matches" >&2
    return 1
  fi
}

missing_keys "en" "$EN_STRINGS"
missing_keys "ko" "$KO_STRINGS"
compare_locale_keys "$EN_STRINGS" "$KO_STRINGS"
reject_raw_ui_copy
reject_awkward_korean_copy

echo "Localization checks passed"
