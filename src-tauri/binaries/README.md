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

| File (base + target triple) | Platform | Status |
| --- | --- | --- |
| `pr-review-daemon-aarch64-apple-darwin` | macOS (Apple Silicon) | **Real** — compiled by `npm run build:sidecar` (gitignored, regenerated locally) |
| `pr-review-daemon-x86_64-apple-darwin` | macOS (Intel) | Stub placeholder |
| `pr-review-daemon-x86_64-unknown-linux-gnu` | Linux (x86_64) | Stub placeholder |
| `pr-review-daemon-x86_64-pc-windows-msvc.exe` | Windows (x86_64) | Stub placeholder |

The real binary is produced by [`@yao-pkg/pkg`](https://github.com/yao-pkg/pkg)
targeting `node22-macos-arm64`; see `daemon/package.json` → `build:sidecar`.
The non-native stubs remain so `cargo build` / `tauri dev` succeed until
cross-compilation is wired up.
