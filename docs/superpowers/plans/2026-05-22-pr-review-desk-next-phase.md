# PR Review Desk 다음 단계 계획

> **Agent 작업자 안내:** 구현 시 independent task에는 `superpowers:subagent-driven-development`, single-session implementation pass에는 `superpowers:executing-plans`를 사용합니다. 이 문서는 MVP E2E test 이후의 다음 개발 방향을 고정합니다. 사용자 승인 없이 구현 허가로 해석하지 않습니다.

**목표:** 검증된 MVP를 실제 pull request에서 신뢰하고 매일 사용할 수 있는 개인용 PR review tool로 강화한다.

**결정:** Automation보다 trust와 repeat-use safety를 먼저 만든다. 다음 단계는 OAuth, background bot, team/server mode가 아니다. 다음 단계는 local alpha hardening이다: correct review attachment, visible evidence, submission guardrail, reliable Codex execution, standard test/release gate.

**현재 baseline:** MVP는 GitHub repository를 load하고, open PR을 list하고, Codex review draft를 generate하고, 사용자가 comment를 edit/select하고, 실제 GitHub review comment를 submit할 수 있다. `developjik/review-desk`의 live test PR 두 개로 E2E test를 완료했다.

---

## Agent Review 종합

현재 repo에 대해 네 가지 독립 review를 실행했다.

- Product/roadmap: happy path는 동작한다. 다음 risk는 babysitting 없이 매일 신뢰할 수 있는지다.
- Native macOS UX: three-column structure는 맞지만 token controls, hidden changed files, missing Settings, missing commands, one-line errors 때문에 prototype처럼 느껴진다.
- 아키텍처/integration: 가장 큰 correctness risk는 Codex가 review한 PR head commit에 review를 bind하지 않고 submit하는 것이다.
- QA/security/release: stale-head checks, pagination, generated-comment validation, Codex timeout/cancel, privacy disclosure, real `swift test`, signing gate가 없으면 wider use는 no-go다.

Agent들은 OAuth를 얼마나 빨리 해야 하는지 의견이 갈렸다. Product와 QA는 둘 다 OAuth를 먼저 하지 말자고 주장했다. Architecture는 나중에 app rewrite 없이 OAuth를 추가할 수 있도록 credential abstraction을 준비하자고 권했다. 최종 결정은 credential boundary는 지금 도입하고, 다음 단계에서는 PAT를 유지하며, daily-driver hardening 후 OAuth UI를 미루는 것이다.

---

## Phase 1: Safety Gate Release

**목적:** 잘못되거나 의도하지 않은 GitHub review submission을 막는다.

**먼저 하는 이유:** GitHub create-review API는 `commit_id`를 받는다. 생략하면 GitHub는 현재 PR head를 기본값으로 사용한다. Generation과 submission 사이 force-push가 있으면 comment나 approval이 사용자가 review하지 않은 code에 적용될 수 있다.

**범위:**

1. Review submission payload에 `commit_id` 추가.
2. Submit 전 PR details를 re-fetch하고 current `headSha`와 reviewed snapshot 비교.
3. PR head가 바뀌면 submit block.
4. Submit enabled 전에 Codex inline comment `path`와 `position`을 fetched/annotated diff positions와 validate.
5. `APPROVE`, `REQUEST_CHANGES`에는 submit confirmation 추가. `COMMENT`는 더 낮은 friction을 유지하되 selected comment count 표시.
6. Submit request in flight 중 duplicate submission 방지.

**주요 파일:**

- `Sources/PRReviewDeskCore/Models.swift`
- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskCore/DiffPositionMapper.swift`
- `Sources/PRReviewDeskApp/AppModel.swift`
- `Sources/PRReviewDeskApp/MainView.swift`
- `Tests/PRReviewDeskCoreTests/GitHubClientTests.swift`
- Test-target conversion 이후 새 workflow tests

**수용 기준:**

- Review payload가 selected PR `headSha`를 `commit_id`로 포함한다.
- Draft generation 후 PR head가 바뀌면 clear message와 함께 submit이 block된다.
- Unknown file path 또는 invalid diff position의 generated inline comment는 blind post되지 않고 제외되거나 invalid로 표시된다.
- `APPROVE`, `REQUEST_CHANGES`는 명시적 confirmation을 요구한다.
- 두 번째 click이 duplicate review submission을 만들 수 없다.

---

## Phase 2: Standard Test와 CI Foundation

**목적:** 일반 Swift tooling과 미래 CI로 app을 검증 가능하게 만든다.

**두 번째 이유:** Custom executable harness는 동작하지만 `swift test`에는 현재 real test target이 없다. 이는 향후 모든 변경의 부담이 된다.

**범위:**

1. `PRReviewDeskCoreTests`를 executable target에서 SwiftPM `.testTarget`으로 전환.
2. Local toolchain이 XCTest를 여전히 막는 경우에만 no-XCTest harness를 유지하되, 가능하면 `swift test`를 primary gate로 만든다.
3. Stale-head rejection, `commit_id`, invalid comment coordinates, GitHub pagination, GitHub error body test 추가.
4. Codex runner timeout/cancellation, missing binary behavior test 추가.
5. SwiftUI-only state에서 workflow logic을 추출해 AppModel/workflow test 추가.

**주요 파일:**

- `Package.swift`
- `Tests/PRReviewDeskCoreTests/*`
- Workflow extraction이 core로 들어가면 새 `Tests/PRReviewDeskWorkflowTests/*`
- `swift test`가 local에서 reliable해진 뒤 `.github/workflows/ci.yml`

**수용 기준:**

- `swift test`가 local에서 pass한다.
- `swift run PRReviewDeskCoreTests`가 더 이상 유일한 verification path가 아니다.
- CI가 live GitHub/Codex credential 없이 build + tests를 실행할 수 있다.
- 모든 safety-gate behavior에 automated coverage가 있다.

---

## Phase 3: Review Workspace UX

**목적:** 사용자가 AI output을 approve하기 전에 evidence를 검증할 수 있게 한다.

**세 번째 이유:** 앱은 changed files를 fetch하지만 현재 보여주지 않는다. Review tool로서는 사용자가 충분한 context 없이 comment를 approve하게 되어 너무 약하다.

**범위:**

1. `MainView`를 focused view로 분리:
   - `RepositorySidebarView`
   - `PullRequestListView`
   - `ReviewWorkspaceView`
   - `ChangedFilesView`
   - `InlineCommentListView`
   - `StatusBarView`
2. Path, status, additions, deletions, omitted-patch indicator가 있는 changed-file summary 추가.
3. Codex가 보는 annotated diff positions를 사용하는 patch preview 추가.
4. Inline comment를 file별로 group하고 각 comment를 file/position 옆에 표시.
5. Bulk include/exclude와 selected-comment count 추가.
6. `⌘R` review-generation shortcut을 refresh로 교체하고 generate review는 `⌘⇧R` 또는 `⌘G`로 이동.
7. Truncated status bar line 하나 대신 multi-line error panel/details 추가.

**주요 파일:**

- `Sources/PRReviewDeskApp/MainView.swift`
- 새 `Sources/PRReviewDeskApp/RepositorySidebarView.swift`
- 새 `Sources/PRReviewDeskApp/PullRequestListView.swift`
- 새 `Sources/PRReviewDeskApp/ReviewWorkspaceView.swift`
- 새 `Sources/PRReviewDeskApp/ChangedFilesView.swift`
- 새 `Sources/PRReviewDeskApp/InlineCommentListView.swift`
- 새 `Sources/PRReviewDeskApp/StatusBarView.swift`

**수용 기준:**

- 사용자가 review submit 전에 Codex로 보낸 모든 file을 inspect할 수 있다.
- Omitted file이 visible하고 설명된다.
- Detail pane은 draft가 어떤 commit SHA 기준으로 generated되었는지 항상 보여준다.
- Submit controls가 event, selected inline comment count, stale/invalid status를 보여준다.
- Keyboard shortcut이 macOS expectation에 맞다.

---

## Phase 4: Setup, Credentials, Privacy Controls

**목적:** First-run과 private-repo usage를 명시적이고 recoverable하게 만든다.

**네 번째 이유:** PAT는 personal alpha에 적합하지만, OAuth 또는 GitHub App auth 전에 stable credential boundary가 필요하다.

**범위:**

1. Versioned `GitHubCredential` model 도입.
2. Raw token plumbing을 `CredentialStore`와 `AccessTokenProvider`로 교체.
3. 기존 Keychain item `PRReviewDesk/github-token`을 versioned PAT credential로 migration.
4. Settings scene 추가:
   - GitHub token status
   - Validate token/scopes
   - Replace/delete token
   - Codex CLI path/status
   - Private repo patches가 Codex/OpenAI로 전송된다는 privacy notice
   - Default review event
   - Submit 전 confirmation 요구
5. First-run checklist 추가: GitHub access, Codex CLI installed, Codex logged in, test repository access.

**주요 파일:**

- `Sources/PRReviewDeskCore/KeychainTokenStore.swift`
- 새 `Sources/PRReviewDeskCore/CredentialStore.swift`
- 새 `Sources/PRReviewDeskCore/GitHubCredential.swift`
- 새 `Sources/PRReviewDeskCore/AccessTokenProvider.swift`
- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- 새 `Sources/PRReviewDeskApp/SettingsView.swift`

**수용 기준:**

- 기존 saved PAT가 migration 후에도 동작한다.
- 사용자가 Settings에서 credential을 validate, replace, delete할 수 있다.
- 앱이 private PR patch가 review generation 중 Codex/OpenAI로 전송될 수 있음을 명확히 disclose한다.
- GitHubClient가 raw token을 permanent하게 소유하지 않고 provider를 통해 authorization을 얻는다.

---

## Phase 5: Reliability, Pagination, Codex Runtime Control

**목적:** Incomplete review와 long-running stuck process를 피한다.

**범위:**

1. Repository, PR list, PR file list에 Link-header pagination 추가.
2. PR에 no patch, binary file, large diff, renamed/deleted-only file이 있을 때 표시.
3. Timeout이 있는 cancellable Codex runner 추가.
4. `PATH`에 blind reliance하지 않는 trusted Codex executable resolution 추가.
5. Codex/GitHub operation에 대한 redacted run logs 추가.
6. Safe read에는 retry path를 추가하되 review submission은 자동 retry하지 않음.

**주요 파일:**

- `Sources/PRReviewDeskCore/GitHubClient.swift`
- `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- 새 `Sources/PRReviewDeskCore/CodexExecutableResolver.swift`
- 새 `Sources/PRReviewDeskCore/ReviewRunLog.swift`
- `Sources/PRReviewDeskApp/AppModel.swift`
- `Sources/PRReviewDeskApp/StatusBarView.swift`

**수용 기준:**

- Large account와 large PR이 100 items에서 silently truncate되지 않는다.
- UI에서 Codex review generation을 cancel할 수 있다.
- Codex process timeout은 recoverable error를 만들고 app을 hang시키지 않는다.
- Log에 GitHub token이나 full secret-like value가 포함되지 않는다.

---

## Phase 6: Context-Aware Draft Quality

**목적:** Safety와 workspace 기본기가 reliable해진 뒤 review usefulness를 개선한다.

**범위:**

1. Per-repository review policy prompt 추가.
2. GitHub patch 밖 source context를 위한 optional local repo mapping 추가.
3. Review context에 PR body, relevant existing comments, status/check summary 포함.
4. Large-diff chunking 추가.
5. Saved drafts와 regenerate/discard flow 추가.

**주요 파일:**

- 새 `Sources/PRReviewDeskCore/ReviewContext.swift`
- 새 `Sources/PRReviewDeskCore/ReviewPolicyStore.swift`
- 새 `Sources/PRReviewDeskCore/LocalRepositoryContextProvider.swift`
- `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- `Sources/PRReviewDeskApp/ReviewWorkspaceView.swift`

**수용 기준:**

- 사용자가 repo-specific review policy를 설정할 수 있다.
- 앱이 PR metadata와 optional local source context로 draft를 generate할 수 있다.
- Draft는 submitted 또는 discarded될 때까지 app restart 후에도 유지된다.
- Large diff는 context를 silently drop하지 않고 graceful failure 또는 deterministic chunking으로 처리된다.

---

## Phase 7: Draft-Only Automation

**목적:** Final submission control을 포기하지 않고 automation을 추가한다.

**결정:** 이 phase의 automation은 draft만 생성해야 한다. GitHub submission 자동화는 하지 않는다.

**범위:**

1. Selected-repo watch list 추가.
2. `ReviewJob` state machine 추가: queued, fetching, generating, draftReady, stale, failed, submitted.
3. Concurrency limit와 cancellation이 있는 `ReviewQueue` actor 추가.
4. 앱이 열려 있는 동안 watched repo를 poll.
5. Generated draft와 job log를 local에 persist.
6. 모든 generated draft는 manual review와 submit을 요구.

**수용 기준:**

- 앱이 열려 있는 동안 watched repo의 review draft를 준비할 수 있다.
- GitHub review가 posted되기 전에 사용자가 항상 approve한다.
- Draft generation 후 PR이 바뀌면 job은 stale이 되고 submit할 수 없다.

---

## 나중으로 미룰 것

다음 phase에서는 만들지 않는다:

- 첫 task로 full OAuth UI 만들기.
- GitHub App installation flow.
- Hosted backend 또는 webhook server.
- Team/multi-user features.
- Auto-submit reviews.
- Billing, analytics dashboard, marketplace/provider selection.
- App Store distribution. Local `codex` CLI를 launch하므로 나중에는 Developer ID distribution이 더 현실적이다.

---

## 최종 우선순위

1. **Phase 1: Safety Gate Release**
2. **Phase 2: Standard Test And CI Foundation**
3. **Phase 3: Review Workspace UX**
4. **Phase 4: Setup, Credentials, And Privacy Controls**
5. **Phase 5: Reliability, Pagination, And Codex Runtime Control**
6. **Phase 6: Context-Aware Draft Quality**
7. **Phase 7: Draft-Only Automation**

이 순서는 의도적으로 보수적이다. MVP는 happy path가 동작한다는 것을 이미 증명했다. 다음 개발은 같은 path를 correct, inspectable, reversible, repeatable하게 만드는 데 집중해야 한다.

---

## 확인한 외부 참고 자료

- GitHub REST create-review API: `commit_id`, diff `position`, pull-request write permissions.
- GitHub REST pagination: `Link` header와 `rel="next"` pagination.
- GitHub OAuth device flow: headless/native-style sign-in에 적합하지만 GitHub는 GitHub Apps도 고려하라고 안내한다.
- GitHub App user access tokens: access는 user access, app permissions, installation scope로 제한된다.
- OpenAI Codex CLI docs: Codex CLI는 local에서 실행되고 selected directory의 code를 read/change/run할 수 있다. Plus/Pro/Business/Edu/Enterprise plan은 Codex를 포함한다.
- OpenAI data controls: API endpoint는 training과 retention behavior를 설명한다. 앱은 여전히 PR patch가 Codex/OpenAI로 전송된다는 점을 disclose해야 한다.
