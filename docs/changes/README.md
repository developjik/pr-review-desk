# 변경 제안

이 폴더는 제품, UX, 아키텍처, 보안, 워크플로우, 기능 변경을 제안하거나 진행 중일 때 사용합니다.

규칙은 단순합니다:

- `docs/product/`는 앱이 현재 실제로 하는 일을 설명합니다.
- `docs/changes/`는 앞으로 바꾸고 싶은 일을 설명합니다.

사소하지 않은 변경은 [TEMPLATE.md](./TEMPLATE.md)에서 시작합니다.

## 생명주기

1. `Proposed`: 아이디어를 리뷰할 수 있게 문서화한 상태.
2. `Accepted`: 방향이 승인된 상태.
3. `Implementing`: 브랜치에서 작업 중인 상태.
4. `Implemented`: 코드, 테스트, 현재 문서, 정합성 리뷰가 갱신된 상태.
5. `Superseded`: 제안이 대체되었거나 중단된 상태.

## Merge 기준

제안이 `Proposed` 또는 `Accepted`로 명확히 표시되어 있다면 구현 전에 merge할 수 있습니다. 단, 미래 동작을 현재 동작처럼 보이게 `docs/product/*`를 갱신하면 안 됩니다.

구현 PR은 관련 제안을 연결하고, merge 전 현재 제품 문서를 갱신해야 합니다.

## 이름 규칙

```text
YYYY-MM-DD-short-change-name.md
```

예시:

```text
2026-05-24-selected-file-regeneration.md
```
