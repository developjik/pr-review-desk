import { describe, it, expect } from "vitest";
import { chunkFiles, MAX_DIFF_LINES, MAX_FILES, ABSOLUTE_MAX_DIFF_LINES } from "./chunker";

/** A per-file diff body with exactly `n` added content lines. */
function diffWithLines(n: number): string {
  const added = Array.from({ length: n }, () => "+x").join("\n");
  return `@@ -1,1 +1,1 @@\n${added}`;
}

describe("chunkFiles", () => {
  it("skips a file whose diff exceeds ABSOLUTE_MAX_DIFF_LINES (5000)", () => {
    const files = { "src/big.ts": "", "src/ok.ts": "" };
    const diffs = new Map([
      ["src/big.ts", diffWithLines(ABSOLUTE_MAX_DIFF_LINES + 1)],
      ["src/ok.ts", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/ok.ts"]);
    expect(skipped).toHaveLength(1);
    expect(skipped[0].file).toBe("src/big.ts");
    expect(skipped[0].reason).toContain("diff too large");
    expect(skipped[0].reason).toContain(`${ABSOLUTE_MAX_DIFF_LINES + 1}`);
    expect(skipped[0].reason).toContain(`${ABSOLUTE_MAX_DIFF_LINES}`);
  });

  it("reviews a 600-line diff file (501–5000 are no longer skipped)", () => {
    const files = { "src/mid.ts": "", "src/ok.ts": "" };
    const diffs = new Map([
      ["src/mid.ts", diffWithLines(600)],
      ["src/ok.ts", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/mid.ts", "src/ok.ts"]);
    expect(skipped).toEqual([]);
  });

  it("reviews a file exactly at the ABSOLUTE_MAX_DIFF_LINES (5000) boundary", () => {
    const files = { "src/exact.ts": "" };
    const diffs = new Map([["src/exact.ts", diffWithLines(ABSOLUTE_MAX_DIFF_LINES)]]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/exact.ts"]);
    expect(skipped).toEqual([]);
  });

  it("never skips based on file content size (content is not consulted)", () => {
    const files = { "src/huge.ts": "x".repeat(500_000) };
    const diffs = new Map([["src/huge.ts", diffWithLines(1)]]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/huge.ts"]);
    expect(skipped).toEqual([]);
  });

  it("never skips based on file content emptiness (empty content + valid diff is reviewable)", () => {
    const files = { "src/empty.ts": "" };
    const diffs = new Map([["src/empty.ts", diffWithLines(5)]]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/empty.ts"]);
    expect(skipped).toEqual([]);
  });

  it("keeps a file exactly at the MAX_DIFF_LINES boundary", () => {
    const files = { "src/exact.ts": "" };
    const diffs = new Map([["src/exact.ts", diffWithLines(MAX_DIFF_LINES)]]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toEqual(["src/exact.ts"]);
    expect(skipped).toEqual([]);
  });

  it("trims test files first when exceeding MAX_FILES", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    // 50 source files (priority 0) + 1 test file (priority 3) = 51 total.
    for (let i = 0; i < MAX_FILES; i++) {
      const p = `src/file${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }
    const testFile = "src/app.test.ts";
    files[testFile] = "";
    diffs.set(testFile, diffWithLines(1));

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toHaveLength(MAX_FILES);
    expect(reviewable).not.toContain(testFile);
    expect(skipped).toHaveLength(1);
    expect(skipped[0].file).toBe(testFile);
    expect(skipped[0].reason).toContain("budget");
  });

  it("ranks source extensions higher than docs when trimming", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    // 49 source + 2 docs = 51 -> one doc trimmed, every source file kept.
    for (let i = 0; i < 49; i++) {
      const p = `src/mod${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }
    const doc1 = "docs/guide.md";
    const doc2 = "README.md";
    for (const d of [doc1, doc2]) {
      files[d] = "";
      diffs.set(d, diffWithLines(1));
    }

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toHaveLength(MAX_FILES);
    for (let i = 0; i < 49; i++) {
      expect(reviewable).toContain(`src/mod${i}.ts`);
    }
    expect(skipped).toHaveLength(1);
    expect([doc1, doc2]).toContain(skipped[0].file);
  });

  it("ranks test files lower than docs when trimming", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    // 49 source + 1 doc + 1 test = 51 -> test dropped, doc survives.
    for (let i = 0; i < 49; i++) {
      const p = `src/mod${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }
    const doc = "docs/guide.md";
    const testFile = "src/app.test.ts";
    for (const f of [doc, testFile]) {
      files[f] = "";
      diffs.set(f, diffWithLines(1));
    }

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect(reviewable).toHaveLength(MAX_FILES);
    expect(reviewable).toContain(doc);
    expect(skipped).toHaveLength(1);
    expect(skipped[0].file).toBe(testFile);
  });

  it("keeps all files when under both limits", () => {
    const files = {
      "src/a.ts": "",
      "src/b.ts": "",
      "docs/c.md": "",
    };
    const diffs = new Map([
      ["src/a.ts", diffWithLines(10)],
      ["src/b.ts", diffWithLines(20)],
      ["docs/c.md", diffWithLines(5)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs);
    expect([...reviewable].sort()).toEqual(["docs/c.md", "src/a.ts", "src/b.ts"]);
    expect(skipped).toEqual([]);
  });

  it("returns an empty reviewable set for an empty files map", () => {
    const { reviewable, skipped } = chunkFiles({}, new Map());
    expect(reviewable).toEqual([]);
    expect(skipped).toEqual([]);
  });
});
