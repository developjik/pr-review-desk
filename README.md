# PR Review Desk

PR Review Desk is a personal macOS app for generating an editable AI review draft for a GitHub pull request, checking the draft locally, and submitting the approved review back to GitHub.

## Using The App

PR Review Desk is designed so a non-developer can review pull requests without touching the project source code.

You need:

- A GitHub account with access to the repositories you want to review.
- Codex installed on this Mac. If the app cannot find Codex, open the [Codex CLI help](https://developers.openai.com/codex/cli), install Codex, then return to PR Review Desk and choose Check Codex.
- Codex signed in on this Mac. PR Review Desk uses that local Codex session for review generation.

First run:

1. Open PR Review Desk.
2. If required setup is incomplete, the main window asks you to finish setup in Settings.
3. In Settings, sign in with GitHub, check Codex, and confirm the privacy disclosure. Pull request details and reviewable changes may be sent to Codex and OpenAI when generating a draft.
4. When setup is complete, PR Review Desk automatically shows the PR review workspace.
5. Select a repository and an open pull request.
6. Generate an AI review draft, edit the review body and selected inline comments, then use the submit preview to confirm exactly what will be posted to GitHub.

Nothing is posted to GitHub until you confirm the submit preview. For private repositories, PR Review Desk asks for repository-specific consent before sending private repository context to Codex and OpenAI.

## Verification

Use the shared verification gate before opening or merging a PR:

```bash
scripts/verify.sh
```

The script runs:

```bash
scripts/probe-swift-testing.sh
swift build --product PRReviewDeskApp
scripts/ui-smoke.sh
swift run PRReviewDeskCoreTests
```

## Development Workflow

This project uses a document-driven workflow. The detailed workflow documents are maintained in Korean:

- [`docs/product`](docs/product/README.md)는 현재 제품 기준 문서이며 같은 브랜치의 구현과 일치해야 합니다.
- [`docs/changes`](docs/changes/README.md)는 제안되었거나 진행 중인 동작을 기록하는 곳입니다.
- [`docs/development/document-driven-workflow.md`](docs/development/document-driven-workflow.md)는 변경 제안, 구현, 현재 문서 갱신, 정합성 리뷰, 검증 순서를 정의합니다.

구현 전 미래 동작을 `docs/product/*`에 쓰지 않습니다. 사소하지 않은 변경은 `docs/changes/TEMPLATE.md`에서 시작하고, issue/PR에 제안을 연결한 뒤, 앱이 실제로 구현한 후 `docs/product/*`를 갱신합니다.

## Localization And Appearance

The app declares English as the default localization and includes Korean resources for the SwiftUI app target. UI resources live under:

```text
Sources/PRReviewDeskApp/Resources/en.lproj
Sources/PRReviewDeskApp/Resources/ko.lproj
```

Use `Localizable.strings` for labels, commands, help text, dialogs, and status copy. Use `Localizable.stringsdict` for count-sensitive text. Keep protocol data unlocalized: GitHub API raw values, OAuth scopes, JSON keys, URLs, diff text, repository names, PR titles, authors, file paths, GitHub error bodies, and Codex output schema values.

The packaged app must include the SwiftPM resource bundle in `Contents/Resources`; `scripts/package-app.sh` copies it and `scripts/validate-package.sh` checks English and Korean localization files. Appearance defaults to System, with Light and Dark overrides available from Settings.

## Review Workflow UI

The main window first checks required setup. If GitHub access, Codex readiness, or privacy acknowledgement is missing, the window shows a setup-required state with a Settings entry point; setup changes are made from Settings. Once ready, the main window opens around a review inbox, not a repository-first control panel. Inbox filters group work into Review Inbox, Draft Ready, Stale, Running, Needs Setup, and Submitted. Repositories remain in the sidebar as scope filters and draft creation sources.

The current product documentation lives in [`docs/product`](docs/product/README.md), including the PRD, user stories, user flows, functional specification, and implementation alignment review.

The detail area uses a focused diff workspace. Changed files stay next to the diff, while review body editing, inline comment selection, pre-submit checks, event selection, and AI trust details live in the trailing inspector. The toolbar and Review menu expose refresh, generation, submission, GitHub opening, file/change-block/comment navigation, draft creation actions, and Codex login actions; `Command-K` opens the contextual action panel.

Diff review supports old/new line gutters, GitHub diff positions, inline comment anchors, viewed/unviewed state, file collapse/expand, unified/split display, whitespace markers, and keyboard navigation for files, change blocks, and inline comments.

The executable `PRReviewDeskCoreTests` target is the current test harness. It does not require live GitHub credentials or Codex credentials. `scripts/probe-swift-testing.sh` reports whether the selected developer directory can import `XCTest` or `Testing`; it is informational unless run with `--require`.

`scripts/ui-smoke.sh` runs the app executable in `--ui-smoke` mode and checks deterministic offscreen SwiftUI/AppKit renders for the setup gate, first-run setup, repository sidebar, review inbox, diff workspace, inspector, submit preview, command panel, and Settings readiness surfaces. It emits rendered pixel sizes and PNG checksums, and it does not load stored credentials, touch GitHub, or call Codex.

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
