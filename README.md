# PR Review

A Tauri 2 + React + TypeScript desktop application for automated, line-level pull
request review. It watches the repositories you're requested on as a reviewer,
fetches open PRs on a schedule, runs each through an LLM, and posts inline
review comments back to GitHub — all from a local menu-bar app.

The app is composed of four parts:

- **Frontend** (`src/`) — React UI (Vite) with a tab-based shell:
  - **Wizard** — initial project configuration
  - **Settings** — application preferences
  - **Monitoring** — live review activity
  - **Logs** — daemon and review logs
- **Tauri backend** (`src-tauri/`) — Rust shell that hosts the webview and
  spawns the review daemon as an external sidecar binary
  (`bundle.externalBin` → `binaries/pr-review-daemon`). It supervises the
  daemon lifecycle (spawn / restart-with-backoff / shutdown), bridges daemon
  stdout events to the frontend, persists config, and owns the tray icon.
- **Daemon** (`daemon/`) — Node.js sidecar, compiled to a standalone binary
  with [`@yao-pkg/pkg`](https://github.com/yao-pkg/pkg). It owns the
  `node:sqlite` database and performs the actual review work (poll GitHub →
  fetch PR context → chunk diff → LLM review → map findings to diff lines →
  publish review comments with dedupe + retry).
- **Shared** (`shared/`) — TypeScript IPC contract types shared between the
  frontend and daemon over a JSON-line stdio protocol.

## 설치 (macOS)

> 이 앱은 서명되지 않은(unsigned) 앱입니다. macOS Gatekeeper가 처음 실행을 차단할 수 있으며 아래 방법으로 우회하세요.
>
> _PR Review is distributed as an unsigned app; macOS Gatekeeper blocks the first launch — use one of the paths below._

### 방법 A — 터미널 한 줄 설치 (권장)

아래 명령은 CPU 아키텍처를 자동으로 감지해 매칭되는 바이너리를 다운로드하고, quarantine 플래그를 제거한 뒤 `/Applications`에 설치합니다.

```bash
curl -fsSL https://example.com/pr-review/install.sh | bash
```

### 방법 B — DMG 다운로드 후 수동 설치

1. 릴리스 페이지에서 아키텍처에 맞는 `.dmg`를 다운로드합니다 (Apple Silicon → `*_aarch64.dmg`, Intel → `*_x64.dmg`).
2. DMG를 열고 `PR Review.app`를 응용프로그램(Applications)으로 드래그합니다.
3. 첫 실행 시 앱을 우클릭 → 열기(Open) → 확인 (서명되지 않은 앱의 일회성 우회).
4. 그래도 차단되면 터미널에서 아래 명령을 실행하세요.

```bash
xattr -dr com.apple.quarantine "/Applications/PR Review.app"
```

## Architecture

```
┌──────────────┐   Tauri IPC (events)   ┌──────────────┐
│  React UI    │ ◄─────────────────────► │  Tauri/Rust  │
│  (webview)   │                         │   host shell │ │
└──────────────┘                         └──────┬───────┘ │
                                                │ spawn +  │
                                                │ supervise│
                                         ┌──────▼───────┐ │
                                         │   Daemon     │ │
                                         │ (pkg binary) │ │
                                         └──┬────────┬──┘ │
                                  node:sqlite │        │ HTTPS
                                   ┌──────────▼┐  ┌────▼─────────┐
                                   │ reviews.db│  │ GitHub + LLM │
                                   └───────────┘  └──────────────┘
```

**IPC protocol** — The daemon speaks a newline-delimited JSON protocol over
stdin/stdout. Commands flow host→daemon (`config`, `poll:now`, `pause`,
`resume`, `shutdown`); events flow daemon→host (`daemon:ready`,
`daemon:status`, `poll:started`, `daemon:error`, `daemon:log`, …). The
protocol version is negotiated at handshake (`proto: 1`). See
`shared/src/ipc-contract.ts` for the full contract.

**Dev vs release sidecar resolution** — In `tauri dev` the Rust host runs the
daemon via `node tsx daemon/src/main.ts` (or `PR_DAEMON_BIN`). In a release
build the daemon is a pre-compiled `@yao-pkg/pkg` binary placed next to the
main executable (e.g. `Contents/MacOS/pr-review-daemon` on macOS).

## Prerequisites

- Node.js v22.23.1+ (npm 10.9.8+) — required for `node:sqlite` and the
  `node22` pkg target
- Rust 1.88.0 (stable)
- Tauri 2 system dependencies — see the
  [Tauri prerequisites](https://tauri.app/start/prerequisites/)

## Workspace layout

This repository is an npm workspace root. `daemon` and `shared` are workspace
packages resolved via symlinks.

```
pr-review/
├── package.json          # workspace root
├── tsconfig.base.json    # shared strict TS config
├── tsconfig.json         # frontend (extends base)
├── vite.config.ts
├── index.html
├── src/                  # React frontend
├── src-tauri/            # Tauri 2 Rust backend
│   ├── binaries/         # sidecar binaries (real arm64 build + cross-platform stubs)
│   └── tauri.conf.json
├── daemon/               # sidecar daemon
│   ├── src/              # poller / reviewer / publisher / orchestrator / db / ipc
│   ├── build/            # esbuild inject shims (import.meta.url for CJS)
│   └── package.json      # build:bundle + build:sidecar scripts
├── shared/               # IPC contract types
└── spikes/               # exploratory spikes (not part of the app)
```

## Getting started

```bash
npm install          # install all workspace dependencies
npm run dev          # start the Vite dev server (frontend only)
npm run tauri dev    # run the full Tauri app in a desktop window
npm run typecheck    # type-check frontend + shared + daemon
npm run lint         # run ESLint
npm run format       # run Prettier
```

## Building

### Sidecar daemon

The daemon is bundled with **esbuild** (resolves workspace + TS imports into a
single CJS file) and then packaged into a standalone Node binary with
**@yao-pkg/pkg**:

```bash
npm run build:sidecar    # root convenience script
# equivalent to:
#   cd daemon && npm run build:sidecar
#     -> esbuild bundle (dist/main.cjs)
#     -> pkg compile (../src-tauri/binaries/pr-review-daemon-aarch64-apple-darwin)
```

The build currently targets `node22-macos-arm64`. Cross-platform targets
(Intel macOS, Linux, Windows) remain committed placeholder stubs under
`src-tauri/binaries/` until cross-compilation is wired up.

> The esbuild step injects a small `import.meta.url` shim
> (`daemon/build/import-meta-url-shim.js`) because the CJS bundle otherwise
> leaves `import.meta.url` undefined, which breaks `node-cron`'s background
> task module at require time.

### Full app

```bash
npm run tauri build     # produces a signed-adhoc .app and .dmg
```

`tauri build` runs `npm run build` as its `beforeBuildCommand`, which itself
runs `prebuild` → `build:sidecar` first, so the sidecar binary is always
regenerated before bundling. The output lands in:

```
src-tauri/target/release/bundle/macos/PR Review.app
src-tauri/target/release/bundle/dmg/PR Review_0.1.0_aarch64.dmg
```

### Build output locations

| Output | Path | Gitignored |
| --- | --- | --- |
| Frontend dist | `dist/` | yes |
| Daemon bundle | `daemon/dist/` | yes |
| Compiled sidecar | `src-tauri/binaries/pr-review-daemon-aarch64-apple-darwin` | yes |
| Rust target / bundles | `src-tauri/target/` | yes |

## Configuration

The wizard writes a JSON config that is persisted by the Tauri host
(`config_store`) and re-delivered to the daemon whenever it (re)starts. Key
fields:

| Field | Description |
| --- | --- |
| `githubUsername` | GitHub user whose review-requested PRs are polled |
| `githubPat` | GitHub personal access token (needs `repo` / review scopes) |
| `llmBaseUrl` | LLM API base URL (e.g. `https://api.openai.com/v1`, or a local proxy) |
| `llmApiKey` | LLM API key |
| `llmModel` | Model id (e.g. `gpt-4o`) |
| `dbPath` | Path to the `node:sqlite` reviews database |
| `logDir` | Directory for rotating daemon logs |

## Running the daemon standalone

The daemon runs without Tauri — drive it by piping JSON commands to stdin. The
handy `daemon-test.mjs` driver at the repo root exercises the full
ready → config → poll → shutdown sequence:

```bash
node daemon-test.mjs
```

To point it at the compiled binary instead of `tsx`, set `PR_DAEMON_BIN`:

```bash
PR_DAEMON_BIN=src-tauri/binaries/pr-review-daemon-aarch64-apple-darwin ...
```

## Developer ID code signing & notarization

The default `tauri build` produces an **ad-hoc signed** app — it runs on the
build machine but Gatekeeper will block it on other Macs. To distribute:

1. **Enroll** in the Apple Developer Program and obtain a **Developer ID
   Application** certificate (`Developer ID Application: Your Name (TEAMID)`).
2. Create an **App Store Connect API key** (`.p8`) for notarytool, or an app
   password.
3. Export the signing environment and build:

   ```bash
   export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
   export APPLE_ID="you@example.com"
   export APPLE_PASSWORD="app-specific-password"   # or use API keys
   export APPLE_TEAM_ID="TEAMID"
   npm run tauri build
   ```

   Tauri reads these env vars and signs + notarizes + staples automatically.

4. Verify the notarized app:

   ```bash
   spctl -a -vv -t exec "PR Review.app"   # should say "accepted"
   xcrun stapler validate "PR Review.app"
   ```

> A valid Developer ID certificate and Apple credentials are **required** for
> distribution; the build scripts in this repo only perform ad-hoc signing by
> default.

## IDE setup

- [VS Code](https://code.visualstudio.com/) +
  [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) +
  [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
