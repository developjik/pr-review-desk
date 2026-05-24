# 문서 주도 개발 워크플로우

상태: Implemented

이슈: local workflow setup
PR: 대기 중
날짜: 2026-05-24
담당: Codex

## 요약

현재 제품 기준 문서와 미래 변경 제안을 분리하는 문서 우선 워크플로우를 정착시킵니다. 이후 작업은 리뷰 가능한 변경 문서에서 시작하고, 구현 완료 후 현재 문서를 실제 구현과 일치하도록 갱신합니다.

## 문제

프로젝트에는 현재 상태 제품 문서가 생겼습니다. 앞으로의 변경은 구현 전 원하는 동작을 설명할 안전한 위치가 필요합니다. 그렇지 않으면 `main`이 아직 구현되지 않은 동작을 이미 존재하는 것처럼 설명할 위험이 있습니다.

## 목표

- `docs/product/*`를 현재 구현과 일치하게 유지합니다.
- 제안/진행 중 변경을 위한 `docs/changes/*`를 추가합니다.
- 재사용 가능한 변경 제안 템플릿을 제공합니다.
- GitHub issue/PR checklist로 일반 작업 흐름에서 이 규칙이 보이게 합니다.
- 현재 문서를 언제 수정해야 하고 언제 수정하면 안 되는지 문서화합니다.

## 비목표

- 모든 오탈자 수정에 변경 제안을 강제하지 않습니다.
- 기존 `docs/superpowers/*` 계획/스펙을 대체하지 않습니다.
- 현재 검증 명령을 넘어서는 문서 자동 검증을 추가하지 않습니다.

## 현재 동작

현재 제품 문서는 `docs/product/`에 있고, 이전 계획/스펙은 `docs/superpowers/`에 있습니다. 미래 동작과 현재 제품 기준을 분리하는 전용 제안 폴더나 PR checklist는 없습니다.

## 제안 동작

사소하지 않은 미래 작업은 `docs/changes/YYYY-MM-DD-slug.md` 제안에서 시작합니다. 제안이 `Proposed` 또는 `Accepted`로 명확히 표시되어 있으면 구현 전에 merge할 수 있습니다. 제품 문서는 구현 완료 후 또는 기존 구현과 문서를 일치시키는 보정 작업에서만 갱신합니다.

## 사용자 이야기

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-01 | 유지보수자로서 current docs가 구현된 동작만 설명하길 원한다. 그래야 `main`을 신뢰할 수 있다. | `docs/development/document-driven-workflow.md`가 이 규칙을 설명하고, PR checklist가 current docs 갱신 여부를 묻는다. |
| US-02 | 유지보수자로서 구현 전에 미래 변경이 문서화되길 원한다. 그래야 합의된 요구사항에서 코딩을 시작할 수 있다. | `docs/changes/TEMPLATE.md`가 문제, 목표, 사용자 이야기, 사용자 흐름, 요구사항, UX, 개인정보, 테스트, 문서 갱신 섹션을 포함한다. |
| US-03 | 리뷰어로서 PR에서 변경 제안과 current-doc 갱신 여부를 확인하고 싶다. | `.github/PULL_REQUEST_TEMPLATE.md`가 문서 우선 checklist를 포함한다. |

## 사용자 흐름

1. 사용자가 사소하지 않은 변경을 식별합니다.
2. 사용자가 GitHub issue를 만듭니다.
3. 사용자가 `docs/changes/TEMPLATE.md`에서 변경 제안을 만듭니다.
4. 사용자가 제안을 승인받습니다.
5. 사용자가 제안을 기준으로 구현합니다.
6. 사용자가 현재 제품 문서와 정합성 리뷰를 갱신합니다.
7. 사용자가 `scripts/verify.sh`를 실행합니다.
8. 사용자가 제안/current-doc checklist를 완료한 PR을 엽니다.

## 기능 요구사항

| ID | 요구사항 | 수용 기준 |
| --- | --- | --- |
| FR-01 | 저장소는 current docs와 change proposal의 분리를 문서화해야 합니다. | `docs/development/document-driven-workflow.md`가 존재하고 README 및 제품 문서에서 연결된다. |
| FR-02 | 저장소는 변경 제안 템플릿을 제공해야 합니다. | `docs/changes/TEMPLATE.md`가 필요한 섹션을 포함한다. |
| FR-03 | 저장소는 PR 작성자가 이 워크플로우를 따르도록 안내해야 합니다. | `.github/PULL_REQUEST_TEMPLATE.md`가 proposal, current-doc, alignment, verification 체크를 포함한다. |
| FR-04 | 저장소는 issue 생성 시 변경 제안 작성을 안내해야 합니다. | `.github/ISSUE_TEMPLATE/change-proposal.md`가 존재하고 `docs/changes`를 가리킨다. |

## UX 메모

이 변경은 앱 UI가 아니라 contributor workflow에 영향을 줍니다. 문서는 README와 `docs/product/README.md`에서 쉽게 찾을 수 있어야 합니다.

## 데이터, 개인정보, 보안

앱 데이터나 runtime security 동작은 바뀌지 않습니다. 템플릿은 앞으로의 제안이 data, privacy, security 영향을 기록하도록 요구합니다.

## 테스트와 검증

- 문서 파일이 존재하고 비어 있지 않습니다.
- Markdown 변경이 whitespace check를 통과합니다.
- 전체 검증 gate가 계속 통과합니다:

```bash
scripts/verify.sh
```

## 갱신한 현재 문서

- `README.md`
- `docs/product/README.md`

## Rollout 및 Migration

Runtime migration은 필요하지 않습니다. 기존 historical docs는 유지하고 변환하지 않습니다.

## 열린 질문

- 없음.

## 구현 체크리스트

- [x] 제안 승인.
- [x] 워크플로우 가이드 추가.
- [x] 변경 제안 템플릿 추가.
- [x] Issue template 추가.
- [x] PR template 추가.
- [x] 현재 제품 문서에서 workflow 연결.
- [x] 검증 계획 수립.
