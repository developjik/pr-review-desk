// build-sidecar.mjs — wraps @yao-pkg/pkg to target the requested platform.
//
// Usage:
//   SIDECAR_TARGET=arm64 npm run build:sidecar   (arm64 is the default when unset;
//                                                  an empty string is rejected fail-loud)
//   SIDECAR_TARGET=x64   npm run build:sidecar
//   SIDECAR_TARGET=linux npm run build:sidecar
//   SIDECAR_TARGET=win   npm run build:sidecar
//
// `@yao-pkg/pkg` downloads prebuilt Node binaries, so the cross targets (x64,
// linux, win) work from any host OS — no cross-compiler needed.
//
// The `build:sidecar` npm script first runs `npm run build:bundle`, which
// produces `dist/main.cjs`. This wrapper then pkg's that bundle into
// `../src-tauri/binaries/pr-review-daemon-<triple>`.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";

const TARGETS = {
  arm64: { pkg: "node22-macos-arm64", triple: "aarch64-apple-darwin" },
  x64: { pkg: "node22-macos-x64", triple: "x86_64-apple-darwin" },
  linux: { pkg: "node22-linux-x64", triple: "x86_64-unknown-linux-gnu" },
  win: { pkg: "node22-win-x64", triple: "x86_64-pc-windows-msvc" },
};

const arch = process.env.SIDECAR_TARGET ?? "arm64";
const t = TARGETS[arch];
if (!t) {
  console.error(`build-sidecar: unknown SIDECAR_TARGET="${arch}". Valid values: arm64 (default), x64, linux, win.`);
  process.exit(2);
}

const bundle = "dist/main.cjs";
if (!existsSync(bundle)) {
  console.error(`build-sidecar: bundle "${bundle}" not found. Run \`npm run build:bundle\` first.`);
  process.exit(1);
}

const out = `../src-tauri/binaries/pr-review-daemon-${t.triple}`;
console.error(`build-sidecar: arch=${arch} pkg=${t.pkg} -> ${out}`);

const result = spawnSync(
  "pkg",
  [bundle, "--target", t.pkg, "--output", out, "--compress", "GZip"],
  { stdio: "inherit", shell: process.platform === "win32" },
);
process.exit(result.status ?? 1);
