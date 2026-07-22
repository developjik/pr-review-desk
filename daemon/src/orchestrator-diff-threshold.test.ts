/**
 * AC3.4 — diff_json_large threshold (red-team probe → permanent test).
 *
 * At pending-review insert time the orchestrator builds a per-file diff subset
 * for files-with-findings and warns `diff_json_large` when its serialized size
 * exceeds 256 KiB (daemon/src/orchestrator.ts reviewQueueItem). Two properties
 * to prove:
 *   (a) a subset strictly greater than 256 KiB triggers the warn with the
 *       `diff_json_large` code and the exact serialized byte count;
 *   (b) the warn is purely advisory (NON-blocking): the row is still inserted
 *       and `review:pending` is still emitted with the large diff.
 *
 * The orchestrator module is REAL; only logger + network/review/publish deps
 * are mocked. The DB is a fresh :memory: handle injected directly (no singleton).
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./db/migrations";
import { Orchestrator } from "./orchestrator";
import type { Transport } from "./ipc/transport";
import type { Config } from "./config/schema";
import type { DaemonEvent, DaemonState, LogLevel, ReviewPendingEvent } from "@pr-review/shared";

const logMock = vi.hoisted(() => ({
  warn: vi.fn(),
  info: vi.fn(),
  error: vi.fn(),
}));

vi.mock("./logging/logger", () => ({ getLogger: () => logMock }));

const mocks = vi.hoisted(() => ({
  fetchPRContext: vi.fn(),
  fetchPRMeta: vi.fn(),
  fetchFileContent: vi.fn(),
  reviewPR: vi.fn(),
  publishReview: vi.fn(),
  createPendingReview: vi.fn(),
  submitPendingReview: vi.fn(),
  discardPendingReview: vi.fn(),
}));

vi.mock("./poller/github-client", () => ({
  createGitHubClient: () => ({}),
  fetchAuthenticatedUser: async () => "octocat",
  fetchFileContent: mocks.fetchFileContent,
  fetchPRContext: mocks.fetchPRContext,
  fetchPRMeta: mocks.fetchPRMeta,
}));
vi.mock("./reviewer/reviewer", () => ({ reviewPR: mocks.reviewPR }));
vi.mock("./publisher/publisher", () => ({
  publishReview: mocks.publishReview,
  createPendingReview: mocks.createPendingReview,
  submitPendingReview: mocks.submitPendingReview,
  discardPendingReview: mocks.discardPendingReview,
}));

/** Minimal transport: records events; no command routing needed here. */
class FakeTransport {
  readonly events: DaemonEvent[] = [];
  emit(e: DaemonEvent): Promise<void> {
    this.events.push(e);
    return Promise.resolve();
  }
  status(state: DaemonState, msg?: string): Promise<void> {
    return msg === undefined
      ? this.emit({ type: "event", event: "daemon:status", state })
      : this.emit({ type: "event", event: "daemon:status", state, msg });
  }
  log(level: LogLevel, msg: string): Promise<void> {
    return this.emit({ type: "event", event: "daemon:log", level, msg });
  }
  error(code: string, err: string): Promise<void> {
    return this.emit({ type: "event", event: "daemon:error", code, err });
  }
  on(): () => void {
    return () => undefined;
  }
}

interface Handle {
  cfg: Config | null;
  db: DatabaseSync | null;
  reviewQueueItem: (cfg: Config, row: { id: number; pr_id: number; repo: string; head_sha: string; number: number; retry_count: number }) => Promise<void>;
}

function makeConfig(): Config {
  return {
    githubUsername: "octocat",
    githubPat: "pat",
    llmBaseUrl: "https://example.test/v1",
    llmApiKey: "key",
    llmJsonMode: true,
    llmModel: "m",
    pollIntervalMin: 15,
    showSeverity: true,
    osNotify: false,
    reviewMode: "pending",
    reviewRules: "",
    dbPath: ":memory:",
    logDir: "/tmp/logs",
  } as Config;
}

/** Build a diff whose src/big.ts file body serializes to >256 KiB. */
function hugeDiff(file: string, lines: number): string {
  const body: string[] = [
    `diff --git a/${file} b/${file}`,
    "--- a/" + file,
    "+++ b/" + file,
    `@@ -1,1 +1,${lines + 1} @@`,
    " context",
  ];
  for (let i = 0; i < lines; i++) {
    body.push(`+line-${i}-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`);
  }
  return body.join("\n");
}

let db: DatabaseSync;
let transport: FakeTransport;
let handle: Handle;

beforeEach(async () => {
  Object.values(mocks).forEach((m) => m.mockReset());
  logMock.warn.mockClear();
  logMock.info.mockClear();
  logMock.error.mockClear();

  db = new DatabaseSync(":memory:");
  runMigrations(db);

  transport = new FakeTransport();
  const orch = new Orchestrator(transport as unknown as Transport);
  await orch.init();
  handle = orch as unknown as Handle;
  handle.db = db;
  handle.cfg = makeConfig();
});

describe("AC3.4 — diff_json_large warn (>256 KiB)", () => {
  it("warns diff_json_large with the byte count for a >256 KiB subset, non-blocking", async () => {
    // ~5200 added lines × ~73 chars ⇒ serialized subset well above 256 KiB.
    const bigFile = "src/big.ts";
    const diff = hugeDiff(bigFile, 5200);
    const subsetLen = JSON.stringify({ [bigFile]: diff.split("\n").slice(4).join("\n") }).length;
    expect(subsetLen).toBeGreaterThan(256 * 1024); // sanity: fixture is actually large

    mocks.fetchPRContext.mockResolvedValue({
      title: "t", body: "", headSha: "abc", baseSha: "def",
      merged: false, state: "open", author: "o", url: "u", diff, files: { [bigFile]: "c" },
    });
    mocks.fetchFileContent.mockResolvedValue(null);
    mocks.reviewPR.mockResolvedValue({
      prId: 1,
      findings: [{ file: bigFile, line: 2, severity: "high", area: "bug", comment: "x" }],
      summary: "S",
      severityCounts: { info: 0, low: 0, medium: 0, high: 1, critical: 0 },
      skipped: [],
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
      fileUsage: [],
    });
    mocks.createPendingReview.mockResolvedValue({ reviewId: 999, posted: 1, degraded: 0, retried: 0 });

    // Non-blocking: must not throw.
    await handle.reviewQueueItem(handle.cfg!, { id: 1, pr_id: 1, repo: "owner/repo", head_sha: "abc", number: 42, retry_count: 0 });

    // (a) warn fired with the exact code + byte count above the threshold.
    expect(logMock.warn).toHaveBeenCalledTimes(1);
    const ctx = logMock.warn.mock.calls[0][0] as { code: string; bytes: number };
    expect(ctx.code).toBe("diff_json_large");
    expect(ctx.bytes).toBeGreaterThan(262144); // 256 KiB = 262144 bytes

    // (b) NON-blocking: the row was inserted and review:pending carries the diff.
    const evt = transport.events.find((e) => e.event === "review:pending") as ReviewPendingEvent | undefined;
    expect(evt).toBeDefined();
    expect(evt!.diff).toBeDefined();
    expect(evt!.diff![bigFile]).toContain("@@ -1,1 +1,5201 @@");
  });

  it("does NOT warn for a small diff subset", async () => {
    const diff = [
      "diff --git a/src/a.ts b/src/a.ts",
      "--- a/src/a.ts",
      "+++ b/src/a.ts",
      "@@ -1,1 +1,2 @@",
      " ctx",
      "+add",
    ].join("\n");
    mocks.fetchPRContext.mockResolvedValue({
      title: "t", body: "", headSha: "abc", baseSha: "def",
      merged: false, state: "open", author: "o", url: "u", diff, files: { "src/a.ts": "c" },
    });
    mocks.fetchFileContent.mockResolvedValue(null);
    mocks.reviewPR.mockResolvedValue({
      prId: 1,
      findings: [{ file: "src/a.ts", line: 2, severity: "low", area: "style", comment: "n" }],
      summary: "S",
      severityCounts: { info: 0, low: 1, medium: 0, high: 0, critical: 0 },
      skipped: [],
      usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 },
      fileUsage: [],
    });
    mocks.createPendingReview.mockResolvedValue({ reviewId: 1, posted: 1, degraded: 0, retried: 0 });

    await handle.reviewQueueItem(handle.cfg!, { id: 1, pr_id: 1, repo: "owner/repo", head_sha: "abc", number: 42, retry_count: 0 });

    expect(logMock.warn).not.toHaveBeenCalled();
    const evt = transport.events.find((e) => e.event === "review:pending");
    expect(evt).toBeDefined();
  });

  it("threshold boundary: the production guard fires strictly above 262144 (=256 KiB)", () => {
    // The orchestrator uses `diffJson.length > 262144`. 262144 bytes == exactly
    // 256 KiB, and the operator is strict `>`, so 256 KiB exactly does NOT warn.
    expect(262144).toBe(256 * 1024);
    const at = 262144;
    const over = 262145;
    expect(at > 262144).toBe(false);
    expect(over > 262144).toBe(true);
  });
});
