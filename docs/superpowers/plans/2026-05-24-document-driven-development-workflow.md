# 문서 주도 개발 워크플로우 구현 계획

> **Agent 작업자 안내:** 이 계획을 task-by-task로 구현할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용합니다. Step은 checkbox(`- [ ]`) 형식으로 추적합니다.

**목표:** 현재 제품 문서와 미래 변경 제안을 분리하는 반복 가능한 문서 주도 워크플로우를 정착시킨다.

**아키텍처:** `docs/development`에는 프로세스 문서를 두고, `docs/changes`에는 제안 문서 인프라를 둔다. `.github`에는 issue/PR template을 추가한다. README와 제품 문서에서 workflow를 연결해 future implementation work 전에 쉽게 찾을 수 있게 한다.

**기술 스택:** Markdown 문서, GitHub issue template, GitHub pull request template, 기존 `scripts/verify.sh` gate.

---

### Task 1: 워크플로우 문서 추가

**Files:**
- Create: `docs/development/document-driven-workflow.md`
- Create: `docs/changes/README.md`
- Create: `docs/changes/TEMPLATE.md`

- [x] **Step 1: current-doc와 proposal-doc 경계 정의**

`docs/product/*`는 현재 구현과 일치해야 하고, `docs/changes/*`는 상태가 명확할 때 미래 동작을 설명할 수 있다는 규칙을 작성한다.

- [x] **Step 2: 제안 생명주기 정의**

`Proposed`, `Accepted`, `Implementing`, `Implemented`, `Superseded`를 문서화한다.

- [x] **Step 3: 재사용 가능한 제안 템플릿 추가**

문제, 목표, 비목표, 현재 동작, 제안 동작, user stories, user flows, 기능 요구사항, UX 메모, data/privacy/security, 테스트, 문서 갱신, rollout, 열린 질문, 구현 checklist 섹션을 포함한다.

### Task 2: GitHub workflow hook 추가

**Files:**
- Create: `.github/PULL_REQUEST_TEMPLATE.md`
- Create: `.github/ISSUE_TEMPLATE/change-proposal.md`

- [x] **Step 1: PR checklist 추가**

PR 작성자가 proposal을 연결하거나 필요 없는 이유를 설명하고, current docs를 맞추고, 동작 변경 시 alignment review를 갱신하고, verification을 실행하도록 요구한다.

- [x] **Step 2: Issue template 추가**

새 변경이 구현 전에 `docs/changes/TEMPLATE.md`로 향하도록 안내한다.

### Task 3: 문서 연결

**Files:**
- Modify: `README.md`
- Modify: `docs/product/README.md`

- [x] **Step 1: README에서 workflow 연결**

`docs/development/document-driven-workflow.md`와 `docs/changes/`를 가리키는 개발 workflow 섹션을 추가한다.

- [x] **Step 2: 제품 문서에서 workflow 연결**

제품 문서는 current-state truth이고 미래 동작은 change proposal에 둔다는 점을 설명한다.

### Task 4: 검증

**Files:**
- No source files expected.

- [x] **Step 1: Whitespace 확인**

`git diff --check`와 README, docs, GitHub template 대상 trailing whitespace 검색을 실행한다.

- [x] **Step 2: 전체 gate 실행**

`scripts/verify.sh`를 실행해 기존 build, UI smoke, localization, harness tests가 계속 통과하는지 확인한다.
