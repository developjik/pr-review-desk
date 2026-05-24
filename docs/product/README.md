# PR Review Desk 제품 문서

이 폴더는 2026-05-24 현재 worktree 기준의 제품 문서 원천입니다.

문서는 Swift package, SwiftUI app code, 실행형 테스트 harness, smoke renderer, 현재 README를 근거로 작성했습니다. 현재 worktree의 앱이 실제로 제공하는 review inbox, GitHub OAuth device sign-in, settings gate, background draft queue, Codex review generation, diff workspace, GitHub review submission guard를 설명합니다.

## 문서

- [PRD](./prd.md): 제품 의도, 범위, 요구사항, 제약, 수용 기준.
- [사용자 이야기](./user-stories.md): persona별 사용자 이야기와 수용 조건.
- [사용자 흐름](./user-flows.md): end-to-end UI flow, 분기, empty/error state.
- [기능 명세](./functional-spec.md): data, UI, auth, AI review, draft, submission의 구현 수준 동작.
- [구현 정합성 리뷰](./implementation-alignment-review.md): 문서가 현재 프로젝트와 일치한다는 evidence map, 알려진 gap, superseded historical docs.

## 변경 워크플로우

제품 문서는 현재 상태 문서입니다. 같은 브랜치에 구현된 동작만 설명해야 합니다.

미래 동작은 먼저 [`docs/changes`](../changes/README.md)에 작성합니다. 변경을 계획하거나 구현할 때는 [문서 주도 개발 워크플로우](../development/document-driven-workflow.md)를 사용합니다:

1. 변경 제안을 작성하거나 갱신합니다.
2. 승인된 제안을 기준으로 구현합니다.
3. 구현된 앱과 일치하도록 제품 문서를 갱신합니다.
4. source/test 근거로 정합성 리뷰를 갱신합니다.
5. 검증 gate를 실행합니다.

## 현재 제품 형태

PR Review Desk는 개인 pull request review를 위한 local macOS SwiftUI app입니다. GitHub OAuth device flow로 sign-in하고, repository access를 검증하며, local Codex CLI ChatGPT login을 확인하고, AI/privacy disclosure acknowledgement를 요구합니다. 이후 Codex로 editable AI review draft를 생성하고 사용자가 확인한 GitHub review만 게시합니다.

Main window는 settings-gated입니다. Setup이 불완전하면 main window는 Settings로 안내합니다. Setup이 완료되면 workspace는 filter가 있는 review inbox, repository scope control, draft queue control, pull-request list, diff review workspace, trailing review inspector로 열립니다.

## 검증 범위

이 문서는 source와 tests에 맞춰 정렬되어 있으며, live GitHub 또는 live Codex output을 검증했다는 의미는 아닙니다. Alignment review에 기록된 검증 명령은 compile-time behavior, deterministic UI smoke rendering, localization check, executable core test harness를 다룹니다.
