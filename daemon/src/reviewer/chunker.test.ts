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
describe("chunkFiles — glob include/exclude (#7)", () => {
  it("AC7.1: fileInclude skips files not matching any include pattern", () => {
    const files = { "src/a.ts": "", "vendor/lib.js": "" };
    const diffs = new Map([
      ["src/a.ts", diffWithLines(1)],
      ["vendor/lib.js", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs, { fileInclude: "src/**" });
    expect(reviewable).toEqual(["src/a.ts"]);
    expect(reviewable).not.toContain("vendor/lib.js");
    const v = skipped.find((s) => s.file === "vendor/lib.js");
    expect(v).toBeDefined();
    expect(v!.reason).toContain("fileInclude");
  });

  it("AC7.2: fileExclude skips files matching an exclude pattern", () => {
    const files = { "x/y/gen.generated.ts": "", "src/a.ts": "" };
    const diffs = new Map([
      ["x/y/gen.generated.ts", diffWithLines(1)],
      ["src/a.ts", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs, { fileExclude: "**/*.generated.ts" });
    expect(reviewable).toEqual(["src/a.ts"]);
    expect(reviewable).not.toContain("x/y/gen.generated.ts");
    const g = skipped.find((s) => s.file === "x/y/gen.generated.ts");
    expect(g).toBeDefined();
    expect(g!.reason).toContain("fileExclude");
  });

  it("AC7.2b: fileExclude `**/*.ts` skips a ROOT-LEVEL file (M1 root-level fix)", () => {
    const files = { "app.ts": "", "README.md": "" };
    const diffs = new Map([
      ["app.ts", diffWithLines(1)],
      ["README.md", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs, { fileExclude: "**/*.ts" });
    expect(reviewable).toEqual(["README.md"]);
    expect(reviewable).not.toContain("app.ts");
    const app = skipped.find((s) => s.file === "app.ts");
    expect(app).toBeDefined();
    expect(app!.reason).toContain("fileExclude");
  });

  it("AC7.3: empty fileInclude/fileExclude ⇒ identical reviewable set to a no-opts call", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    for (const p of ["src/a.ts", "src/b.ts", "vendor/lib.js", "docs/c.md"]) {
      files[p] = "";
      diffs.set(p, diffWithLines(5));
    }

    const baseline = chunkFiles(files, diffs);
    const filtered = chunkFiles(files, diffs, { fileInclude: "", fileExclude: "" });
    expect([...filtered.reviewable].sort()).toEqual([...baseline.reviewable].sort());
    expect(filtered.skipped).toEqual(baseline.skipped);
  });

  it("AC7.4: globbed-out files are excluded BEFORE the file budget (60 files, 55 excluded, all 5 reviewed)", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    for (let i = 0; i < 55; i++) {
      const p = `docs/note${i}.md`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }
    for (let i = 0; i < 5; i++) {
      const p = `src/file${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }

    // 60 files total; default maxFiles=50. With fileExclude=`**/*.md`, the 55
    // .md files are excluded before the budget, leaving 5 ≤ 50 (no trim).
    const { reviewable, skipped } = chunkFiles(files, diffs, { fileExclude: "**/*.md" });
    expect(reviewable).toHaveLength(5);
    for (let i = 0; i < 5; i++) expect(reviewable).toContain(`src/file${i}.ts`);
    const excluded = skipped.filter((s) => s.reason.includes("fileExclude"));
    expect(excluded).toHaveLength(55);
    expect(skipped.some((s) => s.reason.includes("budget"))).toBe(false);
  });
});

describe("chunkFiles — diff threshold + budget config (#5)", () => {
  it("AC5.1: maxDiffLines=2000 skips a 2501-line diff file (reason cites 2501 > 2000)", () => {
    const files = { "src/big.ts": "", "src/ok.ts": "" };
    const diffs = new Map([
      ["src/big.ts", diffWithLines(2501)],
      ["src/ok.ts", diffWithLines(1)],
    ]);

    const { reviewable, skipped } = chunkFiles(files, diffs, { maxDiffLines: 2000 });
    expect(reviewable).toEqual(["src/ok.ts"]);
    const big = skipped.find((s) => s.file === "src/big.ts");
    expect(big).toBeDefined();
    expect(big!.reason).toContain("diff too large");
    expect(big!.reason).toContain("2501");
    expect(big!.reason).toContain("2000");
  });

  it("AC5.2: maxFiles=5 with 10 source files ⇒ 5 reviewed, 5 trimmed (reason cites budget)", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    for (let i = 0; i < 10; i++) {
      const p = `src/file${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }

    const { reviewable, skipped } = chunkFiles(files, diffs, { maxFiles: 5 });
    expect(reviewable).toHaveLength(5);
    expect(skipped).toHaveLength(5);
    expect(skipped.every((s) => s.reason.includes("budget"))).toBe(true);
    const all = new Set([...reviewable, ...skipped.map((s) => s.file)]);
    expect(all.size).toBe(10);
  });

  it('AC5.3: largePrPolicy="abort" + 6 files (maxFiles=5) ⇒ 0 reviewed, all 6 skipped (largePrPolicy=abort)', () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    for (let i = 0; i < 6; i++) {
      const p = `src/file${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(1));
    }

    const { reviewable, skipped } = chunkFiles(files, diffs, { maxFiles: 5, largePrPolicy: "abort" });
    expect(reviewable).toEqual([]);
    expect(skipped).toHaveLength(6);
    expect(skipped.every((s) => s.reason.includes("largePrPolicy=abort"))).toBe(true);
  });

  it("AC5.4: defaults (no opts) ⇒ identical to a call with all defaults explicit", () => {
    const files: Record<string, string> = {};
    const diffs = new Map<string, string>();
    for (let i = 0; i < 3; i++) {
      const p = `src/file${i}.ts`;
      files[p] = "";
      diffs.set(p, diffWithLines(10));
    }

    const baseline = chunkFiles(files, diffs);
    const explicit = chunkFiles(files, diffs, {
      maxDiffLines: 5000,
      maxFiles: 50,
      largePrPolicy: "trim",
      fileInclude: "",
      fileExclude: "",
    });
    expect([...explicit.reviewable].sort()).toEqual([...baseline.reviewable].sort());
    expect(explicit.skipped).toEqual(baseline.skipped);
  });
});
