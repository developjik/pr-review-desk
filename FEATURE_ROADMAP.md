# PR Review — 기능 로드맵 (Feature Roadmap)

> 생성일: 2026-07-21
> 전체 프로젝트 분석 기반 추가 기능 리스트. 구현 여부는 본문 시점의 코드 기준.

---

## 📊 현재 구현된 핵심 기능

| 영역 | 구현 내용 |
|------|----------|
| **리뷰 파이프라인** | Poll → Discover → Review(청킹/토큰예산) → LineMap → Publish |
| **리뷰 모드** | `auto`(즉시 게시) + `pending`(승인 대기, 편집/선택/거부 지원) |
| **필터링** | 리포 glob 포함/제외, trigger/skip 라벨, reaper(merged/closed 정리) |
| **신뢰성** | dedupe(prId+headSha), 큐 재시도(지수 백오프), rate-limit 재시도, orphan reclaim |
| **가이드라인** | 글로벌 `reviewRules` + 리포별 `.prreview/rules.md` 병합 |
| **LLM** | 멀티랭귀지 감지(ko/ja/zh/en), 심각도(high/med/low), 4영역(bug/style/structure/security) |
| **호스트** | 트레이 아이콘 상태 색, OS 알림, autostart, 단일 인스턴스, OS 키체인 비밀 저장 |
| **UI** | Wizard/Settings/Inbox/Logs/Pending, 명령 팔레트(⌘K), 키보드 단축키, 토스트 |
| **플랫폼** | macOS arm64 단일 타겟 (Linux/Windows는 stub) |

---

## 🎯 추가 기능 리스트 (우선순위순)

### 🟥 P0 — 핵심 경쟁력 / 사용자 가치 직결

1. **크로스 플랫폼 빌드 (Linux / Windows / Intel macOS)**
   - 현재 `node22-macos-arm64` 단일 타겟. `src-tauri/binaries/`에 stub만 존재.
   - yao-pkg/pkg 크로스 컴파일 파이프라인 + GitHub Actions 매트릭스 빌드.

2. **GitHub App 인증 (PAT 외 추가 경로)**
   - PAT 대신 GitHub App 설치 → 더 높은 rate limit, 조직 단위 배포, 만료 걱정 없음.
   - `secrets.rs`는 키체인 저장만 지원, 인증 방식 다변화 필요.

3. **자동 업데이트 메커니즘**
   - `tauri-plugin-updater` 도입. 현재 배포 후 수동 업데이트만 가능.

4. **LLM 비용/토큰 사용량 추적**
   - `reviewer/`에 토큰 카운터 존재하지만 비용 환산·예산 한도 기능 없음.
   - 일/월 예산 초과 시 자동 pause, Settings에 사용량 차트.

### 🟧 P1 — 리뷰 품질 / 기능 확장

5. **PR 크기 기반 리뷰 전략 (Diff Threshold)**
   - `orchestrator-diff-threshold.test.ts`가 diff_json 크기 경고만 테스트. 실제 "대형 PR은 스킵 또는 핵심 파일만" 정책 부재.
   - `chunker.ts`의 `ABSOLUTE_MAX_DIFF_LINES=5000` 하드컷 외에 사용자 설정 임계값 필요.

6. **증분 리뷰 (새 커밋만)**
   - 현재 headSha 기반 dedupe → 새 push 시 전체 재리뷰. base..head 전체가 아닌 `이전 리뷰 sha..head` diff만 리뷰.

7. **파일 경로 필터 (포함/제외 패턴)**
   - 리포 단위가 아닌 파일 단위: `src/**` 포함, `**/*.generated.ts`, `vendor/`, `dist/` 제외.
   - 청커에 추가 우선순위 계층으로 자연스럽게 통합 가능.

8. **Draft PR / Bot PR 처리 정책**
   - Draft는 리뷰 보류 옵션, dependabot/renovate는 auto-approve 또는 요약만 옵션.
   - `filter.ts`의 author 기반 매칭 추가.

9. **리뷰 영역 확장 (performance / accessibility / docs / tests)**
   - 현재 4개 영역(bug/style/structure/security) 고정. 영역별 on/off 토글 + 프롬프트 모듈화.

10. **대화형 리뷰 (Reply-to-existing-comment)**
    - GitHub의 `in_reply_to` 지원. 기존 코멘트 스레드에 응답, 사용자가 단 코멘트에 리뷰어가 답글.
    - `publisher.ts`에 `pulls.createReviewReply` 통합.

### 🟨 P2 — 운영 / 관측성

11. **통계 대시보드**
    - 일/주간 리뷰 수, 발견된 findings, 파일별 false-positive율.
    - Monitoring 탭의 history 확장 또는 신규 Stats 탭.

12. **False-Positive 피드백 루프**
    - 사용자가 finding "무시"/"유용" 표시 → DB에 축적 → 프롬프트 개선 또는 무시 패턴 학습.

13. **Slack/Discord/Webhook 알림**
    - `osNotify` 외에 외부 채널 전파. pending 리뷰 대기 알림.

14. **리뷰 히스토리 검색/필터**
    - Monitoring의 `history` 탭 확장: 리포, 날짜, 심각도, 작성자 필터.

15. **정기 리포트 / 다이제스트**
    - 일일/주간 이메일 또는 인앱 요약.

16. **Quiet Hours / 스케줄 일시정지**
    - 폴링은 계속하되 알림/리뷰 게시를 야간/주말에 억제.

17. **동시성 제어 (병렬 리뷰)**
    - 현재 `processQueue` 순차 처리. N개 PR 동시 리뷰 옵션 (rate limit 내에서).

### 🟩 P3 — 인증 / 보안 / 컴플라이언스

18. **OAuth Device Flow (PAT 없는 온보딩)**
    - 토큰 복붙 대신 브라우저 인증. Wizard UX 개선.

19. **감사 로그 (Audit Log)**
    - 누가 언제 approve/reject했는지, 설정 변경 이력. 다중 사용자 환경 대비.

20. **크리덴셜 순환 리마인더**
    - PAT 만료 임박 알림 (GitHub API로 만료일 조회 가능).

21. **GitHub Webhooks 지원 (폴링 보조)**
    - 실시간 트리거 옵션. 퍼블릭 엔드포인트 필요하므로 optional 사이드카 모드.

### 🟦 P4 — 사용자 경험 / UI

22. **Light 테마 (토큰 스왑)**
    - DESIGN.md §13에 명시된 "future token-swap" 경로. `tokens.css` 구조가 이미 준비됨.

23. **다국어 UI (i18n)**
    - 힌트만 한국어, 크롬은 영어 고정(D3). 언어 토글로 UI 전체 번역.

24. **백업/내보내기/가져오기**
    - DB와 설정 내보내기. 기기 이전 대비.

25. **상태 점검 / 자가 진단 (Health Check)**
    - PAT 권한, LLM 연결, DB 무결성, 디스크 용량 통합 점검 화면.

26. **GitHub Status Checks 통합**
    - PR의 CI 통과/실패 상태를 리뷰 컨텍스트에 반영 (실패한 CI 영역 우선 리뷰).

### 🟪 P5 — 고급 / 차별화

27. **코드 커버리지 인식**
    - PR이 코드를 추가했지만 테스트가 없으면 경고. Coverage 리포트 파싱 또는 `*.test.*` 존재 여부 휴리스틱.

28. **시크릿 스캐닝 / 의존성 취약점**
    - diff 내 하드코딩 시크릿, `package.json`/`Cargo.toml` 변경 시 취약점 DB 조회.

29. **코드 오너 인식 라우팅**
    - `CODEOWNERS` 파싱 → 각 영역 담당자 컨텍스트를 프롬프트에 주입.

30. **브랜치 보호 규칙 제안**
    - 리뷰 품질 데이터 기반으로 "이 리포는 브랜치 보호가 약함" 제안.

31. **다중 GitHub 계정 / 다중 LLM 프로필**
    - 개인/회사 계정 전환, 모델별 프로필 (싼 모델/비싼 모델 상황별 적용).

32. **팀 규칙 템플릿 / 프리셋 공유**
    - 검증된 `reviewRules` 프리셋을 팀 단위 공유/임포트.

---

## 💡 추천 즉시 착수 순서

**1차 스프린트 (배포 도달도)**: #1 크로스플랫폼 → #3 자동업데이트 → #4 비용 추적
**2차 스프린트 (리뷰 품질)**: #5 diff threshold → #7 파일 필터 → #8 draft/bot 정책 → #6 증분 리뷰
**3차 스프린트 (관측성)**: #11 통계 → #12 FP 피드백 → #14 히스토리 검색

> 가장 시급한 것은 **#1 크로스 플랫폼 빌드** — 현재 macOS Apple Silicon 사용자만 타겟 가능하여 도달 범위가 제한적. 이후 리뷰 품질 계열(#5~#9)이 사용자 유지율에 직결.
