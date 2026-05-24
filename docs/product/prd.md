# PR Review Desk PRD

상태: 2026-05-24 worktree 기준 현재 상태 제품 요구사항.

## 문제

AI 도움을 받아 GitHub pull request를 review하는 일은 reviewer가 어떤 context가 전송되는지 신뢰할 수 있고, 게시 전에 생성된 comment를 검토할 수 있으며, stale하거나 잘못된 review comment 제출을 피할 수 있을 때만 유용합니다. Local macOS reviewer에게는 setup도 명확해야 합니다. GitHub access, Codex readiness, privacy acknowledgement가 AI generation 전에 보이고 충족되어야 합니다.

## 제품 요약

PR Review Desk는 reviewer가 GitHub repository와 open pull request를 불러오고, local Codex CLI를 통해 editable AI review draft를 생성하며, changed files와 inline comment anchor를 검토하고, 확인된 GitHub review를 제출하도록 돕는 개인용 macOS app입니다.

앱은 local-first입니다. Backend service, multi-user workspace, hosted automation은 없습니다. GitHub REST API, macOS Keychain, local user defaults, draft JSON용 Application Support storage, local Codex CLI session을 사용합니다.

## 주요 사용자

- 개인 reviewer: GitHub에서 접근 가능한 repository들의 open pull request를 review합니다.
- 재방문 reviewer: 저장된 review draft를 이어서 작업하고, stale PR을 refresh하며, preview 확인 후에만 submit합니다.
- 고급 reviewer: inbox filter, command panel, keyboard navigation, file review state, background draft queue를 사용합니다.
- Maintainer/developer: executable test harness, UI smoke renderer, localization check, packaging script로 동작을 검증합니다.

## 목표

- GitHub access, Codex ChatGPT login, privacy acknowledgement가 준비될 때까지 review generation을 gate합니다.
- Repository-first form이 아니라 review inbox를 primary work surface로 둡니다.
- Reviewer가 AI review draft를 자동 게시 없이 만들고, 검토하고, 편집하고, 제출하게 합니다.
- Private repository context를 repository별 명시적 consent step으로 보호합니다.
- Stale head SHA와 invalid inline diff position이 제출되지 않게 합니다.
- Live GitHub 또는 Codex credential 없이 실행 가능한 deterministic local verification을 제공합니다.

## 비목표

- Team account, billing, hosted service mode, shared review queue.
- GitHub App installation flow 또는 server-side GitHub webhook processing.
- Manual preview confirmation 없는 완전 자동 review posting.
- 일반 interactive sign-in path로 manual personal access token entry 제공.
- Selected-file-only regeneration. Command model에는 placeholder가 있지만 현재 availability가 비활성화합니다.

## 제품 요구사항

| ID | 요구사항 | 수용 기준 |
| --- | --- | --- |
| PRD-01 | 앱은 setup이 불완전할 때 review workspace로 진입하지 않아야 합니다. | 필요한 readiness item 중 하나라도 ready가 아니면 main window는 review split view 대신 setup-required content와 Settings entry point를 보여줍니다. |
| PRD-02 | 앱은 GitHub OAuth device sign-in을 지원해야 합니다. | Device flow를 시작하고, GitHub를 열고, user code를 표시/복사하며, authorization 완료까지 poll하고, OAuth credential을 저장하고, scope/login을 검증한 뒤 repository를 refresh할 수 있습니다. |
| PRD-03 | 앱은 launch 시 저장된 GitHub OAuth session을 복원해야 합니다. | 저장된 OAuth credential을 Keychain에서 불러오고, GitHub client를 구성하고, 저장된 metadata를 적용하며, 가능하면 repository를 refresh합니다. 지원하지 않는 저장 credential kind는 제거합니다. |
| PRD-04 | 앱은 generation 전에 Codex readiness를 검증해야 합니다. | Codex CLI를 찾고, `codex login status`를 실행하며, ChatGPT login만 허용합니다. Missing CLI, API-key login, access-token login, unknown output, nonzero status는 block합니다. |
| PRD-05 | 앱은 privacy acknowledgement를 요구해야 합니다. | 사용자가 PR details와 reviewable changes가 Codex 및 OpenAI로 전송될 수 있음을 acknowledge할 때까지 readiness checklist가 incomplete로 남습니다. |
| PRD-06 | Private repository context를 Codex로 보내기 전 명시적 consent가 필요합니다. | Public repo는 consent가 필요 없습니다. Private repo는 이미 remembered되지 않은 한 repository-specific acknowledgement가 필요합니다. |
| PRD-07 | Review inbox는 현재 작업을 status별로 노출해야 합니다. | Inbox filter는 Review Inbox, Draft Ready, Stale, Running, Needs Setup, Submitted이며 count와 localized label을 표시합니다. |
| PRD-08 | Review Inbox filter는 선택 가능해야 하며 빈 상태에서 되돌아가면 안 됩니다. | 사용자가 선택한 empty filter는 선택 상태를 유지하고, 필요하면 selected PR을 clear하며, 해당 empty state를 보여줍니다. Content change는 selected PR의 실제 section으로 selection을 이동할 수 있습니다. |
| PRD-09 | Repository는 sidebar scope filter로 동작해야 합니다. | Sidebar는 repository를 load하고, selected repository를 보여주며, collapsed/expanded repository list, repository search, no-match empty state, private/public indicator를 지원합니다. |
| PRD-10 | Pull-request search는 현재 inbox row를 filter해야 합니다. | Search는 whitespace를 trim하고, active search summary를 보여주며, Clear search를 제공하고, search가 row를 숨길 때 설명합니다. |
| PRD-11 | PR 선택 시 현재 PR details와 changed files를 load해야 합니다. | 앱은 PR details를 refetch하고, changed files를 load하고, 가능하면 selected file을 보존하며, preflight head SHA를 기록하고, 저장된 draft가 있으면 복원합니다. |
| PRD-12 | 앱은 draft state를 일관되게 분류해야 합니다. | Draft state는 no draft, queued, generating, draft ready, stale, failed, submitted입니다. Submitted item은 Review Inbox에서 제외되고 Submitted에 표시됩니다. |
| PRD-13 | 앱은 background draft creation을 지원해야 합니다. | 사용자는 selected PR 또는 selected repository의 모든 open PR을 draft queue에 추가할 수 있습니다. Queue는 start, stop, retry failed/stale item, remove item, persist ready draft를 지원합니다. |
| PRD-14 | Codex generation은 bounded PR context와 reviewable patch만 사용해야 합니다. | Prompt는 PR metadata, bounded PR body/comments/checks, annotated reviewable patches를 포함합니다. Reviewable patch data가 없는 file은 omit되고 coverage warning으로 표시됩니다. |
| PRD-15 | Generated draft는 submit 전까지 editable local state여야 합니다. | Review body, selected event, inline comment body, inline comment selection을 편집할 수 있고, draft key가 있을 때 local draft store에 persist됩니다. |
| PRD-16 | Diff workspace는 정확한 review navigation을 지원해야 합니다. | UI는 changed files, file status/additions/deletions, unified/split diff mode, whitespace marker, GitHub diff position, inline comment anchor, viewed/unviewed state, collapse/expand, keyboard navigation을 보여줍니다. |
| PRD-17 | Inspector는 draft와 submission control을 집중시켜야 합니다. | Inspector는 event selection, submit action, submit safety, AI trust/coverage summary, editable body, editable inline comments, reveal controls, invalid comment warning, discard draft를 보여줍니다. |
| PRD-18 | Submission은 항상 preview를 먼저 보여줘야 합니다. | Preview는 event, body, selected inline comments, safety state, last checked time, invalid comments, check again/regenerate/deselect/reveal/cancel/submit button을 보여줍니다. |
| PRD-19 | Unsafe submission은 block해야 합니다. | Draft가 stale이거나, selected inline comments가 current diff positions와 더 이상 맞지 않거나, diff position validation이 불가능하거나, valid reviewed head SHA가 없으면 Submit이 disabled됩니다. |
| PRD-20 | GitHub review submission은 reviewed commit ID를 사용해야 합니다. | Review payload는 event, body, `commit_id`로 reviewed head SHA, selected comments의 `path`, `position`, `body`를 포함합니다. |
| PRD-21 | Error는 recoverable하고 redacted되어야 합니다. | Recoverable error는 operation, summary, details, recovery suggestion, token/authorization header에 대한 sensitive text redaction을 포함합니다. |
| PRD-22 | Settings는 maintenance control을 제공해야 합니다. | Settings는 appearance, language, readiness, GitHub sign-in/validation/restoration/deletion, Codex check/login helper, privacy acknowledgement, private-consent clearing을 포함합니다. |
| PRD-23 | Localization은 app UI를 포함해야 합니다. | English가 default localization이고 Korean resource가 label, command, dialog, status copy, count-sensitive text에 존재합니다. Protocol data는 localized하지 않습니다. |
| PRD-24 | Verification은 local이고 deterministic해야 합니다. | `scripts/verify.sh`는 Swift testing probe, localization check, app build, UI smoke renderer, executable core tests를 live credential 없이 실행합니다. |

## 성공 기준

- First-time user는 GitHub, Codex, privacy setup 완료 후에만 review workspace에 도달할 수 있습니다.
- 저장된 setup이 있는 returning user는 session restoration과 readiness check 후 review workspace로 바로 열 수 있습니다.
- Reviewer는 draft를 만들고, 생성된 body/comment를 모두 검토하고, selected comments를 바꾸고, 게시될 내용을 정확히 preview할 수 있습니다.
- Stale PR 또는 invalid inline comment는 정상 UI를 통해 submit할 수 없습니다.
- Empty inbox filter는 zero row filter를 포함해 click 시 안정적으로 선택 상태를 유지합니다.
- 전체 local verification gate가 live GitHub 또는 Codex call 없이 통과합니다.

## 제약

- macOS app target은 SwiftPM의 SwiftUI를 사용하고 minimum platform은 macOS 14입니다.
- GitHub API access는 REST endpoint와 bearer authorization을 사용합니다.
- GitHub OAuth는 private repository를 포함하기 위해 현재 broad `repo` scope를 요청합니다.
- Codex generation은 local `codex` executable availability와 ChatGPT login에 의존합니다.
- 현재 standard test command는 executable `PRReviewDeskCoreTests`입니다. `swift test`는 아직 required gate가 아니라고 문서화되어 있습니다.
