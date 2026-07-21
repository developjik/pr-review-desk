import { describe, it, expect } from "vitest";
import { parseHunkRows, locateDiffLine } from "./diff-view";
import type { HunkRow } from "./diff-view";

// Mirrors the fixture in daemon/src/linemap/diff-line-mapper.test.ts.
//   @@ -1,3 +1,4 @@
//    unchanged        -> new-side 1 (ctx)
//   -removed line     -> null (del, no increment)
//   +added line one   -> new-side 2 (add)
//   +added line two   -> new-side 3 (add)
//    unchanged two    -> new-side 4 (ctx)
const HUNK_BODY = [
  "@@ -1,3 +1,4 @@",
  " unchanged",
  "-removed line",
  "+added line one",
  "+added line two",
  " unchanged two",
].join("\n");

// A raw multi-file diff (metadata + hunks) to exercise the meta-first guard:
// a stray `+++`/`---`/`diff --git` must NOT be misclassified as an added line.
const RAW_MULTIFILE = [
  "diff --git a/src/foo.ts b/src/foo.ts",
  "index abc..def 100644",
  "--- a/src/foo.ts",
  "+++ b/src/foo.ts",
  "@@ -1,2 +1,3 @@",
  " keep",
  "+added foo",
  "diff --git a/src/bar.ts b/src/bar.ts",
  "index 111..222 100644",
  "--- a/src/bar.ts",
  "+++ b/src/bar.ts",
  "@@ -10,2 +10,3 @@",
  " keep bar",
  "+added bar",
].join("\n");

function row(
  type: HunkRow["type"],
  text: string,
  newLine: number | null,
): HunkRow {
  return { type, text, newLine };
}

describe("parseHunkRows", () => {
  it("classifies and numbers context and added lines", () => {
    expect(parseHunkRows(HUNK_BODY)).toEqual([
      row("meta", "@@ -1,3 +1,4 @@", null),
      row("ctx", " unchanged", 1),
      row("del", "-removed line", null),
      row("add", "+added line one", 2),
      row("add", "+added line two", 3),
      row("ctx", " unchanged two", 4),
    ]);
  });

  it("treats removed lines as null without incrementing the new-side line", () => {
    const rows = parseHunkRows(HUNK_BODY);
    const removed = rows.find((r) => r.type === "del");
    expect(removed!.newLine).toBeNull();
    // The line following the removed line is an add at new-side 2 (NOT 1),
    // proving the removed line did not consume/shift a number.
    const next = rows[rows.indexOf(removed!) + 1];
    expect(next).toEqual(row("add", "+added line one", 2));
  });

  it("resets the new-side line at each @@ hunk header", () => {
    const diff = [
      "@@ -1,2 +1,3 @@",
      " ctx",
      "+add1",
      "@@ -10,2 +10,3 @@",
      " ctx2",
      "+add2",
    ].join("\n");
    // newLine sequence: [meta null, ctx 1, add 2, meta null, ctx 10, add 11]
    expect(parseHunkRows(diff).map((r) => r.newLine)).toEqual([
      null,
      1,
      2,
      null,
      10,
      11,
    ]);
  });

  it("classifies metadata lines (diff --git / --- / +++) as meta with null newLine", () => {
    const metaByText = Object.fromEntries(
      parseHunkRows(RAW_MULTIFILE)
        .filter((r) => r.type === "meta")
        .map((r) => [r.text, r.newLine]),
    );
    expect(metaByText["diff --git a/src/foo.ts b/src/foo.ts"]).toBeNull();
    expect(metaByText["--- a/src/foo.ts"]).toBeNull();
    expect(metaByText["+++ b/src/foo.ts"]).toBeNull();
    expect(metaByText["diff --git a/src/bar.ts b/src/bar.ts"]).toBeNull();
    expect(metaByText["+++ b/src/bar.ts"]).toBeNull();
  });

  it("does NOT let a stray +++ shift new-side numbering (meta-first guard)", () => {
    const rows = parseHunkRows(RAW_MULTIFILE);
    // The second file's stray `+++ b/src/bar.ts` must be meta (null), not add.
    const strayPlusPlus = rows.find((r) => r.text === "+++ b/src/bar.ts");
    expect(strayPlusPlus!.type).toBe("meta");
    expect(strayPlusPlus!.newLine).toBeNull();
    // foo: keep -> 1, added foo -> 2 ; bar: keep bar -> 10, added bar -> 11.
    expect(rows.find((r) => r.text === " keep")!.newLine).toBe(1);
    expect(rows.find((r) => r.text === "+added foo")!.newLine).toBe(2);
    expect(rows.find((r) => r.text === " keep bar")!.newLine).toBe(10);
    expect(rows.find((r) => r.text === "+added bar")!.newLine).toBe(11);
  });

  it("classifies the \\ No newline marker as meta without shifting numbering", () => {
    const diff = [
      "@@ -1,1 +1,1 @@",
      " last",
      "\\ No newline at end of file",
    ].join("\n");
    expect(parseHunkRows(diff)).toEqual([
      row("meta", "@@ -1,1 +1,1 @@", null),
      row("ctx", " last", 1),
      row("meta", "\\ No newline at end of file", null),
    ]);
  });

  it("parses an empty hunk string as a single blank meta row", () => {
    expect(parseHunkRows("")).toEqual([row("meta", "", null)]);
  });
});

describe("locateDiffLine", () => {
  it("locates a context-line target", () => {
    // " unchanged" -> newLine 1 at row index 1
    expect(locateDiffLine(HUNK_BODY, 1)).toBe(1);
  });

  it("locates an added-line target", () => {
    // "+added line two" -> newLine 3 at row index 4
    expect(locateDiffLine(HUNK_BODY, 3)).toBe(4);
  });

  it("returns null for an out-of-range target line (miss)", () => {
    expect(locateDiffLine(HUNK_BODY, 999)).toBeNull();
  });

  it("returns null for a null target line", () => {
    expect(locateDiffLine(HUNK_BODY, null)).toBeNull();
  });

  it("returns null for an undefined hunk", () => {
    expect(locateDiffLine(undefined, 5)).toBeNull();
  });

  it("returns null for an empty hunk string", () => {
    expect(locateDiffLine("", 5)).toBeNull();
  });

  it("returns the FIRST matching row when a line number repeats across hunks", () => {
    const diff = [
      "@@ -1,1 +1,1 @@",
      " ctx", // newLine 1 (index 1)
      "@@ -1,1 +1,1 @@",
      " ctx2", // newLine 1 again (index 4)
    ].join("\n");
    expect(locateDiffLine(diff, 1)).toBe(1);
  });
});
