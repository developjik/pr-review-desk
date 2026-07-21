// build-release.mjs — dual-arch macOS release orchestrator (LOCAL only).
//
// Purpose:
//   Build PR Review for BOTH macOS arches (arm64 native + x64 cross-compiled),
//   producing 2 DMGs (Tauri bundles them) + 2 tar.gz (this script packs the .app
//   directly). LOCAL release prep only: NO code signing, NO Git commit. Run from
//   repo root:  node scripts/build-release.mjs
//
// One-time prereq (for the x64 cross-compile):
//   rustup target add x86_64-apple-darwin
//
// How the arch reaches the sidecar (SIDECAR_TARGET / prebuild propagation):
//   `npm run tauri build`  →  beforeBuildCommand `npm run build`
//                            →  prebuild hook `npm run build:sidecar`
//                            →  daemon/build-sidecar.mjs reads SIDECAR_TARGET and
//                               writes ../src-tauri/binaries/pr-review-daemon-<triple>.
//   So setting SIDECAR_TARGET on this script's `npm` invocation propagates all
//   the way down to build-sidecar.mjs, which picks the matching pkg node binary.
//
// Arch guard (the load-bearing correctness check):
//   Tauri strips the `-<triple>` suffix from the sidecar at bundle time, so the
//   bundled daemon is a bare `Contents/MacOS/pr-review-daemon`. We `file` it and
//   ASSERT the expected Mach-O arch token is present AND it is NOT reported as a
//   "script" — the latter catches the 269-byte `#!/bin/sh` placeholder stub that
//   ships in src-tauri/binaries/ before a real build runs. The guard runs right
//   after confirming the .app bundle exists and BEFORE the tar step, so a guard
//   failure leaves zero tainted release/ output (Architect P3 recommendation).
//
// Predicted output paths (confirm the x64 DMG suffix on first build — `_x64` is
// Tauri's naming convention, not Apple's `x86_64`):
//   release/pr-review-arm64.tar.gz
//   release/pr-review-x64.tar.gz
//   src-tauri/target/release/bundle/dmg/PR Review_0.1.0_aarch64.dmg
//   src-tauri/target/x86_64-apple-darwin/release/bundle/dmg/PR Review_0.1.0_x64.dmg

import { spawnSync } from "node:child_process";
import { mkdirSync, rmSync, existsSync, readdirSync } from "node:fs";
import path from "node:path";

const ARCHES = [
  { arch: "arm64", triple: "aarch64-apple-darwin", tauriTarget: null },
  { arch: "x64", triple: "x86_64-apple-darwin", tauriTarget: "x86_64-apple-darwin" },
];


const APP_NAME = "PR Review.app";
const repoRoot = process.cwd();
mkdirSync(path.join(repoRoot, "release"), { recursive: true });

function run(file, args, env) {
  // Tauri CLI rejects CI=1 as an invalid --ci value; omit CI from the child env.
  const { CI: _omit, ...baseEnv } = process.env;
  const result = spawnSync(file, args, {
    stdio: "inherit",
    env: { ...baseEnv, ...env },
  });
  if (result.status !== 0) {
    console.error(
      `build-release: command failed (status ${result.status ?? 1}): ${file} ${args.join(" ")}`,
    );
    process.exit(result.status ?? 1);
  }
}

const artifacts = [];

for (const { arch, tauriTarget } of ARCHES) {
  // 1. Build: `npm run tauri build [-- --target <triple>]` with the arch on env.
  const tauriArgs = ["run", "tauri", "build"];
  if (tauriTarget) {
    tauriArgs.push("--", "--target", tauriTarget);
  }
  console.error(`\nbuild-release: === building ${arch} (target ${tauriTarget ?? "host"}) ===`);
  run("npm", tauriArgs, { SIDECAR_TARGET: arch });

  // 2. Locate the bundled .app; bail if Tauri didn't produce it.
  const bundleMacos = tauriTarget
    ? path.join("src-tauri", "target", tauriTarget, "release", "bundle", "macos", APP_NAME)
    : path.join("src-tauri", "target", "release", "bundle", "macos", APP_NAME);
  if (!existsSync(bundleMacos)) {
    console.error(`build-release: expected .app bundle not found for ${arch}: ${bundleMacos}`);
    process.exit(1);
  }

  // 3. Arch guard — BEFORE the tar step so a failure leaves zero tainted release/.
  const daemonInBundle = path.join(bundleMacos, "Contents", "MacOS", "pr-review-daemon");
  const capture = spawnSync("file", ["-b", daemonInBundle], { encoding: "utf8" });
  const desc = capture.stdout.trim();
  const expectedToken = arch === "arm64" ? "arm64" : "x86_64";
  if (!desc.startsWith("Mach-O") || !desc.includes(expectedToken) || desc.includes("script")) {
    console.error(
      `build-release: arch guard FAILED for ${arch}: file reports "${desc}" (expected token ${expectedToken}, must not contain "script" — catches the 269-byte #!/bin/sh stub)`,
    );
    process.exit(1);
  } else {
    console.error(`build-release: arch guard OK for ${arch}: ${desc}`);
  }

  // 4. Pack the .app into release/. --no-mac-metadata keeps bsdtar from baking
  //    com.apple.quarantine/FinderInfo xattrs and ._ AppleDouble junk.
  const tarOut = path.join(repoRoot, "release", `pr-review-${arch}.tar.gz`);
  rmSync(tarOut, { force: true });
  run(
    "tar",
    ["--no-mac-metadata", "-czf", tarOut, "-C", path.dirname(bundleMacos), APP_NAME],
    {},
  );
  console.error(`build-release: done ${arch} tar -> ${tarOut}`);

  // Discover the actual DMG Tauri produced (filename embeds productName + version).
  const bundleBase = tauriTarget
    ? path.join("src-tauri", "target", tauriTarget, "release", "bundle")
    : path.join("src-tauri", "target", "release", "bundle");
  const dmgDir = path.join(bundleBase, "dmg");
  const dmgs = existsSync(dmgDir)
    ? readdirSync(dmgDir).filter((f) => f.endsWith(".dmg"))
    : [];
  const dmgPath = dmgs.length > 0 ? path.join(dmgDir, dmgs[0]) : "(no DMG produced)";
  artifacts.push({ arch, tar: tarOut, dmg: dmgPath });
}

console.error("\nbuild-release: === Artifacts ===");
for (const a of artifacts) {
  console.error(`  [${a.arch}] tar.gz: ${a.tar}`);
  console.error(`  [${a.arch}] dmg:    ${a.dmg}`);
}
console.error("\nbuild-release: all arches built.");
