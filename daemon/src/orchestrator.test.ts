import { describe, it, expect, vi, beforeEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./db/migrations";
import { insertPendingReview, type InsertPendingParams } from "./db/pending-reviews";
import { Orchestrator, applyEdits, decideApproval } from "./orchestrator";
import type { Transport } from "./ipc/transport";
import type { Config } from "./config/schema";
import type { Finding } from "./types/domain";
import type {
  CommandOf,
  DaemonCommandName,
  DaemonEvent,
  DaemonState,
  FindingEdit,
  LogLevel,
  PendingFinding,
  ReviewPendingEvent,
} from "@pr-review/shared";

// ---------------------------------------------------------------------------
// Mocks — mirror reviewer.test.ts vi.hoisted + vi.mock pattern.
// The orchestrator module is REAL; only its network/review/publish deps are
// stubbed. The DB is a fresh :memory: handle injected per-test (no connection
// singleton).
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// A transport that records every emitted event and can deliver a command to the
// registered handler (simulating a stdin command). Implements just the surface
// the orchestrator touches: on / emit / status / log / error.
// ---------------------------------------------------------------------------
class FakeTransport {
  readonly events: DaemonEvent[] = [];
  private readonly handlers = new Map<string, (cmd: unknown) => void | Promise<void>>();

  on<N extends DaemonCommandName>(
    cmd: N,
    listener: (cmd: CommandOf<N>) => void | Promise<void>,
  ): () => void {
    this.handlers.set(cmd, listener as (cmd: unknown) => void | Promise<void>);
    return () => {
      this.handlers.delete(cmd);
    };
  }

  emit(event: DaemonEvent): Promise<void> {
    this.events.push(event);
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

  /** Deliver a command to the registered handler (simulates a stdin line). */
  deliver<N extends DaemonCommandName>(cmd: N, payload: Omit<CommandOf<N>, "type" | "cmd">): Promise<void> {
    const handler = this.handlers.get(cmd);
    if (!handler) return Promise.resolve();
    return Promise.resolve(handler({ type: "command", cmd, ...payload } as unknown as CommandOf<N>));
  }
}

// ---------------------------------------------------------------------------
// Typed handle to reach the orchestrator's private db/cfg slots + the private
// review/approve methods at the method level (avoids running start()/poller).
// ---------------------------------------------------------------------------
interface QueueRowLike {
  id: number;
  pr_id: number;
  repo: string;
  head_sha: string;
  number: number;
  retry_count: number;
}
type ApproveFn = (
  reviewId: number,
  findingIds?: string[],
  edits?: Record<string, FindingEdit>,
) => Promise<void>;
interface OrchestratorHandle {
  db: DatabaseSync | null;
  cfg: Config | null;
  approveReview: ApproveFn;
  reviewQueueItem: (cfg: Config, row: QueueRowLike) => Promise<void>;
}

function makeConfig(overrides: Partial<Config> = {}): Config {
  return {
    githubUsername: "octocat",
    githubPat: "pat",
    llmBaseUrl: "https://example.test/v1",
    llmApiKey: "key",
    llmJsonMode: true,
    llmModel: "test-model",
    pollIntervalMin: 15,
    showSeverity: true,
    osNotify: false,
    reviewMode: "pending",
    reviewRules: "",
    dbPath: ":memory:",
    logDir: "/tmp/logs",
    ...overrides,
  } as Config;
}

/** A two-file diff where only `src/a.ts` is relevant to the seeded finding. */
const TWO_FILE_DIFF = [
  "diff --git a/src/a.ts b/src/a.ts",
  "index aaa..bbb 100644",
  "--- a/src/a.ts",
  "+++ b/src/a.ts",
  "@@ -1,3 +1,4 @@",
  " context",
  "-removed",
  "+added",
  "+more",
  "diff --git a/src/other.ts b/src/other.ts",
  "index ccc..ddd 100644",
  "--- a/src/other.ts",
  "+++ b/src/other.ts",
  "@@ -1,1 +1,1 @@",
  "-old",
  "+new",
].join("\n");

const OPEN_META = {
  title: "t",
  body: "",
  headSha: "abc",
  baseSha: "def",
  merged: false,
  state: "open" as const,
  author: "o",
  url: "u",
};

// Shared fixtures
let transport: FakeTransport;
let orch: Orchestrator;
let handle: OrchestratorHandle;
let db: DatabaseSync;

/** Seed a pending review with one inline (i0) + one degraded (d0) finding. */
function seedPending(overrides: Partial<InsertPendingParams> = {}): number {
  return insertPendingReview(db, {
    prId: 1,
    prNumber: 42,
    repo: "owner/repo",
    headSha: "abc123",
    title: "Test PR",
    summary: "ORIGINAL SUMMARY",
    inline: [
      { file: "src/a.ts", line: 5, severity: "high", area: "bug", comment: "inline orig" },
    ],
    degraded: [
      { file: "src/b.ts", line: null, severity: "info", area: "structure", comment: "degraded orig" },
    ],
    githubReviewId: 999,
    diff: { "src/a.ts": "@@ -1,3 +1,4 @@\n ctx\n+add\n", "src/b.ts": "@@ hunk b @@" },
    ...overrides,
  });
}

beforeEach(async () => {
  mocks.fetchPRContext.mockReset();
  mocks.fetchPRMeta.mockReset();
  mocks.fetchFileContent.mockReset();
  mocks.reviewPR.mockReset();
  mocks.publishReview.mockReset();
  mocks.createPendingReview.mockReset();
  mocks.submitPendingReview.mockReset();
  mocks.discardPendingReview.mockReset();

  db = new DatabaseSync(":memory:");
  runMigrations(db);

  transport = new FakeTransport();
  orch = new Orchestrator(transport as unknown as Transport);
  await orch.init();
  handle = orch as unknown as OrchestratorHandle;
  handle.db = db;
  handle.cfg = makeConfig();
});

// ===========================================================================
// applyEdits — pure edit contract (AC2.4)
// ===========================================================================
describe("applyEdits — pure edit contract", () => {
  const finding = (id: string): PendingFinding => ({
    id,
    file: "src/a.ts",
    line: 5,
    severity: "high",
    area: "bug",
    comment: "orig",
    suggestion: "orig-sug",
  });

  it("overrides only present fields and never mutates the input", () => {
    const src = [finding("i0"), finding("i1")];
    const edits: Record<string, FindingEdit> = { i0: { comment: "EDITED", severity: "medium" } };

    const out = applyEdits(src, edits);

    expect(out).toHaveLength(2);
    expect(out[0].comment).toBe("EDITED");
    expect(out[0].severity).toBe("medium");
    expect(out[0].line).toBe(5); // untouched
    expect(out[0].suggestion).toBe("orig-sug"); // untouched
    expect(out[0].file).toBe("src/a.ts"); // untouched
    // untouched finding passes through
    expect(out[1].comment).toBe("orig");
    // NEVER mutate input
    expect(src[0].comment).toBe("orig");
    expect(src[0].severity).toBe("high");
    // edited element is a fresh copy
    expect(out[0]).not.toBe(src[0]);
  });

  it("overrides line to null when explicitly present", () => {
    const out = applyEdits([finding("i0")], { i0: { line: null } });
    expect(out[0].line).toBeNull();
    expect(out[0].comment).toBe("orig");
  });

  it("ignores unknown ids and empty edits", () => {
    const src = [finding("i0")];
    expect(applyEdits(src, { nope: { comment: "x" } })[0].comment).toBe("orig");
    expect(applyEdits(src, {})[0].comment).toBe("orig");
  });

  it("only-undefined fields on an edit leave the finding unchanged", () => {
    // suggestion: undefined present → not an override (only present fields apply)
    const out = applyEdits([finding("i0")], { i0: { suggestion: undefined } });
    expect(out[0].suggestion).toBe("orig-sug");
  });
});

// ===========================================================================
// decideApproval — the 4 approval quadrants (AC2.4) + MUST-FIX 2 contract
// ===========================================================================
describe("decideApproval — 4 approval quadrants (AC2.4)", () => {
  const full = { keepInline: 2, keepDegraded: 1, totalInline: 2, totalDegraded: 1 };

  it("(a) no edits + full selection → submitPendingReview path", () => {
    expect(decideApproval({ ...full, githubReviewId: 7 })).toEqual({
      hasEdits: false,
      isSelectionComplete: true,
      useSubmitPath: true,
    });
  });

  it("(b) subset selection → discard+publish with summary cleared", () => {
    const d = decideApproval({
      findingIds: ["i0"], // a defined subset request (not undefined == full)
      keepInline: 1,
      keepDegraded: 1,
      totalInline: 2,
      totalDegraded: 1,
      githubReviewId: 7,
    });
    expect(d.isSelectionComplete).toBe(false);
    expect(d.useSubmitPath).toBe(false);
    expect(d.hasEdits).toBe(false);
  });

  it("(c) edits={} empty → behaves as no-edits (submit path if full)", () => {
    const d = decideApproval({ ...full, edits: {}, githubReviewId: 7 });
    expect(d.hasEdits).toBe(false);
    expect(d.useSubmitPath).toBe(true);
  });

  it("(d) edits non-empty + FULL selection → force discard+publish, summary PRESERVED", () => {
    const d = decideApproval({ ...full, edits: { i0: { comment: "x" } }, githubReviewId: 7 });
    expect(d.hasEdits).toBe(true);
    expect(d.isSelectionComplete).toBe(true); // → summary preserved
    expect(d.useSubmitPath).toBe(false); // → discard + publishReview
  });

  it("no github_review_id → never submit path even when full + no edits", () => {
    const d = decideApproval({ ...full, githubReviewId: null });
    expect(d.useSubmitPath).toBe(false);
    expect(d.isSelectionComplete).toBe(true);
  });

  it("findingIds omitted counts as full selection", () => {
    const d = decideApproval({
      keepInline: 0,
      keepDegraded: 0,
      totalInline: 0,
      totalDegraded: 0,
      githubReviewId: 7,
      findingIds: undefined,
    });
    expect(d.isSelectionComplete).toBe(true);
    expect(d.useSubmitPath).toBe(true);
  });
});

// ===========================================================================
// Integration — review:pending emit + approve path via the real orchestrator
// ===========================================================================
describe("orchestrator — pending diff snapshot + approve edits (integration)", () => {
  it("AC1.6 — review:pending carries a non-empty diff keyed only by files-with-findings (MUST-FIX c)", async () => {
    mocks.fetchPRContext.mockResolvedValue({
      title: "PR",
      body: "",
      headSha: "abc",
      baseSha: "def",
      merged: false,
      state: "open",
      author: "o",
      url: "u",
      diff: TWO_FILE_DIFF,
      files: { "src/a.ts": "content", "src/other.ts": "other" },
    });
    mocks.fetchFileContent.mockResolvedValue(null);
    mocks.reviewPR.mockResolvedValue({
      prId: 1,
      findings: [{ file: "src/a.ts", line: 2, severity: "high", area: "bug", comment: "issue" }],
      summary: "SUMMARY",
      severityCounts: { info: 0, low: 0, medium: 0, high: 1, critical: 0 },
      skipped: [],
    });
    mocks.createPendingReview.mockResolvedValue({ reviewId: 999, posted: 1, degraded: 0, retried: 0 });

    const cfg = makeConfig({ reviewMode: "pending" });
    const row: QueueRowLike = { id: 1, pr_id: 1, repo: "owner/repo", head_sha: "abc", number: 42, retry_count: 0 };
    await handle.reviewQueueItem(cfg, row);

    const evt = transport.events.find((e) => e.event === "review:pending") as ReviewPendingEvent | undefined;
    expect(evt).toBeDefined();
    expect(evt!.diff).toBeDefined();
    // ONLY the file with a finding is snapshotted (not src/other.ts).
    expect(Object.keys(evt!.diff!)).toEqual(["src/a.ts"]);
    expect(evt!.diff!["src/a.ts"]).toContain("@@ -1,3 +1,4 @@");
  });

  it("init() approve:review handler threads c.edits (MUST-FIX d)", async () => {
    const edits: Record<string, FindingEdit> = { i0: { comment: "x" } };
    const spy = vi.fn<ApproveFn>().mockResolvedValue(undefined);
    handle.approveReview = spy as unknown as ApproveFn;

    await transport.deliver("approve:review", { reviewId: 7, findingIds: ["i0"], edits });

    expect(spy).toHaveBeenCalledWith(7, ["i0"], edits);
  });

  it("AC2.2(a) — no edits + full selection: submitPendingReview path (byte-identical to today)", async () => {
    const reviewId = seedPending();
    mocks.fetchPRMeta.mockResolvedValue(OPEN_META);
    mocks.submitPendingReview.mockResolvedValue(undefined);

    // No findingIds ⇒ full approval; no edits.
    await handle.approveReview(reviewId);

    expect(mocks.submitPendingReview).toHaveBeenCalledTimes(1);
    expect(mocks.publishReview).not.toHaveBeenCalled();
    expect(mocks.discardPendingReview).not.toHaveBeenCalled();
    expect(transport.events.some((e) => e.event === "pending:resolved")).toBe(true);
  });

  it("AC2.2(b) — subset selection (no edits): discard+publish, summary cleared", async () => {
    const reviewId = seedPending();
    mocks.fetchPRMeta.mockResolvedValue(OPEN_META);
    mocks.discardPendingReview.mockResolvedValue(undefined);
    mocks.publishReview.mockResolvedValue({ posted: 1, degraded: 0, retried: 0 });

    // Only i0 approved (d0 dropped) → subset.
    await handle.approveReview(reviewId, ["i0"]);

    expect(mocks.submitPendingReview).not.toHaveBeenCalled();
    expect(mocks.publishReview).toHaveBeenCalledTimes(1);
    const mapped = mocks.publishReview.mock.calls[0][4] as {
      inline: Finding[];
      degraded: Finding[];
      summary: string;
    };
    expect(mapped.summary).toBe(""); // subset → cleared
    expect(mapped.inline).toHaveLength(1);
    expect(mapped.degraded).toHaveLength(0);
  });

  it("AC2.4(c) — edits={} empty behaves as no-edits (submit path if full)", async () => {
    const reviewId = seedPending();
    mocks.fetchPRMeta.mockResolvedValue(OPEN_META);
    mocks.submitPendingReview.mockResolvedValue(undefined);

    await handle.approveReview(reviewId, undefined, {});

    expect(mocks.submitPendingReview).toHaveBeenCalledTimes(1);
    expect(mocks.publishReview).not.toHaveBeenCalled();
  });

  it("AC2.1 / AC2.4(d) — full approval WITH edits: force discard+republish, EDITED content, summary PRESERVED", async () => {
    const reviewId = seedPending();
    mocks.fetchPRMeta.mockResolvedValue(OPEN_META);
    mocks.discardPendingReview.mockResolvedValue(undefined);
    mocks.publishReview.mockResolvedValue({ posted: 1, degraded: 1, retried: 0 });

    // FULL selection (all ids) + edits on i0. isSelectionComplete=true, hasEdits=true.
    await handle.approveReview(reviewId, ["i0", "d0"], {
      i0: { comment: "EDITED COMMENT", severity: "critical" },
    });

    // Edits force the discard + republish path (never submit the original).
    expect(mocks.submitPendingReview).not.toHaveBeenCalled();
    expect(mocks.discardPendingReview).toHaveBeenCalledTimes(1);
    expect(mocks.publishReview).toHaveBeenCalledTimes(1);

    const [, owner, name, prNumber, mapped, config] = mocks.publishReview.mock.calls[0] as [
      unknown,
      string,
      string,
      number,
      { inline: Finding[]; degraded: Finding[]; summary: string },
      { showSeverity: boolean },
    ];
    expect(owner).toBe("owner");
    expect(name).toBe("repo");
    expect(prNumber).toBe(42);
    expect(config.showSeverity).toBe(true);

    // EDITED inline content flows through (not the original).
    expect(mapped.inline).toHaveLength(1);
    expect(mapped.inline[0].comment).toBe("EDITED COMMENT");
    expect(mapped.inline[0].severity).toBe("critical");

    // CRITICAL (MUST-FIX 2): full-approval-with-edits PRESERVES claimed.summary.
    expect(mapped.summary).toBe("ORIGINAL SUMMARY");

    // publish:review + pending:resolved emitted.
    expect(transport.events.some((e) => e.event === "publish:review")).toBe(true);
    expect(transport.events.some((e) => e.event === "pending:resolved")).toBe(true);
  });

  it("AC2.3 — an edited line outside the diff still flows to publishReview via the republish path", async () => {
    const reviewId = seedPending();
    mocks.fetchPRMeta.mockResolvedValue(OPEN_META);
    mocks.discardPendingReview.mockResolvedValue(undefined);
    mocks.publishReview.mockResolvedValue({ posted: 1, degraded: 0, retried: 0 });

    // Edit i0's line to a value that is NOT a valid new-side line in src/a.ts
    // (its stored hunk is "@@ -1,3 +1,4 @@\n ctx\n+add\n" → valid lines {1,2}).
    // Full selection so isSelectionComplete=true; edits present → republish path.
    await handle.approveReview(reviewId, ["i0", "d0"], { i0: { line: 99999 } });

    // Edits force the discard + republish path (never submit the original).
    expect(mocks.submitPendingReview).not.toHaveBeenCalled();
    expect(mocks.discardPendingReview).toHaveBeenCalledTimes(1);
    expect(mocks.publishReview).toHaveBeenCalledTimes(1);

    const mapped = mocks.publishReview.mock.calls[0][4] as {
      inline: Finding[];
      degraded: Finding[];
      summary: string;
    };

    // The edited (out-of-range) line is preserved through to publishReview — the
    // orchestrator does NOT silently drop or re-validate it; the publisher's own
    // 422 progressive-trim recovery handles invalid lines (AC2.3).
    expect(mapped.inline).toHaveLength(1);
    expect(mapped.inline[0].line).toBe(99999);
    // Full approval → summary preserved despite the forced republish.
    expect(mapped.summary).toBe("ORIGINAL SUMMARY");
  });
});
