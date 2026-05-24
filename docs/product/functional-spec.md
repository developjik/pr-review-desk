# 기능 명세

상태: 2026-05-24 worktree 기준 현재 상태 기능 명세.

## 1. 아키텍처

Package는 세 개의 SwiftPM product/target으로 구성됩니다:

- `PRReviewDeskCore`: data model, presentation policy, GitHub API client, OAuth device flow client, credential storage, Codex execution, diff position mapping, draft store, queue, submission validation, workflow logic.
- `PRReviewDeskApp`: SwiftUI macOS executable, app model, settings, review workspace, inbox, diff viewer, inspector, command panel, smoke renderer, localization resources.
- `PRReviewDeskCoreTests`: live GitHub 또는 Codex credential 없이 sync/async test suite를 실행하는 executable test harness.

앱 state는 `AppModel`에 집중되어 있습니다. View는 `AppModel`과 core presentation/value type에 bind합니다. External effect는 credential store, GitHub client, Codex authentication checker, Codex command runner, review draft store 같은 교체 가능한 dependency 뒤에 둡니다.

## 2. Data Model

Core GitHub 모델:

- `Repository`: `id`, `owner`, `name`, `fullName`, `isPrivate`.
- `PullRequest`: `id`, `number`, `title`, optional `body`, `htmlURL`, `author`, `headSha`, optional `updatedAt`.
- `PullRequestFile`: `path`, `status`, `additions`, `deletions`, optional `patch`, computed `reviewability`.
- `PullRequestReviewContext`: PR body, issue comments, review comments, check runs를 위한 bounded context.

Review 모델:

- `ReviewDraft`: summary, risks, inline comment drafts.
- `InlineCommentDraft`: stable id, path, GitHub diff position, body, severity, `isSelected`.
- `ReviewEvent`: `COMMENT`, `APPROVE`, `REQUEST_CHANGES`.
- `ReviewSubmission`: event, body, commit ID, selected comments.

Coverage 모델:

- `ReviewCoverageSummary`는 total, reviewable, omitted file을 count하고 omitted additions/deletions를 계산합니다.
- GitHub patch text가 없거나 review에 필요한 metadata가 없는 file은 Codex prompt에서 제외되고 UI에 표시됩니다.

## 3. Credential과 GitHub Auth

Interactive GitHub auth는 OAuth App device flow를 사용합니다:

1. `GitHubOAuthDeviceFlowClient`가 `/login/device/code`에 `client_id`와 scope를 POST합니다.
2. `/login/oauth/access_token`을 poll합니다.
3. `authorization_pending`, `slow_down`, `expired_token`, `access_denied`, cancellation, success를 처리합니다.
4. Success 시 OAuth user token과 metadata를 credential store에 저장합니다.

Credential 저장:

- `VersionedCredentialStore`는 typed credential과 metadata를 Keychain에 저장합니다.
- Model에는 여러 credential kind가 존재하지만, 현재 app launch는 API 사용을 위해 OAuth user token만 허용합니다.
- Unsupported saved credential은 삭제되고 사용자는 다시 sign in해야 합니다.
- `CredentialStoreAccessTokenProvider`와 `StaticAccessTokenProvider`가 GitHub API request에 bearer auth를 제공합니다.

Token 검증:

- `GitHubClient.validateToken()`은 `/user`를 호출합니다.
- Login은 user response에서 가져옵니다.
- Scope는 `X-OAuth-Scopes` header에서 가져옵니다.
- 앱은 login/scope metadata를 저장하고 readiness와 repository access check에 사용합니다.

Repository access 정책:

- 일부 GitHub response가 scope를 보고하지 않을 수 있으므로 empty scope는 local에서 allowed로 처리합니다.
- `repo`는 public/private repository 모두 허용합니다.
- `public_repo`는 public repository만 허용합니다.
- Private access가 없는 known scope는 recovery copy와 함께 private repository를 deny합니다.

## 4. Codex Readiness와 AI Review

Codex 준비 상태:

- `CodexCLIAuthenticationChecker`는 `which codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`로 `codex`를 resolve합니다.
- 5초 timeout으로 `codex login status`를 실행합니다.
- ChatGPT login이 감지될 때만 ready입니다.
- Missing CLI, API-key login, access-token login, unknown output, command failure, timeout은 ready가 아닙니다.

Review 생성:

- `CodexReviewAgent`는 `--ignore-user-config`, `--ignore-rules`, `--cd`, `--skip-git-repo-check`, `--sandbox read-only`, `--ephemeral`, `model_reasoning_effort="low"`, `--output-schema`, `--output-last-message`로 `codex exec`를 실행합니다.
- Default timeout은 120초입니다.
- Prompt는 repository, PR number/title/author/URL/head SHA, bounded PR context, annotated diff를 포함합니다.
- PR context는 prompt size를 제어하기 위해 bounded됩니다.
- Reviewable patch가 없는 file은 prompt에서 제외됩니다.
- Output schema는 path, position, body, severity가 있는 inline comments와 summary, risks를 요구합니다.

Error mapping 처리:

- Missing executable, timeout, cancellation, process failure, missing output, malformed output, no reviewable files는 recoverable generation error로 표시됩니다.
- Error details는 `SensitiveTextRedactor`를 거칩니다.

## 5. Readiness Gate

필수 readiness item:

- GitHub sign-in credential.
- GitHub access/token validation.
- Codex CLI와 ChatGPT login을 합친 AI review setup.
- Privacy disclosure acknowledgement.

`SettingsGatePresentation` 결과:

- 필수 item 중 하나라도 ready가 아니면 `.setupRequired`.
- 모든 필수 item이 ready이면 `.reviewWorkspace`.
- Setup-required main window는 Settings를 primary setup route로만 노출합니다.

`FirstRunSetupPresentation` guided setup 순서:

1. GitHub access.
2. AI review setup.
3. Privacy acknowledgement.

## 6. Main Window Layout

Setup이 완료되면 `MainView`는 `NavigationSplitView`를 사용합니다:

- Sidebar: `ReviewInboxSidebarView`.
- Content: `ReviewInboxView`.
- Detail: `ReviewPaneView`.
- Inspector: `ReviewInspectorView`. Layout policy상 기본은 hidden이고 새 draft generation revision 후 열립니다.

Toolbar 명령:

- Actions, Refresh, Generate AI Review Draft, Submit Review, Cancel, Toggle Inspector, Settings.

검색:

- Toolbar search는 pull-request search text에 bind됩니다.

Sheet 목록:

- Command panel.
- Private repository consent.
- Submit review preview.

## 7. Inbox와 Selection

Inbox section 목록:

- Review Inbox: submitted가 아닌 actionable row 전체.
- Draft Ready: current generated draft가 있는 row.
- Stale: stale 또는 failed draft state row.
- Running: queued 또는 generating row.
- Needs Setup: readiness가 incomplete일 때 setup guidance.
- Submitted: saved/background queue state에서 submitted된 row.

Sidebar 표시:

- Section title은 `Inbox Filters`.
- Filter order는 Review Inbox, Draft Ready, Stale, Running, Needs Setup, Submitted.

Row 상태:

- `PullRequestDraftStatus`는 background queue state, local draft presence, reviewed head SHA, current head SHA에서 status를 derive합니다.
- Submitted row는 Review Inbox에서 제외되고 Submitted에 포함됩니다.

Selection 정책:

- Selected row가 visible이면 유지합니다.
- Selected row가 hidden이고 row 변경 이유가 content change이면 selected row의 current section으로 이동합니다.
- Selected row가 user-selected filter 또는 search change 때문에 hidden이면 first visible row를 선택하거나 selection을 clear합니다.
- Empty user-selected filter는 선택 상태를 유지하고 hidden PR selection을 clear합니다.

## 8. Repository와 Pull Request Loading

Repository loading 처리:

- `GitHubClient.listRepositories()`는 owner/collaborator/org affiliation, updated sorting, per-page 100, pagination으로 `/user/repos`를 호출합니다.
- Refresh는 가능한 경우 selected repository를 ID 기준으로 보존합니다.

PR loading 처리:

- `GitHubClient.listOpenPullRequests()`는 pagination으로 open PR을 load합니다.
- Repository 선택은 PR context를 clear하고 open PR을 load합니다.
- PR 선택은 PR details를 refetch하고, files를 load하고, first changed file을 선택하고, preflight head SHA를 update하고, safety timestamp를 기록하고, 가능한 draft를 restore합니다.

검색:

- Repository search는 owner, name, full name을 match합니다.
- Pull-request search는 number, title, author를 match합니다.

## 9. Draft Storage와 Queue

Draft persistence 처리:

- `FileReviewDraftStore`는 Application Support의 `PRReviewDesk/ReviewDrafts` 아래 JSON으로 저장합니다.
- Draft key는 repository full name, pull request number, head SHA를 포함합니다.
- Stored draft는 review draft, review body, selected event, saved date, optional private repository flag를 포함합니다.
- Current draft edit는 current draft key가 있을 때 persist됩니다.

Background queue 처리:

- Queue item은 repository full name과 pull request number로 key됩니다.
- State는 queued, generating, draft ready, stale, failed, submitted입니다.
- Enqueue는 existing item을 deduplicate합니다.
- Queue processing은 repository access, private consent, Codex readiness, PR details, changed files, review context, Codex generation, draft storage, current selection application을 확인합니다.
- Failed/stale item은 retry할 수 있습니다.
- Non-generating item은 remove할 수 있고, remove 시 matching saved draft가 삭제됩니다.

## 10. Diff Workspace

파일 navigation 동작:

- Single-file PR은 inline selected file detail을 사용합니다.
- Multi-file PR은 changed-files pane과 selected file detail을 함께 사용합니다.
- Changed file row는 path, status, additions, deletions, viewed state, omitted state, inline comment selected/total count를 보여줍니다.

선택 file detail 동작:

- File path, status, additions/deletions, draft version availability, diff display mode, whitespace toggle, mark viewed/unviewed, collapse/expand를 보여줍니다.

Diff 렌더링 동작:

- `DiffPositionMapper`는 GitHub patch text에 position을 annotate합니다.
- `DiffViewer`는 old line, new line, position, code text, inline comments, focus highlight를 render합니다.
- Unified와 split view를 지원합니다.
- Whitespace rendering이 enabled이면 tab과 space를 visible marker로 바꿉니다.
- Inline comment button은 해당 inspector/diff state를 focus합니다.

탐색 동작:

- Next/previous file은 changed files를 순환합니다.
- Next/previous hunk는 selected file의 hunk line을 순환합니다.
- Next/previous inline comment는 path와 position 순으로 정렬된 generated inline comments를 순환합니다.

## 11. Inspector, Preview, Submission

Inspector 패널 동작:

- Event picker, submit action, submit safety, AI trust, draft body editor, inline comment editors, reveal controls, invalid warnings, discard draft를 보여줍니다.
- Event picker는 GitHub review event에 mapping됩니다.
- Draft가 있으면 Submit button은 preview를 엽니다.

Safety validation 동작:

- `ReviewSubmissionValidator`는 reviewed head SHA와 current head SHA를 요구합니다.
- Stale head SHA를 block합니다.
- Position 계산이 가능할 때 selected inline comment를 current diff position과 validate합니다.
- Unselected invalid comment는 무시합니다.
- Diff position을 validate할 수 없으면 block합니다.

Preview 동작:

- `ReviewSubmissionPreview`는 event, full submitted body, preview body, selected inline comments, selected count, safety state, safety message, last checked display, `canSubmit`을 포함합니다.
- Unsafe이면 preview는 Check Again과 Regenerate를 제공합니다.
- Invalid comment는 preview에서 reveal 또는 deselect할 수 있습니다.

Submission 동작:

- `ReviewSubmissionWorkflow`는 submit 전 PR details와 files를 refetch하고, safety를 validate한 뒤 GitHub review submission을 호출합니다.
- `GitHubClient.submitReview()`는 event, body, commit ID, comments를 `/repos/{owner}/{repo}/pulls/{number}/reviews`에 POST합니다.
- Selected comments는 path, GitHub diff position, body를 포함합니다.

## 12. Settings, Localization, Appearance

Settings 화면:

- Appearance: System, Light, Dark.
- Language: System, English, Korean.
- Readiness checklist.
- GitHub status, sign-in/reconnect, cancel sign-in, copy code, open GitHub, manage GitHub link, retry restore, delete local credential, validate.
- Codex status, check Codex, copy sign-in step, open Terminal sign-in step.
- Privacy acknowledgement와 remembered private repository consent clearing.

Localization 동작:

- English와 Korean resource가 `Sources/PRReviewDeskApp/Resources` 아래 존재합니다.
- UI copy, command, hint, dialog, status string, count-sensitive string은 localized됩니다.
- Protocol value와 external data는 localized하지 않습니다.

Appearance 동작:

- App storage가 preferred color scheme을 제어합니다.
- Default appearance는 System입니다.

## 13. Error Handling과 Privacy

Recoverable error는 다음을 포함합니다:

- Operation.
- 요약.
- Details.
- Recovery suggestion.

Sensitive redaction 동작:

- Authorization header, GitHub token-like value, OpenAI key-like value는 error details에서 redact됩니다.

개인정보 control 동작:

- Global disclosure는 review workspace access 전에 필요합니다.
- Private repository consent는 repository별이며 clear할 수 있습니다.
- Reviewable patch가 없는 file은 이 앱이 Codex로 보내지 않습니다.

## 14. 검증

필수 local gate:

```bash
scripts/verify.sh
```

Gate 실행 항목:

- `scripts/probe-swift-testing.sh`.
- `scripts/check-localization.sh`.
- `swift build --product PRReviewDeskApp`.
- `scripts/ui-smoke.sh`.
- `swift run PRReviewDeskCoreTests`.

UI smoke 동작:

- Deterministic offscreen SwiftUI/AppKit render를 실행합니다.
- Setup gate, first-run setup, repository sidebar, review inbox, diff workspace, inspector, submit preview, command panel, Settings readiness surface를 cover합니다.
- Stored credential을 load하지 않고, GitHub를 touch하지 않으며, Codex를 call하지 않습니다.

## 15. 현재 제한

- Selected-file-only regeneration은 enabled되어 있지 않습니다.
- Backend, team mode, webhook processor, billing, hosted automation은 없습니다.
- GitHub App auth는 deferred decision이며 현재 behavior가 아닙니다.
- Current suite가 executable harness에 남아 있어 `swift test`는 아직 project gate가 아닙니다.
- Live GitHub/Codex behavior는 deterministic verification gate에서 exercise하지 않습니다.
