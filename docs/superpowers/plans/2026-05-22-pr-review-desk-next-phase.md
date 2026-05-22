# PR Review Desk Next Phase Plan

> **For agentic workers:** REQUIRED SUB-SKILL for implementation: use `superpowers:subagent-driven-development` for independent tasks, or `superpowers:executing-plans` for a single-session implementation pass. This document fixes the next development direction after the MVP E2E test; do not treat it as permission to implement without the user's approval.

**Goal:** Turn the proven MVP into a daily-driver personal PR review tool that is safe to trust on real pull requests.

**Decision:** Build trust and repeat-use safety before automation. The next phase is not OAuth, background bots, or team/server mode. The next phase is local alpha hardening: correct review attachment, visible evidence, submission guardrails, reliable Codex execution, and standard test/release gates.

**Current baseline:** The MVP can load GitHub repositories, list open PRs, generate Codex review drafts, let the user edit/select comments, and submit real GitHub review comments. It has been E2E-tested against two live test PRs in `developjik/review-desk`.

---

## Agent Review Synthesis

Four independent reviews were run against the current repo.

- Product/roadmap: the happy path works; the next risk is whether the app can be trusted every day without babysitting.
- Native macOS UX: the three-column structure is right, but token controls, hidden changed files, missing Settings, missing commands, and one-line errors make the app feel like a prototype.
- Architecture/integration: the main correctness risk is submitting a review without binding it to the PR head commit that Codex reviewed.
- QA/security/release: no-go for wider use until stale-head checks, pagination, generated-comment validation, Codex timeout/cancel, privacy disclosure, real `swift test`, and signing gates exist.

The agents disagreed on how soon OAuth should happen. Product and QA both argue against doing OAuth first. Architecture recommends preparing a credential abstraction now so OAuth can be added later without rewriting the app. The final decision is: introduce credential boundaries now, keep PAT for the next phase, and defer OAuth UI until after daily-driver hardening.

---

## Phase 1: Safety Gate Release

**Purpose:** Prevent wrong or accidental GitHub review submissions.

**Why first:** GitHub's create-review API accepts `commit_id`; if it is omitted, GitHub defaults to the current PR head. A force-push between generation and submission can make comments or approvals apply to code the user did not review.

**Scope:**

1. Add `commit_id` to review submission payloads.
2. Re-fetch PR details before submit and compare the current `headSha` with the reviewed snapshot.
3. Block submit if the PR head changed.
4. Validate Codex inline comment `path` and `position` against fetched/annotated diff positions before enabling submit.
5. Add a submit confirmation for `APPROVE` and `REQUEST_CHANGES`; keep `COMMENT` lower-friction but still show selected comment count.
6. Prevent duplicate submissions while a submit request is in flight.

**Primary files:**

- `Sources/PRReviewDeskCore/Models.swift`
- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskCore/DiffPositionMapper.swift`
- `Sources/PRReviewDeskApp/AppModel.swift`
- `Sources/PRReviewDeskApp/MainView.swift`
- `Tests/PRReviewDeskCoreTests/GitHubClientTests.swift`
- New workflow tests after test-target conversion

**Acceptance criteria:**

- Review payload includes the selected PR `headSha` as `commit_id`.
- Submit is blocked with a clear message when the PR head changes after draft generation.
- Generated inline comments with unknown file path or invalid diff position are excluded or surfaced as invalid, not blindly posted.
- `APPROVE` and `REQUEST_CHANGES` require an explicit confirmation.
- A second click cannot create duplicate review submissions.

---

## Phase 2: Standard Test And CI Foundation

**Purpose:** Make the app verifiable by ordinary Swift tooling and future CI.

**Why second:** The custom executable harness works, but `swift test` currently has no real test target. This will become a drag on every future change.

**Scope:**

1. Convert `PRReviewDeskCoreTests` from executable target to SwiftPM `.testTarget`.
2. Keep the existing no-XCTest harness only if the local toolchain still blocks XCTest, but make `swift test` the primary gate if available.
3. Add tests for stale-head rejection, `commit_id`, invalid comment coordinates, GitHub pagination, and GitHub error bodies.
4. Add Codex runner tests for timeout/cancellation and missing binary behavior.
5. Add AppModel/workflow tests by extracting workflow logic out of SwiftUI-only state.

**Primary files:**

- `Package.swift`
- `Tests/PRReviewDeskCoreTests/*`
- New `Tests/PRReviewDeskWorkflowTests/*` if workflow extraction lands in core
- `.github/workflows/ci.yml` only after `swift test` is reliable locally

**Acceptance criteria:**

- `swift test` passes locally.
- `swift run PRReviewDeskCoreTests` is no longer the only verification path.
- CI can run build + tests without live GitHub/Codex credentials.
- All safety-gate behavior has automated coverage.

---

## Phase 3: Review Workspace UX

**Purpose:** Let the user verify evidence before approving AI output.

**Why third:** The app currently fetches changed files but does not show them. That is too weak for a review tool because the user approves comments without seeing enough context.

**Scope:**

1. Split `MainView` into focused views:
   - `RepositorySidebarView`
   - `PullRequestListView`
   - `ReviewWorkspaceView`
   - `ChangedFilesView`
   - `InlineCommentListView`
   - `StatusBarView`
2. Add changed-file summary with path, status, additions, deletions, and omitted-patch indicator.
3. Add patch preview using the annotated diff positions Codex sees.
4. Group inline comments by file and show each comment beside its file/position.
5. Add bulk include/exclude and selected-comment count.
6. Replace `⌘R` review-generation shortcut with refresh; move generate review to `⌘⇧R` or `⌘G`.
7. Add multi-line error panel/details instead of only one truncated status bar line.

**Primary files:**

- `Sources/PRReviewDeskApp/MainView.swift`
- New `Sources/PRReviewDeskApp/RepositorySidebarView.swift`
- New `Sources/PRReviewDeskApp/PullRequestListView.swift`
- New `Sources/PRReviewDeskApp/ReviewWorkspaceView.swift`
- New `Sources/PRReviewDeskApp/ChangedFilesView.swift`
- New `Sources/PRReviewDeskApp/InlineCommentListView.swift`
- New `Sources/PRReviewDeskApp/StatusBarView.swift`

**Acceptance criteria:**

- The user can inspect every file sent to Codex before submitting a review.
- Omitted files are visible and explained.
- The detail pane always shows which commit SHA the draft was generated against.
- Submit controls show event, selected inline comment count, and stale/invalid status.
- Keyboard shortcuts match macOS expectations.

---

## Phase 4: Setup, Credentials, And Privacy Controls

**Purpose:** Make first-run and private-repo usage explicit and recoverable.

**Why fourth:** PAT is acceptable for personal alpha, but the app needs a stable credential boundary before OAuth or GitHub App auth.

**Scope:**

1. Introduce a versioned `GitHubCredential` model.
2. Replace raw token plumbing with `CredentialStore` and `AccessTokenProvider`.
3. Migrate existing Keychain item `PRReviewDesk/github-token` into a versioned PAT credential.
4. Add Settings scene:
   - GitHub token status
   - Validate token/scopes
   - Replace/delete token
   - Codex CLI path/status
   - Privacy notice for private repo patches sent to Codex/OpenAI
   - Default review event
   - Require confirmation before submit
5. Add a first-run checklist: GitHub access, Codex CLI installed, Codex logged in, test repository access.

**Primary files:**

- `Sources/PRReviewDeskCore/KeychainTokenStore.swift`
- New `Sources/PRReviewDeskCore/CredentialStore.swift`
- New `Sources/PRReviewDeskCore/GitHubCredential.swift`
- New `Sources/PRReviewDeskCore/AccessTokenProvider.swift`
- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- New `Sources/PRReviewDeskApp/SettingsView.swift`

**Acceptance criteria:**

- Existing saved PAT continues to work after migration.
- The user can validate, replace, and delete credentials from Settings.
- The app clearly discloses that private PR patches may be sent to Codex/OpenAI during review generation.
- GitHubClient no longer owns a raw token permanently; it obtains authorization through a provider.

---

## Phase 5: Reliability, Pagination, And Codex Runtime Control

**Purpose:** Avoid incomplete reviews and long-running stuck processes.

**Scope:**

1. Add Link-header pagination for repositories, PR lists, and PR file lists.
2. Show when a PR has files with no patch, binary files, large diffs, or renamed/deleted-only files.
3. Add cancellable Codex runner with timeout.
4. Add trusted Codex executable resolution instead of relying blindly on `PATH`.
5. Add redacted run logs for Codex and GitHub operations.
6. Add retry paths for safe reads; do not retry review submission automatically.

**Primary files:**

- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- New `Sources/PRReviewDeskCore/CodexExecutableResolver.swift`
- New `Sources/PRReviewDeskCore/ReviewRunLog.swift`
- `Sources/PRReviewDeskApp/AppModel.swift`
- `Sources/PRReviewDeskApp/StatusBarView.swift`

**Acceptance criteria:**

- Large accounts and large PRs do not silently truncate at 100 items.
- Codex review generation can be cancelled from the UI.
- Codex process timeout produces a recoverable error and does not hang the app.
- Logs do not include GitHub tokens or full secret-like values.

---

## Phase 6: Context-Aware Draft Quality

**Purpose:** Improve review usefulness after safety and workspace basics are reliable.

**Scope:**

1. Add per-repository review policy prompt.
2. Add optional local repo mapping for source context outside the GitHub patch.
3. Include PR body, relevant existing comments, and status/check summaries in the review context.
4. Add large-diff chunking.
5. Add saved drafts and regenerate/discard flow.

**Primary files:**

- New `Sources/PRReviewDeskCore/ReviewContext.swift`
- New `Sources/PRReviewDeskCore/ReviewPolicyStore.swift`
- New `Sources/PRReviewDeskCore/LocalRepositoryContextProvider.swift`
- `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- `Sources/PRReviewDeskApp/ReviewWorkspaceView.swift`

**Acceptance criteria:**

- User can set a repo-specific review policy.
- The app can generate a draft using PR metadata plus optional local source context.
- Drafts survive app restart until submitted or discarded.
- Large diffs fail gracefully or chunk deterministically instead of silently dropping context.

---

## Phase 7: Draft-Only Automation

**Purpose:** Add automation without surrendering final submission control.

**Decision:** Automation must create drafts only. No automatic GitHub submission in this phase.

**Scope:**

1. Add selected-repo watch list.
2. Add `ReviewJob` state machine: queued, fetching, generating, draftReady, stale, failed, submitted.
3. Add `ReviewQueue` actor with concurrency limits and cancellation.
4. Poll watched repos while the app is open.
5. Persist generated drafts and job logs locally.
6. Require manual review and submit for every generated draft.

**Acceptance criteria:**

- The app can prepare review drafts for watched repos while open.
- The user always approves before any GitHub review is posted.
- If a PR changes after draft generation, the job becomes stale and cannot be submitted.

---

## Deferred Until Later

Do not build these in the next phase:

- Full OAuth UI as the first task.
- GitHub App installation flow.
- Hosted backend or webhook server.
- Team/multi-user features.
- Auto-submit reviews.
- Billing, analytics dashboards, or marketplace/provider selection.
- App Store distribution. Developer ID distribution is more plausible later because the app launches a local `codex` CLI.

---

## Final Priority Order

1. **Phase 1: Safety Gate Release**
2. **Phase 2: Standard Test And CI Foundation**
3. **Phase 3: Review Workspace UX**
4. **Phase 4: Setup, Credentials, And Privacy Controls**
5. **Phase 5: Reliability, Pagination, And Codex Runtime Control**
6. **Phase 6: Context-Aware Draft Quality**
7. **Phase 7: Draft-Only Automation**

This order is intentionally conservative. The MVP already proved that the happy path works; the next development work should make the same path correct, inspectable, reversible, and repeatable.

---

## External References Checked

- GitHub REST create-review API: `commit_id`, diff `position`, and pull-request write permissions.
- GitHub REST pagination: `Link` header and `rel="next"` pagination.
- GitHub OAuth device flow: suitable for headless/native-style sign-in, but GitHub notes GitHub Apps should be considered.
- GitHub App user access tokens: access is limited by user access, app permissions, and installation scope.
- OpenAI Codex CLI docs: Codex CLI runs locally and can read/change/run code in the selected directory; Plus/Pro/Business/Edu/Enterprise plans include Codex.
- OpenAI data controls: API endpoints list training and retention behavior; app should still disclose that PR patches are transmitted to Codex/OpenAI.
