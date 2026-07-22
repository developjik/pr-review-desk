// sidecar-selfcheck.mjs — CI guard that a built sidecar binary is REAL and runs.
//
// Runs in CI after `build:sidecar` and before artifact upload (AC1.7b). It
// catches the 269-byte `#!/bin/sh` placeholder stub that ships under
// `src-tauri/binaries/` before a real cross-platform build runs, so a release
// artifact is never bundled with a no-op daemon.
//
// Usage:
//   node scripts/sidecar-selfcheck.mjs <path-to-sidecar-binary>
//
// Exit codes:
//   0  the binary is large enough AND printed a `daemon ready` / `proto:` line
//   1  stub detected, too small, immediate non-zero exit, or no match in 8 s

import { spawn } from "node:child_process";
import { open } from "node:fs/promises";
import { statSync, existsSync } from "node:fs";

const MIN_SIZE = 1_000_000; // 1 MB — real pkg binaries are ~40-60 MB; the stub is 269 B.
const READY_TIMEOUT_MS = 8000;
const READY_RE = /daemon ready|proto:/;

const binary = process.argv[2];
if (!binary) {
  console.error("sidecar-selfcheck: missing <path-to-sidecar-binary> argument.");
  console.error("usage: node scripts/sidecar-selfcheck.mjs <path-to-sidecar-binary>");
  process.exit(1);
}

if (!existsSync(binary)) {
  console.error(`sidecar-selfcheck: binary not found at "${binary}".`);
  process.exit(1);
}

// --- size guard: catches the placeholder stub --------------------------------
const size = statSync(binary).size;
if (size <= MIN_SIZE) {
  console.error(
    `sidecar-selfcheck: FAIL — "${binary}" is ${size} bytes (< ${MIN_SIZE}). ` +
      `Expected a real @yao-pkg/pkg binary (~40-60 MB). The 269-byte #!/bin/sh ` +
      `placeholder stub is still in place — run \`npm run build:sidecar\` first.`,
  );
  process.exit(1);
}

// --- magic-bytes guard: the sh stub starts with `#!/bin/sh` -------------------
const fh = await open(binary, "r");
const buf = Buffer.alloc(8);
await fh.read(buf, 0, 8, 0);
await fh.close();
if (buf.subarray(0, 7).toString("utf8") === "#!/bin/sh") {
  console.error(
    `sidecar-selfcheck: FAIL — "${binary}" starts with \`#!/bin/sh\`, the ` +
      `placeholder stub. The real binary has not been built yet.`,
  );
  process.exit(1);
}

// --- run guard: spawn and wait for the ready handshake ------------------------
const child = spawn(binary, [], { stdio: ["pipe", "pipe", "pipe"] });

let captured = "";

let settled = false;

const fail = (msg) => {
  if (settled) return;
  settled = true;
  clearTimeout(timer);
  child.kill();
  console.error(`sidecar-selfcheck: FAIL — ${msg}`);
  if (captured.trim()) {
    console.error("--- captured stdout/stderr ---");
    console.error(captured);
  }
  process.exit(1);
};

const ok = () => {
  if (settled) return;
  settled = true;
  clearTimeout(timer);
  child.kill();
  console.error(`sidecar-selfcheck: OK (${binary})`);
  process.exit(0);
};

// Append output to the capture buffer AND test for the ready/proto line in one
// pass, so a match is detected as soon as the bytes arrive.
const onChunk = (d) => {
  captured += d.toString("utf8");
  if (READY_RE.test(captured)) ok();
};
child.stdout.on("data", onChunk);
child.stderr.on("data", onChunk);

// If the binary exits before the handshake, that's a failure.
child.on("exit", (code, signal) => {
  fail(
    `binary exited before ready handshake (code=${code} signal=${signal}).`,
  );
});
child.on("error", (err) => {
  fail(`failed to spawn binary: ${err.message}`);
});

const timer = setTimeout(() => {
  fail(
    `no \`daemon ready\` / \`proto:\` line within ${READY_TIMEOUT_MS} ms.`,
  );
}, READY_TIMEOUT_MS);
