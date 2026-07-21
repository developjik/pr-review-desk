// End-to-end harness: drives the REAL daemon (tsx) through full poll → review →
// publish cycles against in-process mock GitHub + mock LLM HTTP servers.
// Closes the verification gap left by daemon-test.mjs (lifecycle-only, 401 PAT).
//
// Run:  npm run test:e2e    (or: node daemon-e2e-harness.mjs)
//
// Proves what unit/integration tests cannot: the REAL Octokit client, REAL
// OpenAI SDK, REAL node:sqlite DB, and REAL daemon lifecycle wired together —
// across happy path + adversarial scenarios (rate-limit backoff, 422 trim,
// large-PR chunking, merged/closed skip, multi-file).
import { spawn } from "node:child_process";
import http from "node:http";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// ---- shared fixture constants ----------------------------------------------
const OWNER = "acme";
const REPO = "widget";
const PR = 42;
const HEAD = "commit-abc-123";
const FILE = "src/app.ts";
const FILE2 = "src/util.ts";
const json = (o) => JSON.stringify(o);
const LINE = (n) => `line${n}`;
// 16-line single-hunk fixture file + diff (new-side valid lines 10-16).
const FILE_CONTENT = Array.from({ length: 16 }, (_, i) => LINE(i + 1)).join("\n") + "\n";
const SINGLE_DIFF = [
  "diff --git a/src/app.ts b/src/app.ts", "index 111..222 100644",
  "--- a/src/app.ts", "+++ b/src/app.ts", "@@ -10,7 +10,8 @@",
  " line10", " line11", "-  const x = obj.field;", "+  const x = obj?.field;",
  "+  console.log(x);", " line13", " line14", " line15", "",
].join("\n");
// A second small file diff (new-side valid line 5).
const FILE2_CONTENT = Array.from({ length: 10 }, (_, i) => `u${i + 1}`).join("\n") + "\n";
const FILE2_DIFF = [
  "diff --git a/src/util.ts b/src/util.ts", "index 333..444 100644",
  "--- a/src/util.ts", "+++ b/src/util.ts", "@@ -3,5 +3,6 @@",
  " u3", " u4", "-  return null;", "+  return {};", " u5", " u6", "",
].join("\n");

// Build a large multi-hunk diff (>500 diff lines) to force chunking.
function buildLargeDiff(file) {
  const hunks = [];
  const full = [];
  full.push(`diff --git a/${file} b/${file}`, "index aaa..bbb 100644", `--- a/${file}`, `+++ b/${file}`);
  // Two hunks of 300 content lines each = 600 diff lines > 500 chunk budget.
  for (const start of [1, 400]) {
    const lines = [];
    lines.push(`@@ -${start},300 +${start},300 @@`);
    for (let i = 0; i < 300; i++) lines.push(` ${LINE(start + i)}`); // context lines
    hunks.push(lines.join("\n"));
  }
  return full.concat(hunks).join("\n");
}
const LARGE_FILE = "src/big.ts";
const LARGE_FILE_CONTENT = Array.from({ length: 800 }, (_, i) => LINE(i + 1)).join("\n") + "\n";

// ---- mutable mock behavior (scenarios set these) ---------------------------
let gh = {};
let llm = {};

// ---- mock GitHub server -----------------------------------------------------
function startMockGitHub() {
  const requests = [];
  const reset = () => (requests.length = 0);
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const u = new URL(req.url, "http://localhost");
      const path = u.pathname;
      const accept = req.headers.accept || "";
      requests.push({ method: req.method, url: req.url, body });
      const send = (code, headers, payload) => {
        res.writeHead(code, headers);
        res.end(typeof payload === "string" ? payload : json(payload));
      };
      const ok = (payload) => send(200, { "content-type": "application/json" }, payload);

      // GET /search/issues  (supports rate-limit-once injection)
      if (req.method === "GET" && path === "/search/issues") {
        gh.searchCalls = (gh.searchCalls ?? 0) + 1;
        if (gh.rateLimitOnce && gh.searchCalls === 1) {
          return send(403, { "content-type": "application/json", "x-ratelimit-remaining": "0", "retry-after": "1" }, {
            message: "API rate limit exceeded",
          });
        }
        return ok({
          total_count: 1,
          incomplete_results: false,
          items: [
            {
              number: PR, title: "Fix", state: "open", draft: false, user: { login: "alice" },
              html_url: `https://github.com/${OWNER}/${REPO}/pull/${PR}`,
              repository_url: `https://api.github.com/repos/${OWNER}/${REPO}`,
              updated_at: "2026-07-16T00:00:00Z",
            },
          ],
        });
      }
      // GET /repos/:o/:r/pulls/:n  (diff vs JSON by Accept; honors closed/merged)
      if (req.method === "GET" && path === `/repos/${OWNER}/${REPO}/pulls/${PR}`) {
        if (accept.includes("diff")) return send(200, { "content-type": "text/plain; charset=utf-8" }, gh.diff ?? SINGLE_DIFF);
        return ok({
          number: PR, title: "Fix", body: "b",
          head: { sha: HEAD }, base: { sha: "base" },
          merged: gh.merged ?? false,
          state: gh.prState ?? "open",
          user: { login: "alice" },
          html_url: `https://github.com/${OWNER}/${REPO}/pull/${PR}`,
          labels: (gh.labels ?? []).map((name) => ({ name })),
        });
      }
      // GET /repos/:o/:r/pulls/:n/files
      if (req.method === "GET" && path === `/repos/${OWNER}/${REPO}/pulls/${PR}/files`) {
        return ok((gh.files ?? [{ filename: FILE, status: "modified" }]).map((f) => ({ sha: "f", ...f, additions: 1, deletions: 1, changes: 2 })));
      }
      // GET /repos/:o/:r/contents/<path>?ref=
      if (req.method === "GET" && path.startsWith(`/repos/${OWNER}/${REPO}/contents/`)) {
        const sub = decodeURIComponent(path.slice(`/repos/${OWNER}/${REPO}/contents/`.length));
        if (sub === ".prreview/rules.md") return send(404, { "content-type": "application/json" }, {});
        const map = gh.fileContents ?? { [FILE]: FILE_CONTENT };
        if (sub in map) return ok({ type: "file", encoding: "base64", path: sub, content: Buffer.from(map[sub]).toString("base64") });
        return send(404, { "content-type": "application/json" }, {});
      }
      // GET /repos/:o/:r/pulls/:n/comments  (listReviewComments → dedupe)
      if (req.method === "GET" && path === `/repos/${OWNER}/${REPO}/pulls/${PR}/comments`) return ok([]);
      // POST /repos/:o/:r/pulls/:n/reviews  (createReview; supports 422-once)
      if (req.method === "POST" && path === `/repos/${OWNER}/${REPO}/pulls/${PR}/reviews`) {
        gh.reviewCalls = (gh.reviewCalls ?? 0) + 1;
        if (gh.review422 && gh.reviewCalls === 1) {
          return send(422, { "content-type": "application/json" }, {
            message: "Validation Failed",
            errors: [{ resource: "PullRequestReview", code: "custom", field: "pull_request_review_comment_line", value: 12, message: `${FILE}:12 is invalid` }],
          });
        }
        return ok({ id: 1001, state: "COMMENTED" });
      }
      // POST /repos/:o/:r/issues/:n/comments  (degraded standalone)
      if (req.method === "POST" && path === `/repos/${OWNER}/${REPO}/issues/${PR}/comments`) return send(201, { "content-type": "application/json" }, { id: 2001 });
      return send(404, { "content-type": "application/json" }, { message: `mock: no route ${req.method} ${req.url}` });
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, requests, reset, port: server.address().port })));
}

// ---- mock LLM server --------------------------------------------------------
function startMockLLM() {
  const calls = [];
  const reset = () => (calls.length = 0);
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      calls.push({ body });
      // llm.review may be a canned review {findings,summary} or a function(file).
      let review = llm.review ?? { findings: [{ line: 12, severity: "high", area: "bug", comment: "null deref", suggestion: "use ?." }], summary: "one issue" };
      if (typeof review === "function") {
        let fileName = "";
        try {
          fileName = JSON.parse(body).messages?.[1]?.content?.match(/## (?:Diff|Full file content) — (.+)/)?.[1] ?? "";
        } catch { /* empty */ }
        review = review(fileName);
      }
      res.writeHead(200, { "content-type": "application/json" });
      res.end(json({
        id: "chatcmpl-mock", object: "chat.completion",
        choices: [{ index: 0, message: { role: "assistant", content: json(review) }, finish_reason: "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 },
      }));
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve({ server, calls, reset, port: server.address().port })));
}

// ---- daemon driver ----------------------------------------------------------
function spawnDaemon(env) {
  const child = spawn("node", ["node_modules/tsx/dist/cli.mjs", "daemon/src/main.ts"], {
    stdio: ["pipe", "pipe", "inherit"], env: { ...process.env, ...env },
  });
  const events = [];
  let buf = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    buf += chunk;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i);
      buf = buf.slice(i + 1);
      if (line.trim()) { try { events.push(JSON.parse(line)); } catch { /* non-JSON */ } }
    }
  });
  return { child, events };
}
const send = (child, obj) => new Promise((r) => child.stdin.write(json(obj) + "\n", r));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(events, predicate, timeoutMs, interval = 50) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) { if (events.some(predicate)) return true; await wait(interval); }
  return events.some(predicate);
}
const found = (events, name) => events.filter((e) => e.event === name);

async function runScenario({ ghPort, llmPort, reviewMode = "auto", reviewRules, repoInclude, repoExclude, triggerLabels, skipLabels, terminalEvent, terminalTimeout = 8000 }) {
  const dir = mkdtempSync(join(tmpdir(), "pr-review-e2e-"));
  const config = {
    githubUsername: "octocat", githubPat: "pat_mock",
    llmBaseUrl: `http://127.0.0.1:${llmPort}`, llmApiKey: "sk-mock", llmModel: "mock-model", llmJsonMode: true,
    pollIntervalMin: 15, showSeverity: true, osNotify: false, reviewMode,
    dbPath: join(dir, "reviews.db"), logDir: join(dir, "logs"),
    ...(reviewRules !== undefined ? { reviewRules } : {}),
    ...(repoInclude !== undefined ? { repoInclude } : {}),
    ...(repoExclude !== undefined ? { repoExclude } : {}),
    ...(triggerLabels !== undefined ? { triggerLabels } : {}),
    ...(skipLabels !== undefined ? { skipLabels } : {}),
  };
  const { child, events } = spawnDaemon({ PR_GITHUB_API_BASE_URL: `http://127.0.0.1:${ghPort}` });
  await wait(300);
  await send(child, { type: "command", cmd: "config", config });
  await waitFor(events, (e) => e.event === "daemon:status" && e.state === "idle", 5000);
  await send(child, { type: "command", cmd: "poll:now" });
  if (terminalEvent) await waitFor(events, (e) => e.event === terminalEvent, terminalTimeout);
  else await waitFor(events, () => false, 1200); // skip/closed path: short settle
  await wait(200);
  await send(child, { type: "command", cmd: "shutdown" });
  await wait(700);
  return { events, dir };
}

// ---- assertions ------------------------------------------------------------
let failed = 0;
const ok = (c, m) => { if (c) console.log("  ok  -", m); else { console.error("  FAIL-", m); failed++; } };
const reviewPost = (ghReq) => ghReq.find((r) => r.method === "POST" && r.url === `/repos/${OWNER}/${REPO}/pulls/${PR}/reviews`);
const issuePost = (ghReq) => ghReq.find((r) => r.method === "POST" && r.url === `/repos/${OWNER}/${REPO}/issues/${PR}/comments`);

// ---- main ------------------------------------------------------------------
(async () => {
  const GH = await startMockGitHub();
  const LLM = await startMockLLM();
  let code = 0;
  const cfg = () => ({ ghPort: GH.port, llmPort: LLM.port });
  const resetMocks = (overrides = {}) => { GH.reset(); LLM.reset(); gh = { searchCalls: 0, reviewCalls: 0, ...overrides }; llm = {}; };

  try {
    // 1 — AUTO full cycle (core)
    console.log("\n=== 1. AUTO-mode full poll → review → publish ===");
    resetMocks(); llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "deref", suggestion: "?." }], summary: "one" };
    const s1 = await runScenario({ ...cfg(), reviewMode: "auto", reviewRules: "Always validate inputs.", terminalEvent: "publish:review" });
    ok(found(s1.events, "poll:found").length === 1, "poll:found discovers the mock PR");
    ok(found(s1.events, "review:file").length === 1 && found(s1.events, "review:file")[0].findings === 1, "review:file with 1 finding");
    ok(found(s1.events, "publish:review")[0]?.posted >= 1, "publish:review posted >= 1");
    const rp1 = reviewPost(GH.requests);
    ok(!!rp1 && JSON.parse(rp1.body).comments?.[0]?.path === FILE && JSON.parse(rp1.body).comments?.[0]?.line === 12, "posted inline comment path/line correct");
    const sys1 = JSON.parse(LLM.calls[0]?.body ?? "{}").messages?.[0]?.content ?? "";
    ok(/Team \/ project guidelines/.test(sys1) && sys1.includes("Always validate inputs."), "F1 guidelines injected into LLM system prompt");

    // 2 — PENDING mode carries diff (F1 plumbing)
    console.log("\n=== 2. PENDING-mode review:pending carries diff ===");
    resetMocks();
    const s2 = await runScenario({ ...cfg(), reviewMode: "pending", terminalEvent: "review:pending" });
    const rp2 = found(s2.events, "review:pending")[0];
    ok(!!rp2 && rp2.diff?.[FILE]?.includes("@@ -10,7 +10,8 @@"), "review:pending carries diff keyed by file (AC1.6)");

    // 3 — Rate-limit backoff on search (withRateLimitRetry)
    console.log("\n=== 3. Rate-limit backoff (403 + retry-after → retry succeeds) ===");
    resetMocks({ rateLimitOnce: true });
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const t3 = Date.now();
    const s3 = await runScenario({ ...cfg(), reviewMode: "auto", terminalEvent: "publish:review", terminalTimeout: 10000 });
    ok(found(s3.events, "poll:found").length === 1, "poll succeeds after rate-limit retry (poll:found)");
    ok(GH.requests.filter((r) => r.method === "GET" && r.url.startsWith("/search/issues")).length >= 2, "search retried after 403");
    ok(Date.now() - t3 >= 900, "respected ~1s retry-after backoff");

    // 4 — 422 progressive-trim (inline → degraded → standalone comment)
    console.log("\n=== 4. 422 progressive-trim (inline rejected → degraded comment) ===");
    resetMocks({ review422: true });
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "bad line", suggestion: "fix" }], summary: "s" };
    const s4 = await runScenario({ ...cfg(), reviewMode: "auto", terminalEvent: "publish:review" });
    const pub4 = found(s4.events, "publish:review")[0];
    ok(!!pub4, "publish:review fires despite 422 (recovered)");
    ok(gh.reviewCalls >= 2, "createReview retried after 422 (progressive trim)");
    ok(!!issuePost(GH.requests), "degraded finding posted as standalone issue comment");

    // 5 — Large-PR chunking (diff >500 lines → ≥2 LLM chunks)
    console.log("\n=== 5. Large-PR chunking (diff >500 lines → multiple chunks) ===");
    resetMocks({ diff: buildLargeDiff(LARGE_FILE), files: [{ filename: LARGE_FILE, status: "modified" }], fileContents: { [LARGE_FILE]: LARGE_FILE_CONTENT } });
    llm.review = (file) => ({ findings: [{ line: 5, severity: "low", area: "style", comment: "nit", suggestion: "x" }], summary: "chunk review" });
    const s5 = await runScenario({ ...cfg(), reviewMode: "auto", terminalEvent: "publish:review" });
    ok(LLM.calls.length >= 2, `large diff reviewed in ≥2 chunks (got ${LLM.calls.length} LLM calls)`);
    ok(found(s5.events, "review:file").length === 1, "exactly ONE review:file for the chunked file (merged)");
    ok(!!found(s5.events, "publish:review").length, "chunked review still publishes");

    // 6 — Merged/closed skip
    console.log("\n=== 6. Closed-PR skip (no review, no publish) ===");
    resetMocks({ prState: "closed" });
    const s6 = await runScenario({ ...cfg(), reviewMode: "auto" });
    ok(found(s6.events, "poll:skipped").length >= 1, "poll:skipped emitted for closed PR");
    ok(found(s6.events, "review:file").length === 0, "no review:file for closed PR");
    ok(found(s6.events, "publish:review").length === 0, "no publish:review for closed PR");

    // 7 — Multi-file review (2 files → 2 review:file)
    console.log("\n=== 7. Multi-file review (2 files → 2 review:file) ===");
    resetMocks({ diff: `${SINGLE_DIFF}\n${FILE2_DIFF}`, files: [{ filename: FILE, status: "modified" }, { filename: FILE2, status: "modified" }], fileContents: { [FILE]: FILE_CONTENT, [FILE2]: FILE2_CONTENT } });
    llm.review = (file) => ({ findings: [{ line: file === FILE2 ? 5 : 12, severity: "medium", area: "style", comment: "c", suggestion: "s" }], summary: "mf" });
    const s7 = await runScenario({ ...cfg(), reviewMode: "auto", terminalEvent: "review:summary" });
    const rf7 = found(s7.events, "review:file");
    ok(rf7.length === 2, `2 review:file events for 2 files (got ${rf7.length})`);
    ok(found(s7.events, "review:summary").length === 1, "review:summary aggregates both files");
    // 8 — skip-label filters PR (no publish)
    console.log("\n=== 8. skip-label filters PR (no publish) ===");
    resetMocks({ labels: ["wip"] });
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s8 = await runScenario({ ...cfg(), reviewMode: "auto", skipLabels: "wip" });
    ok(found(s8.events, "poll:found").length === 0, "skip-label: PR filtered (no poll:found)");
    ok(found(s8.events, "publish:review").length === 0, "skip-label: no publish:review");

    // 9 — excluded-repo filters PR pre-meta (no fetch, no publish)
    console.log("\n=== 9. excluded-repo filters PR (no meta fetch, no publish) ===");
    resetMocks();
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s9 = await runScenario({ ...cfg(), reviewMode: "auto", repoExclude: "acme/*" });
    ok(found(s9.events, "poll:found").length === 0, "repo-exclude: PR filtered (no poll:found)");
    ok(found(s9.events, "publish:review").length === 0, "repo-exclude: no publish:review");
    ok(GH.requests.filter((r) => r.method === "GET" && r.url === `/repos/${OWNER}/${REPO}/pulls/${PR}`).length === 0, "repo-exclude: pulls.get NOT called (pre-meta skip)");

    // 10 — trigger-present publishes
    console.log("\n=== 10. trigger-label present (publishes normally) ===");
    resetMocks({ labels: ["needs-review"] });
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s10 = await runScenario({ ...cfg(), reviewMode: "auto", triggerLabels: "needs-review", terminalEvent: "publish:review" });
    ok(found(s10.events, "poll:found").length === 1, "trigger-present: PR discovered (poll:found)");
    ok(found(s10.events, "publish:review").length >= 1, "trigger-present: publishes review");

    // 11 — trigger-absent filters (no publish)
    console.log("\n=== 11. trigger-label absent (no publish) ===");
    resetMocks({ labels: [] });
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s11 = await runScenario({ ...cfg(), reviewMode: "auto", triggerLabels: "needs-review" });
    ok(found(s11.events, "poll:found").length === 0, "trigger-absent: PR filtered (no poll:found)");
    ok(found(s11.events, "publish:review").length === 0, "trigger-absent: no publish:review");

    // 12 — empty filters = control (publishes normally)
    console.log("\n=== 12. empty filters = control (publishes normally) ===");
    resetMocks();
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s12 = await runScenario({ ...cfg(), reviewMode: "auto", terminalEvent: "publish:review" });
    ok(found(s12.events, "poll:found").length === 1, "empty-filters: PR discovered (byte-identical to baseline)");
    ok(found(s12.events, "publish:review").length >= 1, "empty-filters: publishes review (backward-compat)");

    // 13 — case-differing repo exclude pattern (case-insensitive)
    console.log("\n=== 13. case-differing repo exclude (case-insensitive match) ===");
    resetMocks();
    llm.review = { findings: [{ file: FILE, line: 12, severity: "high", area: "bug", comment: "x", suggestion: "y" }], summary: "s" };
    const s13 = await runScenario({ ...cfg(), reviewMode: "auto", repoExclude: "ACME/*" });
    ok(found(s13.events, "poll:found").length === 0, "case-insensitive repo-exclude: PR filtered (ACME/* matches acme/widget)");
    ok(found(s13.events, "publish:review").length === 0, "case-insensitive repo-exclude: no publish:review");
  } catch (err) {
    console.error("\nHARNESS ERROR:", err);
    code = 1;
  } finally {
    GH.server.close();
    LLM.server.close();
  }
  console.log(failed === 0 && code === 0 ? "\nALL PASS" : `\n${failed} FAILED${code ? " (+ harness error)" : ""}`);
  process.exit(failed === 0 && code === 0 ? 0 : 1);
})();
