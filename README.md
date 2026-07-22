<div align="center">

# PR Review

**로컬에서 도는 AI 코드 리뷰어 — PR을 폴링하고, LLM으로 회의하고, GitHub에 인라인 코멘트를 단다.**

A local, menu-bar AI code reviewer. It watches the repos you're requested on,
runs every PR through an LLM, and posts precise line-level review comments back
to GitHub — all from your machine, never a server.

[Features](#-features) · [Install](#-install) · [Quick start](#-quick-start) · [Architecture](#-architecture) · [Configuration](#️-configuration)

</div>

---

## ✨ Features

**리뷰 파이프라인**
- 🔄 **자동 폴링** — `review-requested` PR을 주기적으로 발견 (병합/클로즈 자동 정리)
- 🧠 **정밀 리뷰** — 4개 영역(bug · style · structure · security), 심각도(high/med/low), 구체적인 수정 제안(suggestion 블록)
- 🌐 **다국어 코멘트** — ko/ja/zh/en 자동 감지, 설정 언어로 리뷰
- 📐 **대형 PR 처리** — diff를 500라인 청크로 분할(토큰 예산 준수), 파일 우선순위 트리밍, 사용자 설정 임계값
- 🎯 **정확한 라인 매핑** — LineMap이 LLM 코멘트를 실제 diff 라인에 핀

**신뢰성**
- 🔁 **dedupe + 재시도** — (prId, headSha) 중복 방지, 지수 백오프 큐 재시도, rate-limit 자동 복구, orphan reclaim
- ✅ **정확성 최우선** — 프롬프트가 "확신 없는 이슈는 보고하지 마라, 절대 날조하지 마라"를 강제

**리뷰 모드**
- ⚡ `auto` — 리뷰 완료 즉시 GitHub에 게시
- ⏸️ `pending` — 승인 대기: 편집 · 선택적 게시 · 거부 지원 (사람이 최종 승인)

**필터링 & 가이드라인**
- 🗂️ 리포 glob 포함/제외 + trigger/skip 라벨 + **파일 단위 glob 필터**(`src/**` 포함, `**/*.generated.ts` 제외)
- 📝 글로벌 `reviewRules` + 리포별 `.prreview/rules.md` 병합 (토큰 예산 내 트렁케이션)

**비용 제어**
- 💲 **모델별 토큰 가격 + 월 예산** — `review-usage` 테이블이 per-file 토큰을 추적(재시도 중복 카운트 방지), 모델별 비용 환산, 예산 초과 시 자동 pause + UI 경고

**호스트 & UI**
- 🖥️ 트레이 아이콘 상태 색 · OS 알림 · 로그인 시 자동실행 · 단일 인스턴스 · OS 키체인 비밀 저장
- ⌨️ 명령 팔레트(⌘K) · 키보드 단축키 · 토스트 · Wizard/Settings/Monitoring/Logs/Pending 탭
- 🔒 비밀(PAT, LLM key)은 디스크가 아닌 OS 키체인에 저장 (Linux 비밀서비스 부재 시 경고와 함께 안전 폴백)

**플랫폼 & 업데이트**
- 🍎 macOS (Apple Silicon + Intel) · 🐧 Linux (AppImage) · 🪟 Windows (MSI) — CI 매트릭스로 4타겟 네이티브 빌드
- 🔄 인앱 자동 업데이트(tauri-plugin-updater, 서명 검증)

---

## 📦 Install

> 서명되지 않은(unsigned) 앱입니다. macOS는 Gatekeeper, Windows는 SmartScreen이 첫 실행을 차단할 수 있습니다 — 아래 방법으로 우회하세요.

### macOS

**터미널 한 줄 설치 (권장)** — 아키텍처 자동 감지 후 quarantine 제거 + `/Applications` 설치:

```bash
curl -fsSL https://example.com/pr-review/install.sh | bash
```

**DMG 수동 설치** — 릴리스 페이지에서 아키텍처에 맞는 `.dmg` 다운로드 (Apple Silicon → `*_aarch64.dmg`, Intel → `*_x64.dmg`), Applications로 드래그. 첫 실행 우클릭 → 열기. 차단 시:

```bash
xattr -dr com.apple.quarantine "/Applications/PR Review.app"
```

### Linux / Windows

CI(`.github/workflows/release.yml`)가 매 `v*` 태그마다 네이티브 인스톨러를 생성합니다. 첫 태그 릴리스 후 [Releases](../../releases) 페이지에 나타납니다.

**Linux** — `.AppImage` 다운로드 후:
```bash
chmod +x "PR Review_0.1.0_amd64.AppImage"
"./PR Review_0.1.0_amd64.AppImage"
```
WebKitGTK 시스템 라이브러리 필요 (Debian/Ubuntu):
```bash
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev patchelf
```

**Windows** — `.msi` 인스톨러 실행. 서명되지 않아 SmartScreen 경고 → **More info → Run anyway**.

---

## 🚀 Quick start

1. 앱 실행 → **Wizard** 탭에서 GitHub username + PAT(`repo`/review 스코프) + LLM endpoint/key/model 입력.
2. 저장하면 폴링 시작. 트레이 아이콘이 활성 상태로 전환.
3. 리뷰 대기 PR이 발견되면 자동 리뷰 → Settings에서 `auto`/`pending` 모드 선택.
4. (선택) Settings → **Cost & Budget** 에서 월 예산 + 모델별 가격 설정 → 예산 초과 자동 pause.

> 어떤 LLM provider든 OpenAI 호환 `/v1/chat/completions` 엔드포인트면 됩니다 (OpenAI, GLM, 로컬 프록시 등).

---

## 🏗 Architecture

```
┌──────────────┐   Tauri IPC (events)   ┌──────────────┐
│  React UI    │ ◄─────────────────────► │  Tauri/Rust  │
│  (webview)   │                         │   host shell │
└──────────────┘                         └──────┬───────┘
                                                │ spawn + supervise
                                         ┌──────▼───────┐
                                         │   Daemon     │  (pkg binary)
                                         └──┬────────┬──┘
                                  node:sqlite │        │ HTTPS
                                   ┌──────────▼┐  ┌────▼─────────┐
                                   │ reviews.db│  │ GitHub + LLM │
                                   └───────────┘  └──────────────┘
```

네 부분:

- **Frontend** (`src/`) — React 19 + Vite UI. 탭 셸: Wizard · Settings · Monitoring · Logs · Pending. 명령 팔레트(⌘K).
- **Tauri backend** (`src-tauri/`) — Rust 호스트. 웹뷰 호스팅 + 데몬 사이드카 생명주기 관리(spawn / backoff 재시작 / 종료) + 데몬 stdout 이벤트를 프론트로 브릿지 + config 영속화 + 트레이 아이콘 + 키체인 + 자동업데이트.
- **Daemon** (`daemon/`) — Node.js 사이드car, `@yao-pkg/pkg`로 단일 바이너리 컴파일. `node:sqlite` DB 소유, 실제 리뷰 작업 수행: **poll GitHub → PR 컨텍스트 fetch → diff 청킹 → LLM 리뷰 → 라인 매핑 → 게시(dedupe + retry)**.
- **Shared** (`shared/`) — 프론트와 데몬이 JSON-line stdio 프로토콜로 공유하는 TypeScript IPC 계약 타입.

**IPC 프로토콜** — 데몬은 stdin/stdout으로 newline-delimited JSON. 명령은 host→daemon(`config`, `poll:now`, `pause`, `resume`, `shutdown`, `get_usage`), 이벤트는 daemon→host(`daemon:ready`, `daemon:status`, `review:file`, `usage:summary`, `budget:exceeded`, …). 핸드셰이크에서 프로토콜 버전 협상(`proto: 1`). 전체 계약은 `shared/src/ipc-contract.ts`.

**리뷰 파이프라인** — Poll → Discover(필터: 리포 glob + 라벨) → Review(파일 glob 필터 → diff-size 게이트 → 파일 예산 트림 → 500라인 청킹 → 토큰 예산) → LineMap(인라인/디그레이드 분류) → Publish(트림 재시도 + dedupe).

---

## ⚙️ Configuration

Wizard가 JSON config를 작성하고, Tauri 호스트가 영속화(`config_store`) 후 데몬 (재)시작마다 전달합니다. 전체 필드:

| Field | Default | Description |
| --- | --- | --- |
| `githubUsername` | `""` | review-requested PR을 폴링할 GitHub 사용자 |
| `githubPat` | — | GitHub PAT (`repo`/review 스코프) |
| `llmBaseUrl` | — | LLM API base URL (OpenAI 호환) |
| `llmApiKey` | — | LLM API key |
| `llmModel` | — | 모델 id (예: `gpt-4o`, `glm-4.6`) |
| `llmJsonMode` | `true` | LLM JSON 응답 모드 사용 |
| `pollIntervalMin` | `15` | 폴링 주기(분) |
| `reviewMode` | `auto` | `auto` (즉시 게시) \| `pending` (승인 대기) |
| `reviewRules` | `""` | 글로벌 리뷰 가이드라인 (리포 `.prreview/rules.md`와 병합) |
| `showSeverity` | `true` | 심각도 라벨 표시 |
| `osNotify` | `false` | 리뷰 완료 OS 알림 |
| `repoInclude` / `repoExclude` | `""` | 리포 glob 포함/제외 (예: `org/*`) |
| `triggerLabels` / `skipLabels` | `""` | 리뷰 트리거/스킵 라벨 |
| `fileInclude` / `fileExclude` | `""` | 파일 glob 포함/제외 (예: `src/**`, `**/*.generated.ts`) |
| `maxDiffLines` | `5000` | 파일당 diff 라인 하드컷 |
| `maxFiles` | `50` | 리뷰 가능 파일 수 예산 |
| `largePrPolicy` | `trim` | 예산 초과 시 `trim`(저우선순위 드롭) \| `abort`(전체 스킵) |
| `llmPricing` | `""` | 모델별 가격, newline `model:promptPer1M,completionPer1M` |
| `defaultPer1M` | `0` | 미지정 모델 blended $/1M 토큰 |
| `monthlyBudgetUsd` | `0` | 월 LLM 지출 한계 (0=무제한, 초과 시 pause) |
| `dbPath` | — | `node:sqlite` reviews DB 경로 |
| `logDir` | — | 회전 데몬 로그 디렉토리 |

> **핫 리로드** — config 변경 시 런타임에 영향 주는 필드(pollInterval, githubUsername, PAT, llm 모델/endpoint/key, **monthlyBudgetUsd**)만 orchestrator 재스케줄을 트리거합니다. 가격 표시 필드(llmPricing, defaultPer1M)는 표시 전용이라 재스케줄하지 않습니다.

---

## 🔧 Building

### Sidecar daemon

esbuild로 단일 CJS 번들 → `@yao-pkg/pkg`로 단일 바이너리:

```bash
npm run build:sidecar
# → daemon/dist/main.cjs (esbuild)
# → src-tauri/binaries/pr-review-daemon-<triple> (pkg)
```

4 플랫폼을 `SIDECAR_TARGET`(`arm64` \| `x64` \| `linux` \| `win`, 기본 `arm64`)로 선택. CI는 매트릭스로 4타겟 전부 빌드. `daemon/build-sidecar.mjs` 참조.

### Full app

```bash
npm run tauri build     # ad-hoc 서명 .app + .dmg (macOS)
```

`tauri build`가 `beforeBuildCommand`(→ prebuild → build:sidecar)로 사이드카를 먼저 재생성. 출력:

| Output | Path | Gitignored |
| --- | --- | --- |
| Frontend dist | `dist/` | ✅ |
| Daemon bundle | `daemon/dist/` | ✅ |
| Compiled sidecar | `src-tauri/binaries/pr-review-daemon-*` | ✅ |
| Rust target / bundles | `src-tauri/target/` | ✅ |

---

## 🔄 Auto-update (one-time setup)

인앱 자동 업데이트(tauri-plugin-updater)는 서명 키페어가 필요합니다. 설정 전까지 릴리스 CI는 unsigned 인스톨러만 게시합니다(`latest.json` 없음).

1. **키페어 생성:**
   ```bash
   npx @tauri-apps/cli signer generate -w ~/.tauri/pr-review.updater.key
   ```
2. **공개키**를 `src-tauri/tauri.conf.json` → `plugins.updater.pubkey`에 임베드(PLACEHOLDER 교체).
3. **repo secret/variable** 설정:
   - `TAURI_SIGNING_PRIVATE_KEY` — private key 내용 (secret)
   - `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — 생성 시 비밀번호 (secret)
   - `ENABLE_UPDATES` — `true` (variable, latest.json 게시 잡 활성화)
4. `git tag vX.Y.Z && git push --tags` → release 워크플로가 4플랫폼 빌드+서명, `latest.json` 조립(`scripts/build-update-manifest.mjs`), GitHub Release 게시.

> private key는 절대 커밋 금지. 유출 시 재생성 + pubkey 교체 + 버전업(구 서명 무효화).

---

## 🍎 Developer ID 서명 & 공증 (배포용)

기본 `tauri build`는 ad-hoc 서명 — 빌드 머신에서만 실행되고 타 Mac에선 Gatekeeper 차단. 배포하려면:

```bash
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_PASSWORD="app-specific-password"   # 또는 App Store Connect API key
export APPLE_TEAM_ID="TEAMID"
npm run tauri build
```

Tauri가 이 env를 읽어 서명 + 공증 + 스테이플 자동 수행. 검증:
```bash
spctl -a -vv -t exec "PR Review.app"   # "accepted"
xcrun stapler validate "PR Review.app"
```

> 유효한 Developer ID 인증서와 Apple 자격증명이 배포에 **필요**; 이 repo 빌드 스크립트는 기본적으로 ad-hoc 서명만 수행합니다.

---

## 🧰 Development

```bash
npm install          # workspace 의존성 전체 설치
npm run tauri dev    # 데스크톱 윈도우에서 풀 앱 실행
npm run typecheck    # frontend + shared + daemon 타입체크
npm run test         # vitest (332 tests)
npm run lint         # ESLint
npm run format       # Prettier
```

**필수:** Node.js v22+ (`node:sqlite` + `node22` pkg 타겟), Rust stable, [Tauri 2 시스템 의존성](https://tauri.app/start/prerequisites/).

**데몬 단독 실행** — Tauri 없이 stdin으로 JSON 명령을 파이프:
```bash
node daemon-test.mjs                                        # tsx 기반
PR_DAEMON_BIN=src-tauri/binaries/pr-review-daemon-aarch64-apple-darwin node daemon-test.mjs  # 컴파일된 바이너리
```

### Workspace layout

npm workspace 루트. `daemon`과 `shared`는 심링크로 해상되는 워크스페이스 패키지.

```
pr-review/
├── package.json          # workspace root
├── src/                  # React frontend
├── src-tauri/            # Tauri 2 Rust backend (+ binaries/, tauri.conf.json)
├── daemon/               # sidecar daemon (poller/reviewer/publisher/orchestrator/db/ipc)
├── shared/               # IPC contract types
├── scripts/              # build-release, sidecar-selfcheck, build-update-manifest, install
└── .github/workflows/    # release CI (4-platform matrix)
```

### IDE

[VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer).

---

## 📋 Roadmap

진행 중인 기능과 우선순위는 [`FEATURE_ROADMAP.md`](./FEATURE_ROADMAP.md)를 참조.

---

<div align="center">

**Tauri 2 · React 19 · TypeScript · Rust · Node.js 22**

로컬에서 도는, 서버 없는, 프라이빗한 AI 코드 리뷰.

</div>
