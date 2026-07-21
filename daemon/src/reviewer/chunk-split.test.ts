import { describe, it, expect } from "vitest";
import { splitFileIntoChunks, mergeChunkResults, SEVERITY_RANK } from "./chunk-split";
import { countDiffLines } from "./chunker";
import type { Finding, Severity } from "../types/domain";
import type { LlmFileReview } from "./llm-client";

/** A single `@@` hunk whose body has exactly `n` counted diff lines. */
function hunk(newStart: number, n: number): string {
  const body = Array.from({ length: n }, () => "+x").join("\n");
  return `@@ -1,1 +${newStart},${n} @@\n${body}`;
}

/** Join hunks back into one per-file diff. */
const diffOf = (...hunks: string[]): string => hunks.join("\n");

describe("splitFileIntoChunks", () => {
  it("returns exactly one chunk for a single-hunk ≤500-line diff", () => {
    const chunks = splitFileIntoChunks(hunk(1, 100), 500);
    expect(chunks).toHaveLength(1);
    expect(countDiffLines(chunks[0])).toBe(100);
  });

  it("packs multiple small hunks totaling ≤500 lines into one chunk", () => {
    const diff = diffOf(hunk(1, 100), hunk(200, 100), hunk(400, 100)); // 300 total
    const chunks = splitFileIntoChunks(diff, 500);
    expect(chunks).toHaveLength(1);
    expect(countDiffLines(chunks[0])).toBe(300);
  });

  it("splits a multi-hunk >500-line diff into ≥2 chunks, each ≤500 lines", () => {
    const diff = diffOf(hunk(1, 150), hunk(200, 150), hunk(400, 150), hunk(600, 150)); // 600
    const chunks = splitFileIntoChunks(diff, 500);
    expect(chunks.length).toBeGreaterThanOrEqual(2);
    for (const c of chunks) {
      expect(countDiffLines(c)).toBeLessThanOrEqual(500);
    }
  });

  it("makes a single oversized hunk its own chunk (never split mid-hunk)", () => {
    const diff = diffOf(hunk(1, 600), hunk(700, 10)); // hunk0 alone > budget
    const chunks = splitFileIntoChunks(diff, 500);
    // The 600-line oversized hunk must survive intact as one chunk.
    expect(chunks.some((c) => countDiffLines(c) === 600)).toBe(true);
    // Every chunk is either within budget or the lone oversized hunk.
    for (const c of chunks) {
      const n = countDiffLines(c);
      expect(n <= 500 || n === 600).toBe(true);
    }
  });

  it("never splits mid-hunk: every chunk starts with a @@ header and headers are preserved", () => {
    const diff = diffOf(hunk(1, 200), hunk(300, 200), hunk(600, 200)); // 3 hunks, 600 lines
    const chunks = splitFileIntoChunks(diff, 500);

    const originalHeaders = diff.match(/^@@/gm)?.length ?? 0;
    const chunkedHeaders = chunks.reduce(
      (n, c) => n + (c.match(/^@@/gm)?.length ?? 0),
      0,
    );
    expect(chunkedHeaders).toBe(originalHeaders); // no header dropped or duplicated
    for (const c of chunks) {
      expect(c.startsWith("@@")).toBe(true); // chunk never begins mid-hunk
    }
  });

  it("is deterministic (same input ⇒ same output across calls)", () => {
    const diff = diffOf(hunk(1, 200), hunk(300, 200), hunk(600, 200));
    expect(splitFileIntoChunks(diff, 500)).toEqual(splitFileIntoChunks(diff, 500));
  });

  it("preserves original hunk order (left→right)", () => {
    const diff = diffOf(hunk(1, 400), hunk(500, 400)); // 800, 2 chunks
    const chunks = splitFileIntoChunks(diff, 500);
    expect(chunks).toHaveLength(2);
    // First chunk holds the +1 hunk, second the +500 hunk.
    expect(chunks[0]).toContain("+1,400 @@");
    expect(chunks[1]).toContain("+500,400 @@");
    expect(chunks[0]).not.toContain("+500,400 @@");
  });

  it("returns [diffText] for empty input", () => {
    expect(splitFileIntoChunks("", 500)).toEqual([""]);
  });

  it("returns [diffText] for input with no @@ hunk header", () => {
    const text = "just some context lines\nwith no hunk header";
    expect(splitFileIntoChunks(text, 500)).toEqual([text]);
  });

  it("returns [diffText] when @@ appears only mid-content (no line starts with @@)", () => {
    const text = "blah @@ mid content";
    expect(splitFileIntoChunks(text, 500)).toEqual([text]);
  });
});

describe("SEVERITY_RANK", () => {
  it("ranks critical highest and info lowest", () => {
    expect(SEVERITY_RANK.info).toBe(0);
    expect(SEVERITY_RANK.low).toBe(1);
    expect(SEVERITY_RANK.medium).toBe(2);
    expect(SEVERITY_RANK.high).toBe(3);
    expect(SEVERITY_RANK.critical).toBe(4);
  });
});

describe("mergeChunkResults", () => {
  const finding = (
    severity: Severity,
    overrides: Partial<Finding> = {},
  ): Finding => ({
    file: "src/a.ts",
    line: 10,
    severity,
    area: "bug",
    comment: "same comment",
    ...overrides,
  });

  it("returns empty findings + summary for [] without throwing", () => {
    expect(mergeChunkResults([])).toEqual({ findings: [], summary: "" });
  });

  it("dedupes: high (chunk0) beats medium (chunk1) → one finding, severity high", () => {
    const results: LlmFileReview[] = [
      { findings: [finding("high")], summary: "s0" },
      { findings: [finding("medium")], summary: "s1" },
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings).toHaveLength(1);
    expect(merged.findings[0].severity).toBe("high");
  });

  it("dedupes: medium (chunk0) beats nothing — survives alongside a later high collision on the same key", () => {
    // Same key, chunk0 medium then chunk1 high: high wins.
    const results: LlmFileReview[] = [
      { findings: [finding("medium")], summary: "" },
      { findings: [finding("high")], summary: "" },
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings).toHaveLength(1);
    expect(merged.findings[0].severity).toBe("high");
  });

  it("tie on severity keeps the earliest chunk (winner = first seen)", () => {
    const results: LlmFileReview[] = [
      { findings: [finding("medium", { area: "bug" })], summary: "" },
      { findings: [finding("medium", { area: "style" })], summary: "" },
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings).toHaveLength(1);
    expect(merged.findings[0].area).toBe("bug"); // earliest chunk's area retained
  });

  it("keeps distinct findings separate (no over-dedup)", () => {
    const results: LlmFileReview[] = [
      {
        findings: [
          finding("low", { line: 1, comment: "c1" }),
          finding("low", { line: 2, comment: "c2" }),
        ],
        summary: "",
      },
    ];
    expect(mergeChunkResults(results).findings).toHaveLength(2);
  });

  it("collapses findings with null line under the same key", () => {
    const results: LlmFileReview[] = [
      { findings: [finding("low", { line: null })], summary: "" },
      { findings: [finding("high", { line: null })], summary: "" },
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings).toHaveLength(1);
    expect(merged.findings[0].severity).toBe("high");
  });

  it("suggestion = first non-empty across copies, even when the winner is a later chunk", () => {
    const results: LlmFileReview[] = [
      { findings: [finding("low", { suggestion: "fix A" })], summary: "" },
      { findings: [finding("high")], summary: "" }, // winner, no suggestion
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings).toHaveLength(1);
    expect(merged.findings[0].severity).toBe("high"); // winner
    expect(merged.findings[0].suggestion).toBe("fix A"); // first non-empty
  });

  it("suggestion picks the first non-empty even if a later copy also has one", () => {
    const results: LlmFileReview[] = [
      { findings: [finding("low", { suggestion: "first" })], summary: "" },
      { findings: [finding("high", { suggestion: "second" })], summary: "" },
    ];
    const merged = mergeChunkResults(results);
    expect(merged.findings[0].suggestion).toBe("first");
  });

  it("summary = results[0]?.summary", () => {
    const results: LlmFileReview[] = [
      { findings: [], summary: "first summary" },
      { findings: [], summary: "second summary" },
    ];
    expect(mergeChunkResults(results).summary).toBe("first summary");
  });

  it("summary is '' when the first result has no summary", () => {
    const results: LlmFileReview[] = [
      { findings: [], summary: "" },
      { findings: [], summary: "ignored" },
    ];
    expect(mergeChunkResults(results).summary).toBe("");
  });
});
