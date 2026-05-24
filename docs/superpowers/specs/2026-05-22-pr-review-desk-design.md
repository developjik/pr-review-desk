# PR Review Desk 설계

> Historical note: 이 문서는 2026-05-22에 작성된 original MVP design입니다. 현재 제품 기준 문서가 아닙니다. 앱은 이제 GitHub OAuth device flow, settings-gated first-run path, review inbox, private repository consent, saved drafts, background draft queue를 사용합니다. 현재 PRD, user stories, user flows, functional specification, implementation alignment review는 `docs/product/`를 사용하세요.

## 목표

Developer가 Codex로 GitHub pull request를 review하도록 돕는 개인용 macOS app을 만듭니다. 앱은 repository와 open PR을 browse하고, AI review draft를 생성하고, 사용자가 comment를 edit/choose하게 하고, 승인된 review만 GitHub로 submit해야 합니다.

## 범위

MVP는 개인용이며 developer-focused입니다. Multi-user account, backend server, GitHub OAuth, billing, hosted automation은 필요하지 않습니다.

앱이 사용하는 것:

- GitHub access를 위한 GitHub Personal Access Token. macOS Keychain에 저장.
- AI review generation을 위한 local Codex CLI login.
- Repository browsing, PR browsing, diff retrieval, review submission을 위한 GitHub REST API.
- Installed Command Line Tools로 build할 수 있도록 SwiftPM 사용.

## Core Flow

1. 사용자가 macOS app을 엽니다.
2. 저장된 token이 없으면 사용자가 GitHub PAT를 입력합니다.
3. 앱이 accessible repositories를 list합니다.
4. 사용자가 repository를 선택합니다.
5. 앱이 해당 repository의 open pull requests를 list합니다.
6. 사용자가 pull request를 선택합니다.
7. 앱이 PR metadata와 changed files를 fetch합니다.
8. 사용자가 Generate Review를 click합니다.
9. Local helper가 structured JSON schema로 non-interactive `codex exec`를 invoke합니다.
10. Codex가 summary, risks, inline comment candidate가 있는 review draft를 반환합니다.
11. 앱이 editable review body와 selectable inline comments를 보여줍니다.
12. 사용자가 `Comment`, `Approve`, `Request changes` 중 하나를 선택합니다.
13. 앱이 review를 GitHub로 submit합니다.

## 아키텍처

Swift package는 세 target을 가집니다:

- `PRReviewDeskCore`: models, GitHub API client, diff position mapping, Keychain storage, Codex runner, review orchestration.
- `PRReviewDeskApp`: core library를 사용하는 SwiftUI macOS app.
- `PRReviewDeskCoreTests`: core behavior unit tests.

앱은 network와 process execution을 protocol 뒤에 둬서 GitHub 또는 Codex call 없이 core behavior를 test할 수 있게 합니다.

## GitHub Integration

GitHub client는 REST endpoint를 사용합니다:

- `GET /user/repos`: accessible repositories list.
- `GET /repos/{owner}/{repo}/pulls?state=open`: open PR list.
- `GET /repos/{owner}/{repo}/pulls/{number}`: PR metadata와 head SHA fetch.
- `GET /repos/{owner}/{repo}/pulls/{number}/files`: changed files와 patches fetch.
- `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews`: review submit.

Review submission이 사용하는 값:

- `event`: `COMMENT`, `APPROVE`, `REQUEST_CHANGES`.
- `body`: edited review body.
- `comments`: `path`, `position`, `body`가 있는 selected inline comments.

GitHub docs에 따르면 `position`은 file line number가 아니라 file의 first diff hunk header에서 몇 line 아래인지 나타내는 값입니다. 따라서 앱은 Codex로 보내기 전에 patch에 diff position을 annotate합니다.

## Codex Integration

Codex integration은 local `codex exec`를 다음 option으로 실행합니다:

- `--skip-git-repo-check`
- `--sandbox read-only`
- `--ephemeral`
- `--output-schema <schema>`
- `--output-last-message <result-file>`

Prompt는 PR metadata와 annotated patches를 포함합니다. Output schema는 다음을 요구합니다:

- `summary`: string
- `risks`: string array
- `inline_comments`: `{ path, position, body, severity }` array

앱은 JSON을 사용자에게 보여주기 전에 validate합니다. Invalid JSON, missing Codex login, missing `codex` binary, process failure는 recoverable UI error로 표시합니다.

## UI

MVP UI는 three-column SwiftUI layout입니다:

- Left sidebar: repository list와 refresh.
- Middle column: selected repository의 open PR list.
- Main pane: selected PR details, Generate Review action, editable review body, inline comment candidates, event picker, Submit Review.

앱은 landing page보다 utilitarian density를 선호합니다. 반복적인 review session을 위한 work tool입니다.

## Error Handling

앱이 보고하는 것:

- Missing GitHub token.
- Invalid 또는 unauthorized GitHub token.
- Empty repository 또는 PR lists.
- GitHub rate limit 또는 validation errors.
- Missing Codex CLI.
- Codex process timeout 또는 non-zero exit.
- GitHub review submission failures.

Secret은 project file이나 log에 쓰지 않습니다.

## 테스트

Unit test cover 범위:

- GitHub patch text의 diff position mapping.
- Codex output decoding과 validation.
- Fake command runner를 사용한 Codex runner command construction/result parsing.
- GitHub request construction과 review payload encoding.

Manual verification cover 범위:

- `swift test`
- `swift build`
- Codex CLI smoke test
- `/user` 대상 GitHub token smoke test
- App target 실행

## 향후 작업

MVP 이후:

- PAT를 GitHub OAuth로 교체.
- Review quality 개선을 위한 local repository context 추가.
- Selected repositories에 대한 background review generation 추가.
- Per-repository review policy prompt 추가.
- Team use를 위한 GitHub App/server mode 추가.
