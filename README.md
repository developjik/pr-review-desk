# PR Review Desk

PR Review Desk is a personal macOS app for generating an editable AI review draft for a GitHub pull request, checking the draft locally, and submitting the approved review back to GitHub.

## Verification

Use the shared verification gate before opening or merging a PR:

```bash
scripts/verify.sh
```

The script runs:

```bash
swift build --product PRReviewDeskApp
swift run PRReviewDeskCoreTests
```

The executable `PRReviewDeskCoreTests` target is the current test harness. It does not require live GitHub credentials or Codex credentials.

The package tools version is kept at Swift 6.1 so the GitHub-hosted macOS runner can execute the same gate without installing an additional toolchain. Newer local Swift toolchains can still build the package.

## Swift Test Status

`swift test` is not the local verification gate yet. The current local Command Line Tools install cannot import `XCTest` or `Testing`, and the package keeps the test suite in an executable harness until that toolchain blocker is resolved.

Issue #12 tracks the migration path to a standard SwiftPM test target.
