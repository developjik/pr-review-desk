#!/usr/bin/env bash
set -euo pipefail

require_ready=false
if [[ "${1:-}" == "--require" ]]; then
  require_ready=true
elif [[ $# -gt 0 ]]; then
  echo "usage: scripts/probe-swift-testing.sh [--require]" >&2
  exit 64
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
swift_version="$(swift --version 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

echo "Swift testing probe"
echo "developer_dir=${developer_dir:-unknown}"
echo "swift_version=${swift_version:-unknown}"

xctest_status="unavailable"
xctest_output=""
if xctest_output="$(swift -e 'import XCTest; print("XCTest import ok")' 2>&1)"; then
  xctest_status="available"
fi

testing_status="unavailable"
testing_output=""
if testing_output="$(swift -e 'import Testing; print("Testing import ok")' 2>&1)"; then
  testing_status="available"
fi

echo "xctest=${xctest_status}"
echo "testing=${testing_status}"

if [[ "$xctest_status" == "available" || "$testing_status" == "available" ]]; then
  echo "swift_test_migration_ready=true"
  exit 0
fi

echo "swift_test_migration_ready=false"
echo "fallback=keep PRReviewDeskCoreTests executable harness as the verification gate"

if [[ "$require_ready" == true ]]; then
  echo "XCTest probe output:" >&2
  echo "$xctest_output" >&2
  echo "Testing probe output:" >&2
  echo "$testing_output" >&2
  exit 1
fi
