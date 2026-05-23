#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

scripts/probe-swift-testing.sh
scripts/check-localization.sh
swift build --product PRReviewDeskApp
scripts/ui-smoke.sh
swift run PRReviewDeskCoreTests
