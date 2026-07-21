import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Config } from "../config/schema";
import type { Finding, ReviewContext, Severity } from "../types/domain";
import type { LlmFileReview } from "./llm-client";

// Script the LLM client: `createLlmClient` returns an object whose `reviewFile`
// is a fully-controlled vi.fn. `vi.hoisted` keeps the shared refs available to
// the (hoisted) `vi.mock` factories — mirroring llm-client.test.ts.
const mocks = vi.hoisted(() => ({
  reviewFile: vi.fn(),
  emits: [] as Array<Record<string, unknown>>,
}));

vi.mock("./llm-client", () => ({
  createLlmClient: () => ({ reviewFile: mocks.reviewFile }),
}));

// Capture every transport.emit — `review:file` (from the reviewer) and
// `review:summary` (from the aggregator) — so we can assert on wire events.
vi.mock("../ipc/transport", () => ({
  transport: {
    emit: async (e: Record<string, unknown>): Promise<void> => {
      mocks.emits.push(e);
    },
  },
}));

import { reviewPR } from "./reviewer";
import { parseDiffHunks } from "../linemap/diff-parser";
import { mapFindings } from "../linemap/diff-line-mapper";

// `createLlmClient` is mocked; only these config fields could be read by the
// reviewer path, and none matter once the client is stubbed.
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
    reviewMode: "auto",
    reviewRules: "",
    dbPath: "/tmp/reviews.db",
    logDir: "/tmp/logs",
    ...overrides,
  } as Config;
}

function makeCtx(
  diff: string,
  files: Record<string, string>,
  overrides: Partial<ReviewContext> = {},
): ReviewContext {
  return {
    prId: 1,
    number: 42,
    repo: "owner/repo",
    title: "Fix bug",
    body: "does a thing",
    author: "octocat",
    headSha: "abc",
    baseSha: "def",
    url: "https://github.com/owner/repo/pull/42",
    diff,
    files,
    reviewRules: "",
    ...overrides,
  };
}

/** A `@@` hunk whose body has exactly `n` added lines, starting at new-side line `newStart`. */
function hunk(newStart: number, n: number): string {
  const body = Array.from({ length: n }, (_, i) => `+line ${newStart + i}`).join("\n");
  return `@@ -1,1 +${newStart},${n} @@\n${body}`;
}

/** Wrap per-file hunks into a full PR diff for `file` (diff --git / --- / +++ headers included). */
function fileDiff(file: string, hunks: string[]): string {
  return `diff --git a/${file} b/${file}\nindex abc..def 100644\n--- a/${file}\n+++ b/${file}\n${hunks.join("\n")}`;
}

/** Build a typed finding on `file`. */
function mkFinding(
  file: string,
  line: number | null,
  comment: string,
  severity: Severity = "high",
): Finding {
  return { file, line, severity, area: "bug", comment };
}

/** Wrap findings as a per-chunk LLM review. */
function review(findings: Finding[], summary = "chunk summary"): LlmFileReview {
  return { findings, summary };
}

/** `review:file` events captured on the (mocked) transport. */
function fileEvents(): Array<Record<string, unknown>> {
  return mocks.emits.filter((e) => e.event === "review:file");
}

describe("reviewer — chunked file review (F2)", () => {
  beforeEach(() => {
    mocks.reviewFile.mockReset();
    mocks.emits.length = 0;
  });

  it("(a) single-chunk ≤500 diff lines: one reviewFile call, one review:file emit, full content + whole diffHunks (== today)", async () => {
    const FILE = "src/app.ts";
    const content = "import foo from 'bar';\n";
    const diff = fileDiff(FILE, [hunk(1, 3)]);
    const ctx = makeCtx(diff, { [FILE]: content });

    mocks.reviewFile.mockResolvedValue(review([mkFinding(FILE, 2, "nit")]));

    const result = await reviewPR(ctx, makeConfig());

    // Exactly ONE LLM call — fast path identical to today.
    expect(mocks.reviewFile).toHaveBeenCalledTimes(1);
    const [f, c, dh, , , rules] = mocks.reviewFile.mock.calls[0];
    expect(f).toBe(FILE);
    expect(c).toBe(content); // FULL content
    expect(dh).toContain("@@ -1,1 +1,3 @@"); // whole diffHunks (not chunked)
    expect(rules).toBe(""); // rules forwarded (empty here ⇒ byte-identical)

    // Exactly ONE review:file emit.
    const evts = fileEvents();
    expect(evts).toHaveLength(1);
    expect(evts[0]).toMatchObject({
      event: "review:file",
      file: FILE,
      status: "findings",
      findings: 1,
    });

    expect(result.findings).toHaveLength(1);
    expect(result.findings[0].line).toBe(2);
  });

  it("(b) multi-chunk >500 diff lines: N calls, one review:file emit, merged findings, rules + full content on EVERY call", async () => {
    const FILE = "src/big.ts";
    const content = "x".repeat(50);
    // 2 hunks × 300 lines = 600 > 500 ⇒ 2 chunks.
    const diff = fileDiff(FILE, [hunk(1, 300), hunk(500, 300)]);
    const ctx = makeCtx(diff, { [FILE]: content }, { reviewRules: "RULES-X" });

    mocks.reviewFile
      .mockResolvedValueOnce(review([mkFinding(FILE, 50, "issue at 50")]))
      .mockResolvedValueOnce(review([mkFinding(FILE, 550, "issue at 550")]));

    const result = await reviewPR(ctx, makeConfig());

    // Two LLM calls — one per chunk.
    expect(mocks.reviewFile).toHaveBeenCalledTimes(2);
    // FULL content + rules forwarded to EVERY call.
    for (const call of mocks.reviewFile.mock.calls) {
      expect(call[1]).toBe(content); // full content (not empty, not chunk-scoped)
      expect(call[5]).toBe("RULES-X"); // rules forwarded
    }
    // Each call receives its own @@-scoped chunk of the diff.
    expect(mocks.reviewFile.mock.calls[0][2]).toContain("+1,300 @@");
    expect(mocks.reviewFile.mock.calls[0][2]).not.toContain("+500,300 @@");
    expect(mocks.reviewFile.mock.calls[1][2]).toContain("+500,300 @@");

    // Exactly ONE review:file emit with the MERGED finding count.
    const evts = fileEvents();
    expect(evts).toHaveLength(1);
    expect(evts[0]).toMatchObject({
      event: "review:file",
      file: FILE,
      status: "findings",
      findings: 2,
    });

    expect(result.findings).toHaveLength(2);
  });

  it("(c) dedupes overlapping findings across chunks (high beats medium ⇒ one finding, severity high)", async () => {
    const FILE = "src/dup.ts";
    const content = "content";
    const diff = fileDiff(FILE, [hunk(1, 300), hunk(500, 300)]); // 2 chunks
    const ctx = makeCtx(diff, { [FILE]: content });

    // Both chunks emit the SAME finding key (file|line|comment); severities differ.
    mocks.reviewFile
      .mockResolvedValueOnce(review([mkFinding(FILE, 50, "same comment", "high")]))
      .mockResolvedValueOnce(review([mkFinding(FILE, 50, "same comment", "medium")]));

    const result = await reviewPR(ctx, makeConfig());

    expect(mocks.reviewFile).toHaveBeenCalledTimes(2);
    expect(result.findings).toHaveLength(1); // deduped to one
    expect(result.findings[0].severity).toBe("high"); // highest severity wins
    expect(result.findings[0].comment).toBe("same comment");
    expect(result.findings[0].line).toBe(50);

    const evts = fileEvents();
    expect(evts).toHaveLength(1);
    expect(evts[0]).toMatchObject({ findings: 1 });
  });

  it("(d1) partial chunk failure: file still reviewed with surviving chunks' merged findings (status findings, not error)", async () => {
    const FILE = "src/partial.ts";
    const content = "content";
    const diff = fileDiff(FILE, [hunk(1, 300), hunk(500, 300)]); // 2 chunks
    const ctx = makeCtx(diff, { [FILE]: content });

    // Chunk 0 throws; chunk 1 succeeds.
    mocks.reviewFile
      .mockRejectedValueOnce(new Error("chunk 0 boom"))
      .mockResolvedValueOnce(review([mkFinding(FILE, 550, "survived")]));

    const result = await reviewPR(ctx, makeConfig());

    expect(mocks.reviewFile).toHaveBeenCalledTimes(2); // both chunks attempted
    const evts = fileEvents();
    expect(evts).toHaveLength(1);
    expect(evts[0]).toMatchObject({ file: FILE, status: "findings", findings: 1 });
    expect(result.findings).toHaveLength(1);
    expect(result.findings[0].line).toBe(550);
  });

  it("(d2) total chunk failure: review:file status error and the file is skipped (no findings)", async () => {
    const FILE = "src/total.ts";
    const content = "content";
    const diff = fileDiff(FILE, [hunk(1, 300), hunk(500, 300)]); // 2 chunks
    const ctx = makeCtx(diff, { [FILE]: content });

    mocks.reviewFile.mockRejectedValue(new Error("all boom"));

    const result = await reviewPR(ctx, makeConfig());

    expect(mocks.reviewFile).toHaveBeenCalledTimes(2); // both chunks attempted
    const evts = fileEvents();
    expect(evts).toHaveLength(1);
    expect(evts[0]).toMatchObject({ file: FILE, status: "error", findings: 0 });
    expect(result.findings).toEqual([]); // file skipped (R19)
  });

  it("(e) line-map non-regression: chunked findings classify inline/degraded identically to a single-call baseline", async () => {
    const FILE = "src/lmap.ts";
    const content = "content";
    // 3 hunks × 300 lines = 900 ⇒ 3 chunks. New-side ranges: 1-300, 400-699, 800-1099.
    const diff = fileDiff(FILE, [hunk(1, 300), hunk(400, 300), hunk(800, 300)]);
    const ctx = makeCtx(diff, { [FILE]: content });

    // chunk0 (1-300)   → line 100  (valid new-side line)
    // chunk1 (400-699) → line 450  (valid new-side line)
    // chunk2 (800+)    → line 9999 (out of range ⇒ degraded)
    mocks.reviewFile
      .mockResolvedValueOnce(review([mkFinding(FILE, 100, "valid in hunk0")]))
      .mockResolvedValueOnce(review([mkFinding(FILE, 450, "valid in hunk1")]))
      .mockResolvedValueOnce(review([mkFinding(FILE, 9999, "out of range")]));

    const result = await reviewPR(ctx, makeConfig());

    expect(mocks.reviewFile).toHaveBeenCalledTimes(3);
    expect(result.findings).toHaveLength(3);

    // Line-map the MERGED findings against the WHOLE diff — exactly as the
    // orchestrator does (parseDiffHunks runs on the original, unchunked diff).
    const validLines = parseDiffHunks(diff);
    const { inline, degraded } = mapFindings(validLines, result.findings);

    const inlineLines = new Set(inline.map((f) => f.line));
    expect(inlineLines.has(100)).toBe(true);
    expect(inlineLines.has(450)).toBe(true);
    expect(inlineLines.size).toBe(2);
    const degradedLines = new Set(degraded.map((f) => f.line));
    expect(degradedLines.has(9999)).toBe(true);
    expect(degradedLines.size).toBe(1);

    // Baseline: the SAME classification holds for an equivalent single-call
    // finding set — line mapping is a pure function of (wholeDiff, findings),
    // independent of how chunks carved the diff.
    const baseline = mapFindings(validLines, [
      mkFinding(FILE, 100, "x"),
      mkFinding(FILE, 450, "y"),
      mkFinding(FILE, 9999, "z"),
    ]);
    expect(baseline.inline.length).toBe(inline.length);
    expect(baseline.degraded.length).toBe(degraded.length);
  });
});
