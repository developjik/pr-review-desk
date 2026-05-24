# 문서 주도 개발 워크플로우

상태: 활성 프로젝트 워크플로우.

## 핵심 규칙

`main`은 `main`이 실제로 구현하지 않은 제품 상태를 설명하면 안 됩니다.

이 프로젝트는 현재 상태 문서와 미래 변경 문서를 분리합니다:

- `docs/product/`: 현재 제품 기준 문서입니다. 같은 브랜치의 앱 구현과 반드시 일치해야 합니다.
- `docs/changes/`: 제안되었거나 진행 중인 변경 문서입니다. 상태가 명확하다면 아직 구현되지 않은 미래 동작을 설명할 수 있습니다.

## 문서 종류

| 종류 | 위치 | 목적 | 미래 동작 설명 가능 여부 |
| --- | --- | --- | --- |
| 현재 PRD | `docs/product/prd.md` | 현재 코드가 구현한 제품 요구사항. | 아니오 |
| 현재 user stories | `docs/product/user-stories.md` | 현재 코드가 지원하는 사용자 이야기와 수용 기준. | 아니오 |
| 현재 user flows | `docs/product/user-flows.md` | 현재 존재하는 end-to-end 흐름과 분기. | 아니오 |
| 현재 기능 명세 | `docs/product/functional-spec.md` | 현재 구현 수준의 동작. | 아니오 |
| 현재 정합성 리뷰 | `docs/product/implementation-alignment-review.md` | 현재 문서가 source/tests와 일치한다는 근거. | 아니오 |
| 변경 제안 | `docs/changes/YYYY-MM-DD-slug.md` | 하나의 변경에 대한 미래 또는 진행 중인 동작. | `Implemented`가 아니면 가능 |
| 결정 기록 | `docs/decisions/YYYY-MM-DD-topic.md` | 지속되어야 하는 아키텍처/제품 결정과 trade-off. | 결정 맥락으로 표시되면 가능 |
| 과거 계획/스펙 | `docs/superpowers/` | agent 실행 이력과 구현 계획. | 가능하지만 현재 제품 기준은 아님 |

## 변경 제안 상태

모든 `docs/changes/*` 파일 상단에는 다음 중 하나의 상태를 사용합니다:

- `Proposed`: 논의를 위해 작성됨. 아직 구현 약속은 없음.
- `Accepted`: 방향이 승인되었지만 아직 구현되지 않음.
- `Implementing`: 브랜치에서 구현 중.
- `Implemented`: 구현이 merge되었거나 merge 준비가 되었고, `docs/product/*`가 실제 구현과 일치하도록 갱신됨.
- `Superseded`: 다른 제안이나 결정으로 대체됨.

## 표준 워크플로우

1. 변경에 대한 GitHub issue를 만들거나 기존 issue를 찾습니다.
2. `docs/changes/TEMPLATE.md`를 복사해 `docs/changes/YYYY-MM-DD-slug.md`를 만듭니다.
3. 문제, 목표, 비목표, user stories, user flows, 요구사항, UX 메모, data/privacy/security 메모, 수용 기준, 검증, 구현 후 갱신할 현재 문서를 채웁니다.
4. 변경이 제안 상태일 때는 `docs/product/*`를 바꾸지 않습니다.
5. 승인된 변경 제안을 기준으로 구현합니다.
6. 위험도에 맞는 테스트와 smoke coverage를 추가하거나 갱신합니다.
7. 구현된 앱과 일치하도록 `docs/product/*`를 갱신합니다.
8. `docs/product/implementation-alignment-review.md`에 새 동작의 source/test 근거를 추가합니다.
9. 변경 제안을 `Implemented`로 표시하고 issue/PR을 연결합니다.
10. `scripts/verify.sh`를 실행합니다.
11. PR checklist에 변경 제안과 현재 문서 갱신을 연결한 상태로 PR을 엽니다.

## PR 규칙

순수 제안 PR:

- `docs/changes/*`를 추가하거나 수정할 수 있습니다.
- 제안의 일부라면 결정 기록을 추가할 수 있습니다.
- 구현되지 않은 동작을 현재 동작처럼 보이게 `docs/product/*`에 쓰면 안 됩니다.
- script나 source 파일을 바꾸지 않았다면 앱 테스트는 필수는 아닙니다.

구현 PR:

- 변경 제안을 연결해야 합니다. 변경 제안이 필요 없는 문서-only/current-doc correction이라면 명시합니다.
- 사용자에게 보이는 동작, 제품 요구사항, 흐름, 저장소, 인증, 보안, 검증, UI 상태가 바뀌면 `docs/product/*`를 갱신해야 합니다.
- 구현 정합성 리뷰에 source/test 근거를 추가해야 합니다.
- `scripts/verify.sh`를 실행해야 하며, 실행하지 못했다면 이유를 설명해야 합니다.

현재 문서 보정 PR:

- 목표가 기존 구현과 일치하도록 문서를 바로잡는 것이라면 변경 제안 없이 `docs/product/*`를 갱신할 수 있습니다.
- source/tests 또는 UI smoke output 근거를 포함해야 합니다.

## 이름 규칙

날짜 prefix와 lowercase slug를 사용합니다:

```text
docs/changes/2026-05-24-selected-file-regeneration.md
docs/changes/2026-05-24-submit-preview-invalid-comment-recovery.md
```

각 제안은 독립적으로 리뷰할 수 있는 하나의 변경에 집중합니다. 관련 없는 여러 workflow를 건드리는 큰 작업은 여러 제안 파일로 나눕니다.

## 하지 말아야 할 것

- 미래 동작을 `docs/product/functional-spec.md`에 쓰지 않습니다.
- 코드, 테스트, 현재 문서, 정합성 근거가 갱신되기 전에 제안을 `Implemented`로 표시하지 않습니다.
- 수용 기준을 모호하게 남기지 않습니다. 코드, UI smoke, 수동 QA, source inspection 중 하나로 검증 가능해야 합니다.
- merge 대상 문서에 `TBD`나 placeholder 요구사항을 남기지 않습니다.

## 검증

구현 PR을 merge하기 전에는 전체 gate를 사용합니다:

```bash
scripts/verify.sh
```

문서-only 변경에서는 다음도 실행합니다:

```bash
git diff --check
rg -n "[ \t]+$" README.md docs .github
```

문서 변경이 예시, 템플릿, script, workflow 파일을 바꾼다면 관련 script나 parser도 함께 실행합니다.
