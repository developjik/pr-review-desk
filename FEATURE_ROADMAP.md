# PR Review — 기능 로드맵 (Feature Roadmap)

> 최종 갱신: 2026-07-23. 본문은 코드베이스 직접 검증 기준 — 2026-07-23에 전 항목을 소스와 교차검증하고 `npm test` 386/386 통과 + `npm run typecheck` clean을 확인했다. ✅ = 구현 완료, 🟡 = 구현됐으나 활성화/검증 보류(human action 대기), ⬜ = 미구현(코드 부재 확인).

---

## ✅ 현재 구현된 핵심 기능

| 영역 | 구현 내용 | 상태 |
|------|----------|------|
| **리뷰 파이프라인** | Poll → Discover → Review(청킹/토큰예산) → LineMap → Publish | ✅ |
| **리뷰 모드** | `auto`(즉시 게시) + `pending`(승인 대기, 편집/선택/거부) | ✅ |
| **필터링** | 리포 glob 포함/제외, trigger/skip 라벨, reaper(merged/closed 정리), **draft PR 제외**(R22) | ✅ |
| **파일 필터** | `fileInclude`/`fileExclude` glob — 청커 stage 0에서 size/budget보다 먼저 (예: `src/**`, `**/*.generated.ts`) | ✅ |
| **PR 크기 전략** | `maxDiffLines`/`maxFiles`/`largePrPolicy`(trim\|abort) — config→chunker→reviewer→UI end-to-end | ✅ |
| **신뢰성** | dedupe(prId+headSha), 큐 재시도(지수 백오프), rate-limit 재시도, orphan reclaim | ✅ |
| **가이드라인** | 글로벌 `reviewRules` + 리포별 `.prreview/rules.md` 병합 (토큰 예산 트렁케이션) | ✅ |
| **LLM** | 멀티랭귀지 감지(ko/ja/zh/en), 심각도(high/med/low), 4영역(bug/style/structure/security) | ✅ |
| **비용/예산** | per-file 토큰 추적(`review-usage`, 재시도 중복카운트 방지), **모델별 비용 환산**, 월 예산 초과 자동 pause + UI 경고 | ✅ |
| **Bot PR 정책** | `botAuthors`/`botPolicy`(skip\|review) — filter Phase 0 author 매칭, config→poller→UI end-to-end (G001) | ✅ |
| **증분 리뷰** | `incrementalReview` — previousSha..head compare diff로 새 커밋만 리뷰, diverged/force-push 시 full fallback (G002) | ✅ |
| **리뷰 영역 토글** | `reviewAreas` — bug/style/structure/security 부분집합 on/off, 프롬프트 모듈화 (`buildAreasSection`) (G003) | ✅ |
| **리뷰 히스토리 영속화** | `review_history` 테이블(migration v7) — auto/pending 모드 결과 저장, approve/reject 시 status 업데이트 | ✅ |
| **통계 대시보드** | `getStatsSince`/`getStatsByDay` + SVG 차트 — 일별 리뷰 추이, 월간 비용/토큰 카드 | ✅ |
| **FP 피드백 루프** | `finding_feedback` 테이블 + Pending UI 👍/👎 버튼 → `markFinding` 커맨드 → 패턴 축적 | ✅ |
| **히스토리 검색/필터** | DB 기반 history + repo/severity 필터 + `useReviewHistory` 훅 (debounce) | ✅ |
| **호스트** | 트레이 아이콘 상태 색, OS 알림, autostart, 단일 인스턴스, OS 키체인 비밀 저장 | ✅ |
| **자동업데이트** | tauri-plugin-updater (Rust-driven check/install), 트레이·Settings 트리거, CI 서명+latest.json | 🟡 구현됨, 서명키 활성화 보류 |
| **UI** | Wizard/Settings/Inbox/Logs/Pending, 명령 팔레트(⌘K), 키보드 단축키, 토스트, 비용 차트 | ✅ |
| **플랫폼** | macOS arm64+x64(완료) · Linux AppImage · Windows MSI — CI 매트릭스 4타겟 네이티브 빌드 | 🟡 CI 구현됨, 태그푸시 검증 보류 |

> 🟡 항목은 코드는 완성됐으나 실제 릴리스/검증이 human action에 막혀 있음 — 자동업데이트는 서명 키페어 생성, 크로스플랫폼은 `git tag` 푸시 후 CI 실행 필요.

---

## 🎯 추가 기능 리스트 (우선순위순)

> 1차 스프린트(배포 도달도) 완료. 2차 스프린트(리뷰 품질: #4 Bot PR 정책 · #5 증분 리뷰 · #6 리뷰 영역 토글) 완료 — 전체 레이어(config→daemon→shared→UI→테스트) 구현 + 88개 테스트 통과. 아래는 잔여 기능.

### 🟥 P0 — 핵심 경쟁력 / 사용자 가치 직결

2. **auto-update 서명 활성화** 🟡 (human action)
   - 코드는 완성. `tauri signer generate` → pubkey를 `tauri.conf.json`에, private key를 repo secret(`TAURI_SIGNING_PRIVATE_KEY`)+`ENABLE_UPDATES` 변수 설정 후 태그 푸시.

3. **크로스플랫폼 CI 검증** 🟡 (human action)
   - 워크플로+셀프체크 완성. `git tag vX.Y.Z && git push --tags` → 4플랫폼 산출물 생성 확인.

### 🟧 P1 — 리뷰 품질 / 기능 확장 (2차 스프린트 ✅ 완료)

4. **Bot PR 처리 정책 (dependabot/renovate)** ✅ (G001)
   - ✅ 구현 완료: `shouldSkipBotAuthor()` Phase 0 author 매칭 + `botAuthors`/`botPolicy`(skip\|review) config → poller `discover()` → UI. 9개 테스트 통과.

5. **증분 리뷰 (새 커밋만)** ✅ (G002)
   - ✅ 구현 완료: `getPreviousSha()` + `fetchCompareDiff()`(compareCommits API) → orchestrator narrowing (previousSha..head) → diverged/force-push 시 full fallback. 4개 테스트 통과.

6. **리뷰 영역 토글 (bug/style/structure/security)** ✅ (G003)
   - ✅ 구현 완료: `buildAreasSection(areas)` 부분집합 on/off + `reviewAreas` config → llm-client → UI 체크박스. 5개 테스트 통과.

7. **대화형 리뷰 (Reply-to-existing-comment)** ✅
   - ✅ 구현 완료: `partitionByExisting` + `ExistingComment` id/review_id 확장 → `publishReview` auto 모드에서 `createReplyForReviewComment`로 기존 스레드에 응답(dedupe drop → reply). best-effort 실패 처리, null review_id drop, `replyToThreads` config(기본 false=현재 동작). AC2.1-2.5 + partition 테스트.

### 🟨 P2 — 운영 / 관측성 (3차 스프린트 ✅ 완료)

8. **통계 대시보드** ✅
   - ✅ 구현 완료: `review_history` 테이블(migration v7) + `getStatsSince`/`getStatsByDay` + Monitoring Summary 카드(월간 비용/토큰/일평균) + SVG 일별 추이 차트.

9. **False-Positive 피드백 루프** ✅
   - ✅ 구현 완료: `finding_feedback` 테이블 + `upsertFeedback`/`getFeedbackStats`/`getFalsePositivePatterns` + Pending UI 👍/👎 버튼 → `markFinding` IPC.

10. **Slack/Discord/Webhook 알림** ⬜
    - `osNotify` 외 외부 채널 전파. pending 리뷰 대기 알림.

11. **리뷰 히스토리 검색/필터** ✅
    - ✅ 구현 완료: DB 기반 `getHistory(filters)` + Monitoring repo/severity 필터 + `useReviewHistory` 훅(debounce). in-memory history를 DB 기반으로 보완

12. **정기 리포트 / 다이제스트** ⬜ — 일일/주간 이메일 또는 인앱 요약.

13. **Quiet Hours / 스케줄 일시정지** ⬜ — 폴링은 계속, 알림/리뷰 게시 야간/주말 억제.

14. **동시성 제어 (병렬 리뷰)** ✅ — `processQueue` 직렬 → bounded lazy p-limit(N) 워커풀(`maxConcurrentReviews`, 기본 1=직렬 동일). claimNext atomic 유지 + 전용 try/catch(P2 claim-error clean-exit), reviewQueueItem try/catch 워커 내부 이동(에러 격리), `budget_concurrency_soft_limit` 경고. 예산 게이트는 ≤N review soft cap. AC3.1/3.2/3.3/3.4/3.9 테스트 통과.

### 🟩 P3 — 인증 / 보안 / 컴플라이언스

16. **감사 로그 (Audit Log)** ⬜ — 누가 언제 approve/reject했는지, 설정 변경 이력.

17. **크리덴셜 순환 리마인더** ⬜ — PAT 만료 임박 알림 (GitHub API로 만료일 조회).

18. **GitHub Webhooks 지원 (폴링 보조)** ⬜ — 실시간 트리거. 퍼블릭 엔드포인트 필요 → optional 사이드카.

### 🟦 P4 — 사용자 경험 / UI

19. **Light 테마 (토큰 스왑)** ⬜ — DESIGN.md §13 "future token-swap". `tokens.css` 구조가 이미 준비됨.

20. **다국어 UI (i18n)** ⬜ — 힌트만 한국어, 크롬은 영어 고정(D3). 언어 토글로 UI 전체 번역.

21. **백업/내보내기/가져오기** ⬜ — DB와 설정 내보내기. 기기 이전 대비.

22. **상태 점검 / 자가 진단 (Health Check)** ⬜ — PAT 권한, LLM 연결, DB 무결성, 디스크 용량 통합 점검.

23. **GitHub Status Checks 통합** ⬜ — PR의 CI 통과/실패를 리뷰 컨텍스트에 반영.

### 🟪 P5 — 고급 / 차별화

24. **코드 커버리지 인식** ⬜ — 코드 추가 시 테스트 없으면 경고. `*.test.*` 휴리스틱 또는 coverage 리포트 파싱.

25. **시크릿 스캐닝 / 의존성 취약점** ⬜ — diff 내 하드코딩 시크릿, `package.json`/`Cargo.toml` 변경 시 취약점 DB 조회.

26. **코드 오너 인식 라우팅** ⬜ — `CODEOWNERS` 파싱 → 담당자 컨텍스트 프롬프트 주입.

27. **브랜치 보호 규칙 제안** ⬜ — 리뷰 품질 데이터 기반 제안.

28. **다중 GitHub 계정 / 다중 LLM 프로필** ⬜ — 개인/회사 전환, 모델별 프로필.

29. **팀 규칙 템플릿 / 프리셋 공유** ⬜ — 검증된 `reviewRules` 프리셋 공유/임포트.

---

## 💡 추천 다음 스프린트

**1차 스프린트(배포 도달도) 완료**: 비용/예산 · 크로스플랫폼 · 자동업데이트 (diff 임계값, 파일 필터는 사전 구현 상태였음).

**2차 스프린트 (리뷰 품질) ✅ 완료**: #4 Bot PR 정책 · #5 증분 리뷰 · #6 리뷰 영역 토글
- #4(Bot): `shouldSkipBotAuthor` Phase 0 매칭 + `botAuthors`/`botPolicy` config → poller → UI. 9개 테스트.
- #5(증분 리뷰): `getPreviousSha` + `fetchCompareDiff`(compareCommits) → orchestrator narrowing → diverged 시 full fallback. 4개 테스트.
- #6(영역 토글): `buildAreasSection` 부분집합 + `reviewAreas` config → llm-client → UI 체크박스. 5개 테스트.

**3차 스프린트 (관측성) ✅ 완료**: #8 통계 대시보드 · #9 FP 피드백 루프 · #11 히스토리 검색/필터
- migration v7 (`review_history` + `finding_feedback`) → data layer → IPC (3 events, 3 commands) → orchestrator 통합 → hooks (useReviewHistory, useStats) → UI (Monitoring 필터/차트, Pending 피드백)
- 386/386 테스트 통과, tsc clean. 7명 executor 병렬 구현.
- #7(대화형 리뷰)은 4차 스프린트에서 구현 완료 — 아래 4차 스프린트 요약 참조.

> 🟡 보류 2건(#2 서명활성화, #3 CI검증)은 사용자 액션만 남은 상태 — 다음 스프린트와 병행 가능.

**4차 스프린트 (리뷰 상호작용 + 동시성) ✅ 완료**: #7 대화형 리뷰 · #14 동시성 제어 (+ GitHub 인증 #1/#15 로드맵에서 영구 제거)
- #7(대화형 리뷰): `partitionByExisting` + `ExistingComment` id/review_id 확장 → `publishReview` auto 모드에서 `createReplyForReviewComment`로 기존 스레드 응답(dedupe drop → reply), best-effort 실패, `replyToThreads`(기본 false=현재 동작). AC2.1-2.5 + partition 테스트.
- #14(동시성): `processQueue` 직렬 → bounded lazy p-limit(N) 워커풀(`maxConcurrentReviews`, 기본 1=직렬 동일); claimNext atomic 유지 + P2 claim-error clean-exit + 에러 격리 + `budget_concurrency_soft_limit` 경고. 예산 게이트는 ≤N review soft cap. AC3.1/3.2/3.3/3.4/3.9.
- 411/411 테스트 통과, tsc clean. ralplan 합의(2패스) → config→daemon→shared→UI 전 레이어 구현.
- ⚠️ `maxConcurrentReviews>1` + 월 예산 설정 시 예산은 pause-on-exceed soft cap으로 ≤N review까지 초과 가능(기본 N=1이면 추가 초과 없음).
