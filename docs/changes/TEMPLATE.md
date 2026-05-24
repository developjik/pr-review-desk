# 변경 제목

상태: Proposed

Issue: <!-- GitHub issue 링크 -->
PR: <!-- 구현이 시작되면 PR 링크 -->
날짜: YYYY-MM-DD
담당: <!-- 변경을 주도하는 사람 또는 agent -->

## 요약

의도한 변경을 짧은 문단 하나로 설명합니다.

## 문제

현재 사용자가 겪는 문제 또는 엔지니어링 문제를 설명합니다. 필요하면 현재 제품 문서와 source 파일을 연결합니다.

## 목표

- 목표 1.
- 목표 2.

## 비목표

- 관련은 있지만 이번 범위에서 제외하는 일을 명시합니다.

## 현재 동작

앱이 현재 어떻게 동작하는지 설명합니다. 이 섹션은 `docs/product/*`와 현재 source에 일치해야 합니다.

## 제안 동작

사용자 관점과 시스템 관점에서 무엇이 바뀌어야 하는지 설명합니다.

## 사용자 이야기

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-01 | 사용자로서 ... 하고 싶다. | Given ..., when ..., then ... |

## 사용자 흐름

1. 사용자는 ...에서 시작합니다.
2. 사용자는 ...을 선택합니다.
3. 앱은 ...로 응답합니다.
4. 사용자는 ...을 확인합니다.

## 기능 요구사항

| ID | 요구사항 | 수용 기준 |
| --- | --- | --- |
| FR-01 | 앱은 ... 해야 합니다. | ...로 검증합니다. |

## UX 메모

UI surface, label, empty state, disabled state, keyboard behavior, accessibility 기대값, localization 필요 사항을 설명합니다.

## 데이터, 개인정보, 보안

저장 데이터, 외부 API 호출, secret, private repository 처리, redaction, consent, failure mode를 설명합니다.

## 테스트와 검증

- Unit 또는 harness tests:
- UI smoke coverage:
- 수동 QA:
- 필수 명령:

```bash
scripts/verify.sh
```

## 구현 후 갱신할 현재 문서

- `docs/product/prd.md`
- `docs/product/user-stories.md`
- `docs/product/user-flows.md`
- `docs/product/functional-spec.md`
- `docs/product/implementation-alignment-review.md`

## Rollout 및 Migration

Migration, backward compatibility, saved state 처리, 또는 필요 없는 이유를 설명합니다.

## 열린 질문

- 질문 1.

## 구현 체크리스트

- [ ] 제안이 승인됨.
- [ ] 테스트가 추가 또는 갱신됨.
- [ ] 구현 완료.
- [ ] 현재 제품 문서 갱신 완료.
- [ ] 정합성 리뷰에 source/test 근거 추가 완료.
- [ ] `scripts/verify.sh` 통과.
- [ ] 제안 상태를 `Implemented`로 변경.
