# 구현 정합성 리뷰

상태: 2026-05-24 worktree 기준 현재 상태 문서 audit 완료.

## Audit 방법

이 폴더의 문서는 다음을 기준으로 확인했습니다:

- Swift package manifest와 target layout.
- Core data model, policy, GitHub client, OAuth client, Codex runner, draft store, queue, diff mapper, submission validator.
- SwiftUI app view, `AppModel`, Settings, review inbox, diff workspace, inspector, command panel, UI smoke renderer.
- Executable test harness와 test suite 이름.
- README와 historical docs.

이 리뷰는 source 기반이며 deterministic합니다. Live GitHub 또는 live Codex verification을 주장하지 않습니다.

## Source Evidence Map

| 제품 영역 | 현재 동작 | 근거 |
| --- | --- | --- |
| SwiftPM 구조 | Core library, SwiftUI app executable, executable test harness가 있습니다. | `Package.swift`, `Tests/PRReviewDeskCoreTests/TestHarness.swift` |
| Main setup gate | Incomplete readiness는 setup-required view로, complete readiness는 review workspace로 route됩니다. | `Sources/PRReviewDeskCore/SettingsGatePresentation.swift`, `Sources/PRReviewDeskApp/MainView.swift`, `Sources/PRReviewDeskApp/SetupRequiredView.swift` |
| Readiness checklist | GitHub credential, GitHub access validation, AI review setup, privacy acknowledgement를 요구합니다. | `Sources/PRReviewDeskCore/ReadinessChecklist.swift`, `Sources/PRReviewDeskApp/ReadinessChecklistView.swift` |
| First-run setup | Guided order는 GitHub, Codex, privacy입니다. | `Sources/PRReviewDeskCore/FirstRunSetupPresentation.swift`, `Sources/PRReviewDeskApp/ReviewInboxView.swift` |
| GitHub OAuth | Device flow start/poll/terminal state handling/token storage를 지원합니다. | `Sources/PRReviewDeskCore/GitHubOAuthDeviceFlowClient.swift`, `Sources/PRReviewDeskApp/AppModel.swift` |
| Credential storage | Versioned Keychain credential envelope, metadata, legacy migration model, OAuth-only app restore가 있습니다. | `Sources/PRReviewDeskCore/KeychainTokenStore.swift`, `Sources/PRReviewDeskApp/AppModel.swift` |
| GitHub API | Repository, PR, file, review context, token validation, review submission이 REST를 사용합니다. | `Sources/PRReviewDeskCore/GitHubClient.swift` |
| Repository access | Private repo access는 OAuth scope에 따라 결정됩니다. | `Sources/PRReviewDeskCore/GitHubRepositoryAccessPolicy.swift` |
| Codex readiness | CLI lookup과 ChatGPT login detection이 generation을 gate합니다. | `Sources/PRReviewDeskCore/CodexAuthentication.swift`, `Sources/PRReviewDeskApp/AppModel.swift` |
| Codex generation | Schema, read-only sandbox, bounded context, annotated patch로 `codex exec`를 실행합니다. | `Sources/PRReviewDeskCore/CodexReviewAgent.swift` |
| Privacy consent | Global privacy acknowledgement와 private repository per-repo consent를 지원합니다. | `Sources/PRReviewDeskCore/PrivateRepositoryConsent.swift`, `Sources/PRReviewDeskApp/PrivateRepositoryConsentSheet.swift` |
| Review inbox filters | Review Inbox, Draft Ready, Stale, Running, Needs Setup, Submitted를 지원합니다. | `Sources/PRReviewDeskCore/ReviewInbox.swift`, `Sources/PRReviewDeskCore/ReviewInboxSidebarPresentation.swift`, `Sources/PRReviewDeskApp/ReviewInboxSidebarView.swift` |
| Empty filter behavior | User-selected empty filter는 선택 상태를 유지하고 hidden PR selection을 clear합니다. | `Sources/PRReviewDeskCore/ReviewInboxSelectionPolicy.swift`, `Sources/PRReviewDeskApp/ReviewInboxView.swift`, `Tests/PRReviewDeskCoreTests/ReviewInboxTests.swift` |
| Pull-request rows | Draft status, coverage warning, severity, repo metadata, visibility rule을 제공합니다. | `Sources/PRReviewDeskCore/ReviewInbox.swift`, `Sources/PRReviewDeskApp/ReviewInboxView.swift` |
| Repository scope | Sidebar load/refresh, selected repo, collapsed list, search, no-match state를 제공합니다. | `Sources/PRReviewDeskApp/ReviewInboxSidebarView.swift`, `Sources/PRReviewDeskCore/RepositorySearchPresentation.swift` |
| App model PR lifecycle | Refresh repos, select repo, select PR, load files, restore drafts, generate, submit을 처리합니다. | `Sources/PRReviewDeskApp/AppModel.swift` |
| Background queue | Queue state, dedupe, start/stop/retry/remove, saved drafts, submitted state를 지원합니다. | `Sources/PRReviewDeskCore/BackgroundReviewQueue.swift`, `Sources/PRReviewDeskApp/ReviewInboxSidebarView.swift`, `Sources/PRReviewDeskApp/AppModel.swift` |
| Draft store | Repo, PR, head SHA로 key된 Application Support JSON draft storage입니다. | `Sources/PRReviewDeskCore/ReviewDraftStore.swift` |
| Diff mapping | GitHub patch position과 semantic annotated line을 제공합니다. | `Sources/PRReviewDeskCore/DiffPositionMapper.swift`, `Sources/PRReviewDeskApp/DiffViewer.swift` |
| Diff workspace | Changed file list, selected file detail, unified/split mode, whitespace, viewed/collapsed, inline anchor를 지원합니다. | `Sources/PRReviewDeskApp/ReviewPaneView.swift`, `Sources/PRReviewDeskApp/ChangedFilesPane.swift`, `Sources/PRReviewDeskApp/SelectedFileDetailView.swift`, `Sources/PRReviewDeskApp/DiffViewer.swift` |
| Inspector/editor | Event picker, safety, trust summary, body editor, inline comment editor, discard를 제공합니다. | `Sources/PRReviewDeskApp/ReviewInspectorView.swift`, `Sources/PRReviewDeskApp/DraftEditorView.swift` |
| Submit preview | Body/comment preview, safety state, invalid comment recovery, submit confirmation을 제공합니다. | `Sources/PRReviewDeskCore/ReviewSubmissionPreview.swift`, `Sources/PRReviewDeskApp/ReviewSubmissionPreviewSheet.swift` |
| Submission validation | Stale head, invalid selected comment, unknown diff validation을 block합니다. | `Sources/PRReviewDeskCore/ReviewSubmissionValidator.swift`, `Sources/PRReviewDeskCore/ReviewSubmissionWorkflow.swift` |
| Command panel | Searchable grouped action, disabled guidance, inbox filter action, keyboard behavior를 제공합니다. | `Sources/PRReviewDeskCore/ReviewCommandPanelPresentation.swift`, `Sources/PRReviewDeskApp/ReviewCommandPanelView.swift` |
| Keyboard/menu commands | Refresh, generate, cancel, submit, open PR, navigation, command panel을 제공합니다. | `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`, `Sources/PRReviewDeskApp/MainView.swift` |
| Settings | Appearance, language, readiness, GitHub, Codex, privacy maintenance를 제공합니다. | `Sources/PRReviewDeskApp/SettingsView.swift` |
| Localization | English/Korean app resources와 localization check script가 있습니다. | `Sources/PRReviewDeskApp/Resources/en.lproj`, `Sources/PRReviewDeskApp/Resources/ko.lproj`, `scripts/check-localization.sh` |
| 검증 | Probe, localization, build, UI smoke, executable tests를 실행합니다. | `scripts/verify.sh`, `scripts/ui-smoke.sh`, `Sources/PRReviewDeskApp/UISmokeRenderRunner.swift`, `Tests/PRReviewDeskCoreTests/TestHarness.swift` |

## Test Coverage Map

현재 executable test suite는 다음을 cover합니다:

- Model, coverage summary, redaction, review event value.
- Review inbox classification, selection policy, file state, command availability, sidebar presentation, filter presentation.
- Settings gate, first-run setup, readiness checklist, Settings GitHub access presentation.
- Repository와 pull-request search/selection.
- Diff position mapping과 inline comment navigation.
- Draft storage와 background queue lifecycle.
- GitHub repository access policy.
- Credential access-token provider와 Keychain credential store behavior.
- GitHub client request construction, pagination, retry behavior, validation, context, submission payload.
- OAuth device flow.
- Codex authentication과 Codex review agent command/prompt/error behavior.
- Review submission preview, validator, workflow.
- UI smoke manifest coverage.

근거: `Tests/PRReviewDeskCoreTests/TestHarness.swift`가 모든 active suite를 열거합니다.

## 정합성 발견사항

| 발견 | 상태 | 해결 |
| --- | --- | --- |
| 현재 behavior는 GitHub OAuth device flow를 사용하지만 original MVP design doc은 PAT entry를 설명했습니다. | Historical doc mismatch. | Original design doc은 historical로 표시했고 이 product documentation이 supersede합니다. |
| README는 inbox filter를 `Recents/Favorites`로 설명했지만 현재 code는 첫 filter를 `Review Inbox`로 표시합니다. | 이 문서 update에서 수정됨. | README는 Review Inbox, Draft Ready, Stale, Running, Needs Setup, Submitted로 갱신되었습니다. |
| Selected-file regeneration은 command kind로 존재하지만 현재 enabled되지 않습니다. | Documented limitation. | PRD와 functional spec이 selected-file-only regeneration 미지원 상태를 명시합니다. |
| `Tests` 아래 suite가 있어도 `swift test`는 active gate가 아닙니다. | Documented limitation. | README와 functional spec은 executable harness가 현재 verification임을 기록합니다. |
| Live GitHub/Codex integration은 deterministic local docs audit로 증명할 수 없습니다. | Documented boundary. | Alignment review는 이 audit이 source/test/smoke 기반이고 live-service verification이 아니라고 명시합니다. |

## 요구사항 추적

| 요구사항 | 근거 상태 |
| --- | --- |
| PRD-01 setup gate | Core policy, main view, setup-required view, tests로 cover. |
| PRD-02 OAuth device sign-in | OAuth client, AppModel sign-in flow, tests로 cover. |
| PRD-03 saved OAuth restore | AppModel restore/load logic과 credential store tests로 cover. |
| PRD-04 Codex readiness | Codex auth checker, readiness UI, tests로 cover. |
| PRD-05 privacy acknowledgement | Readiness checklist, setup UI, Settings로 cover. |
| PRD-06 private repository consent | Consent policy, sheet, AppModel continuation, tests로 cover. |
| PRD-07 review inbox filters | Inbox core, sidebar presentation, localized resources, tests로 cover. |
| PRD-08 empty filter stability | Selection policy reason, ReviewInboxView behavior, tests로 cover. |
| PRD-09 repository scope | Sidebar UI와 search presentation tests로 cover. |
| PRD-10 PR search | SearchFilter와 ReviewInboxFilterPresentation tests로 cover. |
| PRD-11 PR selection loading | AppModel selection flow와 GitHub client tests로 cover. |
| PRD-12 draft state classification | ReviewInbox core와 tests로 cover. |
| PRD-13 background draft queue | BackgroundReviewQueue, AppModel queue processing, tests로 cover. |
| PRD-14 bounded Codex context | CodexReviewAgent와 tests로 cover. |
| PRD-15 local editable drafts | DraftEditorView, AppModel persistence, draft store tests로 cover. |
| PRD-16 diff navigation | Diff views, mapper, layout policy, navigation tests로 cover. |
| PRD-17 inspector controls | ReviewInspectorView와 UI smoke surface로 cover. |
| PRD-18 submit preview | Preview core/view와 tests로 cover. |
| PRD-19 unsafe submission blocking | Validator/workflow tests로 cover. |
| PRD-20 reviewed commit ID submission | ReviewSubmissionWorkflow와 GitHubClient tests로 cover. |
| PRD-21 redacted recoverable errors | AppModel error handling과 redactor tests로 cover. |
| PRD-22 Settings maintenance | SettingsView와 readiness presentation tests로 cover. |
| PRD-23 localization | Resources와 localization check script로 cover. |
| PRD-24 deterministic verification | `scripts/verify.sh`, smoke runner, executable tests로 cover. |

## 남아 있는 제품 gap

이는 문서 mismatch가 아니라 실제 gap입니다:

- Placeholder command kind는 있지만 selected-file-only regeneration은 없습니다.
- Hosted/team mode 또는 GitHub App authentication은 없습니다.
- Deterministic gate에 live-service verification은 없습니다.
- Native `swift test` target은 아직 없습니다.

## 결론

Older MVP design을 historical로 표시하고 README inbox wording을 수정한 뒤, 현재 product documentation은 현재 codebase와 일치합니다. Authoritative current docs는 `docs/product/`의 파일입니다.
