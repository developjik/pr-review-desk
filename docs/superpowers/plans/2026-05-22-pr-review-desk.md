# PR Review Desk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal macOS SwiftUI app that browses GitHub repositories and PRs, generates Codex review drafts, lets the user edit/select comments, and submits a GitHub PR review.

**Architecture:** Create a SwiftPM workspace with a tested `PRReviewDeskCore` library and a SwiftUI executable target. Keep GitHub, Keychain, and Codex process execution behind focused types so tests can verify behavior without live credentials.

**Tech Stack:** Swift 6.2, SwiftPM, SwiftUI, Foundation URLSession, Security.framework Keychain, local `codex exec`, GitHub REST API.

---

### Task 1: Package Skeleton And Core Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/PRReviewDeskCore/Models.swift`
- Create: `Tests/PRReviewDeskCoreTests/ModelsTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Write failing model tests**

Create tests that require `Repository`, `PullRequest`, `ReviewEvent`, `ReviewDraft`, and `InlineCommentDraft` to exist and encode/decode predictably.

- [ ] **Step 2: Run model tests and verify RED**

Run: `swift test --filter ModelsTests`

Expected: build fails because the package and models do not exist yet.

- [ ] **Step 3: Add package skeleton and model implementation**

Create the SwiftPM package and model types used by the app and later services.

- [ ] **Step 4: Run model tests and verify GREEN**

Run: `swift test --filter ModelsTests`

Expected: model tests pass.

### Task 2: Diff Position Mapping

**Files:**
- Create: `Sources/PRReviewDeskCore/DiffPositionMapper.swift`
- Create: `Tests/PRReviewDeskCoreTests/DiffPositionMapperTests.swift`

- [ ] **Step 1: Write failing diff mapper tests**

Cover single-hunk and multi-hunk patches. Verify that the first non-header line after `@@` is position 1 and positions continue through later hunks in the same file.

- [ ] **Step 2: Run mapper tests and verify RED**

Run: `swift test --filter DiffPositionMapperTests`

Expected: build fails because `DiffPositionMapper` does not exist.

- [ ] **Step 3: Implement mapper**

Add a mapper that returns annotated patch text and maps new-line numbers to GitHub diff positions.

- [ ] **Step 4: Run mapper tests and verify GREEN**

Run: `swift test --filter DiffPositionMapperTests`

Expected: mapper tests pass.

### Task 3: GitHub Client

**Files:**
- Create: `Sources/PRReviewDeskCore/GitHubClient.swift`
- Create: `Tests/PRReviewDeskCoreTests/GitHubClientTests.swift`

- [ ] **Step 1: Write failing GitHub client tests**

Use a custom `URLProtocol` to capture requests. Verify auth headers, repository and PR decoding, changed file decoding, and review submission payload.

- [ ] **Step 2: Run client tests and verify RED**

Run: `swift test --filter GitHubClientTests`

Expected: build fails because `GitHubClient` does not exist.

- [ ] **Step 3: Implement client**

Add a URLSession-backed client with methods for listing repositories, listing open PRs, fetching PR details, fetching changed files, and submitting reviews.

- [ ] **Step 4: Run client tests and verify GREEN**

Run: `swift test --filter GitHubClientTests`

Expected: client tests pass.

### Task 4: Codex Review Agent

**Files:**
- Create: `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- Create: `Tests/PRReviewDeskCoreTests/CodexReviewAgentTests.swift`

- [ ] **Step 1: Write failing Codex agent tests**

Use a fake command runner. Verify command arguments include `codex exec`, schema output, read-only sandbox, and that valid JSON becomes a `ReviewDraft`.

- [ ] **Step 2: Run agent tests and verify RED**

Run: `swift test --filter CodexReviewAgentTests`

Expected: build fails because `CodexReviewAgent` does not exist.

- [ ] **Step 3: Implement Codex agent**

Add prompt construction, JSON schema writing, process execution, and output decoding.

- [ ] **Step 4: Run agent tests and verify GREEN**

Run: `swift test --filter CodexReviewAgentTests`

Expected: agent tests pass.

### Task 5: Keychain Token Store

**Files:**
- Create: `Sources/PRReviewDeskCore/KeychainTokenStore.swift`
- Create: `Tests/PRReviewDeskCoreTests/KeychainTokenStoreTests.swift`

- [ ] **Step 1: Write failing Keychain interface tests**

Test a memory-backed `TokenStore` implementation and the shared protocol used by the app. Avoid writing real user secrets in unit tests.

- [ ] **Step 2: Run token store tests and verify RED**

Run: `swift test --filter KeychainTokenStoreTests`

Expected: build fails because `TokenStore` does not exist.

- [ ] **Step 3: Implement token store**

Add `TokenStore`, `InMemoryTokenStore`, and `KeychainTokenStore` using Security.framework.

- [ ] **Step 4: Run token store tests and verify GREEN**

Run: `swift test --filter KeychainTokenStoreTests`

Expected: token store tests pass.

### Task 6: SwiftUI App

**Files:**
- Create: `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- Create: `Sources/PRReviewDeskApp/AppModel.swift`
- Create: `Sources/PRReviewDeskApp/MainView.swift`

- [ ] **Step 1: Add app state tests if core gaps appear**

Keep app logic thin. Add core tests first for any behavior that would otherwise sit in SwiftUI views.

- [ ] **Step 2: Implement SwiftUI app shell**

Build the repository sidebar, PR list, review pane, token entry, generate review action, editable draft, event picker, and submit action.

- [ ] **Step 3: Build app**

Run: `swift build`

Expected: build succeeds.

### Task 7: End-To-End Verification

**Files:**
- No new files expected.

- [ ] **Step 1: Run unit tests**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 2: Run build**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 3: Verify Codex CLI**

Run a small `codex exec` JSON smoke test without using project secrets.

- [ ] **Step 4: Verify GitHub token**

Call GitHub `/user` with the provided token without printing the token.

- [ ] **Step 5: Run app target briefly**

Run: `timeout 5 swift run PRReviewDeskApp`

Expected: the executable starts. If the GUI run blocks as expected, terminate after timeout and treat a timeout as successful launch.

- [ ] **Step 6: Report live-test limits**

If there is no safe open PR to review, do not submit a real review. Report repository/PR discovery and stop before posting to an arbitrary PR.
