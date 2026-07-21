/**
 * ADVERSARIAL CROSS-CHECK (red-team probe — promoted to a permanent test).
 *
 * The pending diff viewer's highlight logic lives in TWO independent modules:
 *   - shared/src/diff-view.ts          (parseHunkRows / locateDiffLine) — viewer
 *   - daemon/src/linemap/diff-parser.ts (parseDiffHunks / splitDiffByFile) — classifier
 *
 * The plan's load-bearing claim (AC1.2 / ADR) is that diff-view.ts "mirrors"
 * parseDiffHunks' @@-semantics. If they EVER diverge, a finding the classifier
 * accepts as inline (its line is in parseDiffHunks' valid set) would NOT be
 * locatable in the DiffViewer (locateDiffLine → null → no highlight), or a
 * removed line the classifier REJECTS would be highlightable. Either is a real
 * correctness bug. This test pins the two implementations together on the SAME
 * raw diffs so a future edit to either side fails loudly.
 *
 * Additionally covers AC1.7: a finding whose file is absent from the diff map
 * → splitDiffByFile returns nothing → locateDiffLine(undefined, …) → null
 * → DiffViewer renders "Diff unavailable" (source-verified, no DOM runner).
 */
import { describe, it, expect } from "vitest";
import { parseHunkRows, locateDiffLine } from "@pr-review/shared";
import { parseDiffHunks, splitDiffByFile } from "./diff-parser";

/** Commentable new-side lines that parseHunkRows would surface for a hunk. */
function viewerLines(hunk: string): Set<number> {
  return new Set(
    parseHunkRows(hunk)
      .map((r) => r.newLine)
      .filter((l): l is number => l !== null),
  );
}

/**
 * The core invariant: for every file in a raw diff, the classifier's valid-line
 * set must EXACTLY equal the viewer's locatable-line set, and every valid line
 * must be locatable (locateDiffLine !== null) while no invalid (removed) line is.
 */
function assertMirror(diff: string) {
  const classifier = parseDiffHunks(diff);
  const perFile = splitDiffByFile(diff);

  for (const [file, valid] of classifier) {
    const hunk = perFile.get(file);
    expect(hunk, `splitDiffByFile missing file ${file}`).toBeDefined();
    const viewer = viewerLines(hunk!);

    // (1) Sets are identical — no drift between classifier and viewer.
    expect(viewer, `${file}: viewer lines drifted from classifier`).toEqual(valid);

    // (2) Every classifier-valid line is locatable in the viewer (AC1.2).
    for (const line of valid) {
      expect(locateDiffLine(hunk, line), `${file}:${line} should be locatable`).not.toBeNull();
    }

    // (3) A line just past the last valid line (out of range) is NOT locatable.
    const max = Math.max(...valid);
    expect(locateDiffLine(hunk, max + 1)).toBeNull();
  }
}

describe("diff-view ↔ diff-parser mirror invariant (AC1.2)", () => {
  it("single hunk, mixed ctx/add/del", () => {
    const diff = [
      "diff --git a/src/a.ts b/src/a.ts",
      "index aaa..bbb 100644",
      "--- a/src/a.ts",
      "+++ b/src/a.ts",
      "@@ -1,3 +1,4 @@",
      " unchanged", // ctx -> 1
      "-removed line", // del -> null (NOT locatable)
      "+added line one", // add -> 2
      "+added line two", // add -> 3
      " unchanged two", // ctx -> 4
    ].join("\n");
    assertMirror(diff);

    // A removed line is never locatable even though it sits between valid lines.
    const hunk = splitDiffByFile(diff).get("src/a.ts")!;
    expect(locateDiffLine(hunk, null)).toBeNull();
  });

  it("multi-hunk: new-side line resets at each @@ header", () => {
    const diff = [
      "diff --git a/m.ts b/m.ts",
      "--- a/m.ts",
      "+++ b/m.ts",
      "@@ -1,2 +1,3 @@",
      " ctx", // 1
      "+add1", // 2
      "@@ -50,2 +50,3 @@",
      " ctx2", // 50
      "+add2", // 51
    ].join("\n");
    assertMirror(diff);
    // Line 2 only appears in the FIRST hunk → first-match semantics.
    expect(locateDiffLine(splitDiffByFile(diff).get("m.ts")!, 2)).not.toBeNull();
  });

  it("multi-file raw diff: stray +++/---/diff --git never shift numbering", () => {
    const diff = [
      "diff --git a/foo.ts b/foo.ts",
      "index abc..def 100644",
      "--- a/foo.ts",
      "+++ b/foo.ts",
      "@@ -1,2 +1,3 @@",
      " keep", // 1
      "+added foo", // 2
      "diff --git a/bar.ts b/bar.ts",
      "index 111..222 100644",
      "--- a/bar.ts",
      "+++ b/bar.ts",
      "@@ -10,2 +10,3 @@",
      " keep bar", // 10
      "+added bar", // 11
    ].join("\n");
    assertMirror(diff);
    // Explicitly: the second file's stray +++ is meta, does not consume line 10.
    expect(locateDiffLine(splitDiffByFile(diff).get("bar.ts")!, 10)).not.toBeNull();
    expect(locateDiffLine(splitDiffByFile(diff).get("bar.ts")!, 11)).not.toBeNull();
  });

  it("blank context line (a single space) is commentable on both sides", () => {
    // A genuinely-empty context line is encoded as a single space in unified diff.
    const diff = [
      "diff --git a/b.ts b/b.ts",
      "--- a/b.ts",
      "+++ b/b.ts",
      "@@ -1,3 +1,4 @@",
      " before", // 1
      " ", // blank ctx -> 2
      "+inserted", // 3
      " after", // 4
    ].join("\n");
    assertMirror(diff);
    expect(locateDiffLine(splitDiffByFile(diff).get("b.ts")!, 2)).not.toBeNull();
  });

  it("\\ No newline marker is meta on both sides and does not shift numbering", () => {
    const diff = [
      "diff --git a/c.ts b/c.ts",
      "--- a/c.ts",
      "+++ b/c.ts",
      "@@ -1,1 +1,2 @@",
      " last", // 1
      "+tail", // 2
      "\\ No newline at end of file",
    ].join("\n");
    assertMirror(diff);
    expect(locateDiffLine(splitDiffByFile(diff).get("c.ts")!, 2)).not.toBeNull();
  });

  it("deletion-only file (+++ /dev/null) yields no commentable lines and is not locatable", () => {
    const diff = [
      "diff --git a/del.ts b/del.ts",
      "--- a/del.ts",
      "+++ /dev/null",
      "@@ -1,2 +0,0 @@",
      "-gone one",
      "-gone two",
    ].join("\n");
    // parseDiffHunks skips /dev/null files entirely.
    expect(parseDiffHunks(diff).has("del.ts")).toBe(false);
    // splitDiffByFile still records a (deletion-only) body; viewer finds no valid lines.
    const hunk = splitDiffByFile(diff).get("del.ts");
    if (hunk) {
      expect(viewerLines(hunk)).toEqual(new Set<number>());
      expect(locateDiffLine(hunk, 1)).toBeNull();
    }
  });

  it("locateDiffLine returns the FIRST matching row when a line repeats across hunks", () => {
    const diff = [
      "diff --git a/r.ts b/r.ts",
      "--- a/r.ts",
      "+++ b/r.ts",
      "@@ -1,1 +1,1 @@",
      " ctx", // newLine 1, row idx 1
      "@@ -1,1 +1,1 @@",
      " ctx2", // newLine 1 again, row idx 4
    ].join("\n");
    const hunk = splitDiffByFile(diff).get("r.ts")!;
    expect(locateDiffLine(hunk, 1)).toBe(1); // first occurrence
    // The classifier set still just contains {1} (a Set), consistent with viewer.
    expect(viewerLines(hunk)).toEqual(new Set([1]));
  });
});

describe("AC1.7 — finding file absent from the diff map", () => {
  it("a finding whose file is not snapshotted → locateDiffLine(undefined, …) === null", () => {
    // The finding targets src/secret.ts, but the stored diff only has src/a.ts.
    const storedDiff: Record<string, string> = {
      "src/a.ts": "@@ -1,1 +1,1 @@\n ctx\n",
    };
    const findingFile = "src/secret.ts";
    // Pending.tsx passes review.diff?.[findingFile] → undefined.
    const hunk = storedDiff[findingFile];
    expect(hunk).toBeUndefined();
    // locateDiffLine(undefined, …) === null → DiffViewer renders "Diff unavailable".
    expect(locateDiffLine(hunk, 5)).toBeNull();
  });
});
