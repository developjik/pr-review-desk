# Settings-Gated User Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route users to setup/settings when required setup is incomplete, and show the PR review workspace only after GitHub, Codex, and privacy readiness are complete.

**Architecture:** Add a small core presentation policy that decides whether the main window should show setup-required content or the review workspace. Keep setup-changing actions in Settings/setup surfaces, while main review surfaces expose only status and Settings navigation.

**Tech Stack:** Swift 6.1 SwiftPM package, SwiftUI macOS app, existing executable test harness, existing UI smoke renderer, Computer Use UI verification.

---

### Task 1: Add User Flow Policy Tests

**Files:**
- Create: `Sources/PRReviewDeskCore/SettingsGatePresentation.swift`
- Create: `Tests/PRReviewDeskCoreTests/SettingsGatePresentationTests.swift`
- Modify: `Tests/PRReviewDeskCoreTests/TestHarness.swift`

- [ ] **Step 1: Write failing tests**

Add tests that assert incomplete readiness routes to setup, complete readiness routes to review, and main-window setup actions are limited to opening Settings.

- [ ] **Step 2: Verify RED**

Run `swift run PRReviewDeskCoreTests` and confirm the new test suite fails to build because `SettingsGatePresentation` does not exist.

- [ ] **Step 3: Implement presentation policy**

Add `SettingsGateDestination`, `SettingsGateAction`, and `SettingsGatePresentation.make(readinessChecklist:)` in core.

- [ ] **Step 4: Verify GREEN**

Run `swift run PRReviewDeskCoreTests` and confirm the policy tests pass.

### Task 2: Gate Main Window UI

**Files:**
- Create: `Sources/PRReviewDeskApp/SetupRequiredView.swift`
- Modify: `Sources/PRReviewDeskApp/MainView.swift`
- Modify: `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- Modify: `Sources/PRReviewDeskApp/ReviewInboxSidebarView.swift`
- Modify: `Sources/PRReviewDeskApp/ReviewCommandPanelView.swift`

- [ ] **Step 1: Add setup-required view**

Create a setup-required main-window view that summarizes missing readiness items and exposes `SettingsLink` as the primary setup action.

- [ ] **Step 2: Gate `MainView`**

When `SettingsGatePresentation.destination == .setupRequired`, show `SetupRequiredView`; otherwise show the existing review split view.

- [ ] **Step 3: Restore GitHub session on launch**

Run GitHub session restore together with Codex readiness on launch so saved setup is recognized before the user sees the gate.

- [ ] **Step 4: Remove main-window setup mutation**

Keep GitHub/Codex/privacy mutation controls in Settings/setup surfaces only. The review command panel should not expose setup actions when the main window is gated.

### Task 3: Update Smoke Contracts And Copy

**Files:**
- Modify: `Sources/PRReviewDeskApp/UISmokeRenderRunner.swift`
- Modify: `scripts/ui-smoke.sh`
- Modify: `Sources/PRReviewDeskApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/PRReviewDeskApp/Resources/ko.lproj/Localizable.strings`
- Modify: `README.md`

- [ ] **Step 1: Add setup-gate smoke surface**

Add a deterministic smoke render for the setup-required main window and assert that it contains `Open Settings`.

- [ ] **Step 2: Update localization**

Add English and Korean strings for setup-required title, summary, and Settings-only guidance.

- [ ] **Step 3: Update docs**

Document that setup is managed from Settings and the review workspace appears after readiness is complete.

### Task 4: Verify And UI Test

**Files:**
- No source files expected unless verification exposes defects.

- [ ] **Step 1: Run focused tests**

Run `swift run PRReviewDeskCoreTests`.

- [ ] **Step 2: Run full gate**

Run `scripts/verify.sh`.

- [ ] **Step 3: Launch app**

Run `./script/build_and_run.sh --verify` or the existing app launch path.

- [ ] **Step 4: Computer Use verification**

Use Computer Use to inspect the launched macOS app in setup-incomplete and setup-complete smoke states where possible, confirming Settings-only setup routing and review workspace visibility.
