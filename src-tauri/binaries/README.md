# Sidecar binaries

`tauri.conf.json` declares a sidecar via `bundle.externalBin`:

```json
"externalBin": ["binaries/pr-review-daemon"]
```

Tauri resolves the binary by appending the **Rust target triple** to the name,
so it looks for `pr-review-daemon-<target-triple>`. Tauri's build step
validates that this file exists during codegen, so the build fails if it is
missing.

## Current state

| File (base + target triple) | Platform | Local | CI |
| --- | --- | --- | --- |
| `pr-review-daemon-aarch64-apple-darwin` | macOS (Apple Silicon) | **Real** — `npm run build:sidecar` (`SIDECAR_TARGET=arm64`) | Real (macos-14) |
| `pr-review-daemon-x86_64-apple-darwin` | macOS (Intel) | **Real** — `node scripts/build-release.mjs` (dual-arch) | Real (macos-13) |
| `pr-review-daemon-x86_64-unknown-linux-gnu` | Linux (x86_64) | Stub | **Real** — CI (`SIDECAR_TARGET=linux`, ubuntu-22.04) |
| `pr-review-daemon-x86_64-pc-windows-msvc.exe` | Windows (x86_64) | Stub | **Real** — CI (`SIDECAR_TARGET=win`, windows-latest) |

All four targets are compiled by [`@yao-pkg/pkg`](https://github.com/yao-pkg/pkg)
(see `daemon/build-sidecar.mjs`). Because pkg downloads prebuilt Node binaries,
the Linux and Windows cross targets build on any host — no cross-compiler
needed.

The non-native **stubs** (a 269-byte `#!/bin/sh` / `.bat` no-op) exist so that
`cargo build` and `tauri dev` succeed on a developer machine: Tauri validates
that every `externalBin` entry exists at codegen time, so a file must be
present even before a real cross build runs. CI overwrites them with a genuine
binary (see `.github/workflows/release.yml`); the
`scripts/sidecar-selfcheck.mjs` guard fails the CI build if a stub is still in
place.