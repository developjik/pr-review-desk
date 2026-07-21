import { describe, it, expect } from "vitest";
import { mapFindings } from "./diff-line-mapper";
import { parseDiffHunks } from "./diff-parser";
import type { Finding } from "../types/domain";

/**
 * A unified diff with a single hunk touching `src/foo.ts`.
 *
 *   @@ -1,3 +1,4 @@
 *    unchanged        -> new-side line 1
 *   -removed line     -> no new-side line (removed)
 *   +added line one   -> new-side line 2
 *   +added line two   -> new-side line 3
 *    unchanged two    -> new-side line 4
 */
const SAMPLE_DIFF = [
  "diff --git a/src/foo.ts b/src/foo.ts",
  "index abc..def 100644",
  "--- a/src/foo.ts",
  "+++ b/src/foo.ts",
  "@@ -1,3 +1,4 @@",
  " unchanged",
  "-removed line",
  "+added line one",
  "+added line two",
  " unchanged two",
].join("\n");

/** Minimal Finding factory — only `file` and `line` matter for classification. */
function makeFinding(file: string, line: number | null): Finding {
  return {
    file,
    line,
    severity: "medium",
    area: "bug",
    comment: "looks off",
  };
}

describe("parseDiffHunks", () => {
  it("extracts the new-side line numbers for a single hunk", () => {
    const valid = parseDiffHunks(SAMPLE_DIFF);
    // Context + added lines are commentable (1..4); the removed line is not.
    expect(valid.get("src/foo.ts")).toEqual(new Set([1, 2, 3, 4]));
    expect(valid.size).toBe(1);
  });

  it("tracks new-side line numbers across multiple hunks", () => {
    const diff = [
      "+++ b/src/bar.ts",
      "@@ -1,2 +1,3 @@",
      " ctx",
      "+add1",
      "@@ -10,2 +10,3 @@",
      " ctx2",
      "+add2",
    ].join("\n");
    const valid = parseDiffHunks(diff);
    expect(valid.get("src/bar.ts")).toEqual(new Set([1, 2, 10, 11]));
  });

  it("skips pure deletions (+++ /dev/null) entirely", () => {
    const diff = [
      "diff --git a/src/gone.ts b/src/gone.ts",
      "deleted file mode 100644",
      "--- a/src/gone.ts",
      "+++ /dev/null",
      "@@ -1,1 +0,0 @@",
      "-old line",
    ].join("\n");
    expect(parseDiffHunks(diff).size).toBe(0);
  });

  it("returns an empty map for an empty diff string", () => {
    expect(parseDiffHunks("").size).toBe(0);
  });
});

describe("mapFindings", () => {
  // src/foo.ts => {1, 2, 3, 4}
  const validLines = parseDiffHunks(SAMPLE_DIFF);

  it("classifies a finding on a valid new-side line as inline", () => {
    const { inline, degraded } = mapFindings(validLines, [
      makeFinding("src/foo.ts", 2),
    ]);
    expect(inline).toHaveLength(1);
    expect(degraded).toHaveLength(0);
  });

  it("classifies a finding whose line is outside the hunk as degraded", () => {
    const { inline, degraded } = mapFindings(validLines, [
      makeFinding("src/foo.ts", 999),
    ]);
    expect(inline).toHaveLength(0);
    expect(degraded).toHaveLength(1);
    expect(degraded[0].line).toBe(999);
  });

  it("classifies a finding with a null line as degraded", () => {
    const { inline, degraded } = mapFindings(validLines, [
      makeFinding("src/foo.ts", null),
    ]);
    expect(inline).toHaveLength(0);
    expect(degraded).toHaveLength(1);
    expect(degraded[0].line).toBeNull();
  });

  it("classifies a finding for a file absent from the diff as degraded", () => {
    const { inline, degraded } = mapFindings(validLines, [
      makeFinding("src/elsewhere.ts", 1),
    ]);
    expect(inline).toHaveLength(0);
    expect(degraded).toHaveLength(1);
    expect(degraded[0].file).toBe("src/elsewhere.ts");
  });

  it("splits a mixed batch into inline and degraded", () => {
    const findings = [
      makeFinding("src/foo.ts", 1), // inline
      makeFinding("src/foo.ts", 3), // inline
      makeFinding("src/foo.ts", 50), // degraded: line out of range
      makeFinding("src/foo.ts", null), // degraded: null line
      makeFinding("src/missing.ts", 1), // degraded: file missing
    ];
    const { inline, degraded } = mapFindings(validLines, findings);
    expect(inline).toHaveLength(2);
    expect(degraded).toHaveLength(3);
    expect(inline.map((f) => f.line)).toEqual([1, 3]);
    expect(degraded.map((f) => f.line)).toEqual([50, null, 1]);
  });

  it("returns empty inline and degraded for no findings", () => {
    const { inline, degraded } = mapFindings(validLines, []);
    expect(inline).toEqual([]);
    expect(degraded).toEqual([]);
  });
});
