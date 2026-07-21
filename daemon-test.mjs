// Standalone driver: spawns the daemon, drives its stdin with real delays,
// and asserts the stdout event sequence. Run: node daemon-test.mjs
import { spawn } from "node:child_process";

const child = spawn(
  "node",
  ["node_modules/tsx/dist/cli.mjs", "daemon/src/main.ts"],
  { stdio: ["pipe", "pipe", "inherit"] },
);

const out = [];
let buf = "";
child.stdout.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i);
    buf = buf.slice(i + 1);
    if (line.trim()) out.push(JSON.parse(line));
  }
});

const send = (obj) =>
  new Promise((r) => child.stdin.write(JSON.stringify(obj) + "\n", r));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

const CONFIG = {
  githubUsername: "octocat",
  githubPat: "pat_xxx",
  llmBaseUrl: "http://localhost:11434",
  llmApiKey: "sk-x",
  llmModel: "gpt-4o",
  dbPath: "./data/reviews.db",
  logDir: "./logs",
};

let failed = 0;
function assert(cond, msg) {
  if (cond) {
    console.log("  ok  -", msg);
  } else {
    console.error("  FAIL-", msg);
    failed++;
  }
}
function findEvents(name) {
  return out.filter((e) => e.event === name);
}

child.on("exit", async (code) => {
  const events = (n) => out.map((e) => e.event).filter((x) => x === n);
  console.log("\n--- assertions (exit code", code, ") ---");
  assert(code === 0, "daemon exits 0");
  assert(out[0]?.event === "daemon:ready" && out[0]?.proto === 1, "first event is daemon:ready proto 1");
  assert(
    findEvents("daemon:status").some((e) => e.state === "idle"),
    "config -> daemon:status idle",
  );
  assert(
    findEvents("poll:started").length >= 1,
    "poll:now -> poll:started emitted",
  );
  const statuses = findEvents("daemon:status").map((e) => e.state);
  assert(
    statuses.includes("polling") && statuses.includes("idle"),
    "poll:now transitions polling then idle",
  );
  const logs = findEvents("daemon:log");
  assert(logs.some((l) => /starting orchestrator/.test(l.msg)), "daemon:log forwarded from pino");
  console.log("\nevent sequence:", out.map((e) => `${e.event}${e.state ? `:${e.state}` : ""}`).join(" -> "));
  console.log(failed === 0 ? "\nALL PASS" : `\n${failed} FAILED`);
  process.exit(failed === 0 ? 0 : 1);
});

await wait(300); // let READY emit
await send({ type: "command", cmd: "config", config: CONFIG });
await wait(400); // let config handshake complete
await send({ type: "command", cmd: "poll:now" });
await wait(300);
await send({ type: "command", cmd: "shutdown" });
