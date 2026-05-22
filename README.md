# PR Review Desk

PR Review Desk is a personal macOS app for generating an editable AI review draft for a GitHub pull request, checking the draft locally, and submitting the approved review back to GitHub.

## Verification

Use the shared verification gate before opening or merging a PR:

```bash
scripts/verify.sh
```

The script runs:

```bash
scripts/probe-swift-testing.sh
swift build --product PRReviewDeskApp
swift run PRReviewDeskCoreTests
```

The executable `PRReviewDeskCoreTests` target is the current test harness. It does not require live GitHub credentials or Codex credentials. `scripts/probe-swift-testing.sh` reports whether the selected developer directory can import `XCTest` or `Testing`; it is informational unless run with `--require`.

The package tools version is kept at Swift 6.1 so the GitHub-hosted macOS runner can execute the same gate without installing an additional toolchain. Newer local Swift toolchains can still build the package.

## Release Candidate Gate

CI pins the macOS runner to `macos-26` instead of `macos-latest` so the release candidate gate does not silently move between major runner images. Each run prints the selected developer directory, Xcode version, Swift version, and a Foundation import probe before building.

Run the same release candidate checks locally before publishing a build:

```bash
scripts/verify.sh
swift build -c release --product PRReviewDeskApp
scripts/package-app.sh
scripts/validate-package.sh
```

`scripts/package-app.sh` builds a release bundle by default, writes bundle metadata from `scripts/app-metadata.sh`, lints the generated `Info.plist`, and ad-hoc signs the app for local distribution readiness. When the checkout is inside iCloud Drive, `.build/app` is symlinked to a temporary output directory so macOS FileProvider metadata does not break strict code-signing verification. `scripts/validate-package.sh` checks the generated `.build/app/PRReviewDesk.app` bundle structure, `Info.plist`, executable bit, bundle identifier, package type, principal class, version metadata, and code signature.

## Swift Test Status

`swift test` is not the local verification gate yet. The package intentionally keeps the suite in the executable `PRReviewDeskCoreTests` harness until the local toolchain can run a standard SwiftPM test target.

Local status observed on 2026-05-22:

```bash
scripts/probe-swift-testing.sh
# Swift testing probe
# developer_dir=/Library/Developer/CommandLineTools
# swift_version=swift-driver version: 1.127.14.1 Apple Swift version 6.2.3 ... Target: arm64-apple-macosx26.0
# xctest=unavailable
# testing=unavailable
# swift_test_migration_ready=false
# fallback=keep PRReviewDeskCoreTests executable harness as the verification gate

xcode-select -p
# /Library/Developer/CommandLineTools

swift --version
# Apple Swift version 6.2.3 ... Target: arm64-apple-macosx26.0

swift -e 'import XCTest; print("XCTest import ok")'
# error: no such module 'XCTest'

swift -e 'import Testing; print("Testing import ok")'
# error: no such module 'Testing'

swift test
# error: no tests found; create a target in the 'Tests' directory
```

The local blocker is the active Command Line Tools-only developer directory, which does not expose `XCTest` or `Testing` to this package. Installing and selecting a full Xcode developer directory should be verified with the import probes above before changing the gate:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
scripts/probe-swift-testing.sh --require
```

For CI, prefer pinning a full-Xcode macOS image when migrating instead of relying on an implicit local setup. As of 2026-05-22, GitHub's `actions/runner-images` `macos-26` image documentation lists Xcode 26.2 as the default `/Applications/Xcode.app`, with additional Xcode 26.x bundles available: <https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md>.

Migration path:

1. Keep `scripts/verify.sh` and the executable harness as the only required gate until both local and CI import probes pass.
2. Change `Package.swift` by replacing the `PRReviewDeskCoreTests` executable product/target with a `.testTarget` at the same `Tests/PRReviewDeskCoreTests` path.
3. Replace `TestHarness.main()` with minimal XCTest or Swift Testing adapters that call the existing suite `run()` methods. This reuses the current test bodies instead of keeping a second duplicated suite.
4. Update `scripts/verify.sh` to run `swift test` after the test target is green locally and in CI.
5. Incrementally convert the suite `run()` methods into native XCTest or Swift Testing cases only after the gate is stable.
