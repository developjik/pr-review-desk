/**
 * Pure unified-diff row parser for the pending diff viewer.
 *
 * Mirrors the @@-semantics of `daemon/src/linemap/diff-parser.ts#parseDiffHunks`:
 * context lines (` ` prefix) and added lines (`+` prefix) are commentable and
 * carry/advance the new-side line number; removed lines (`-` prefix) have no
 * new-side line. This module reuses that exact line-counting logic but returns
 * structured rows (for rendering) plus a locate helper (to highlight a finding's
 * line), so a finding's absolute new-side line maps to the correct rendered row.
 *
 * No node deps — pure, vitest-testable, shared by daemon + host.
 */

/** A single classified row of a diff hunk. */
export interface HunkRow {
  type: "ctx" | "add" | "del" | "meta";
  text: string;
  /** New-side line number, or null for removed/metadata rows. */
  newLine: number | null;
}

/** Hunk header regex, capturing the new-side start line (group 1). Identical to
 * the one in daemon/src/linemap/diff-parser.ts#parseDiffHunks. */
const HUNK_HEADER = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/;

/**
 * Parse a single hunk (or a raw multi-file diff string) into classified rows.
 *
 * Classification is META-FIRST (defense-in-depth, load-bearing): metadata lines
 * are matched BEFORE the single-char branches, so a stray `+++` / `---` /
 * `diff --git` is never misclassified as an added/removed line that would shift
 * the new-side numbering of subsequent rows.
 *
 * Order of checks:
 *   1. `@@ -a,b +START,c @@` → meta; capture START as the new-side line.
 *   2. `+++ ...` / `--- ...`  → meta (file headers).
 *   3. `diff --git ...`       → meta (file boundary).
 *   4. `\ No newline at end of file` → meta.
 *   5. exactly `""` (blank line in the split) → meta/blank, no increment.
 * Then, for the remaining lines:
 *   - ` ` (space prefix) → ctx: assign current newLine, then increment.
 *   - `+`                → add: assign current newLine, then increment.
 *   - `-`                → del: newLine null, no increment.
 *   - anything else      → meta, no increment (e.g. `index abc..def`).
 *
 * @returns the rows in order; `newLine` is the new-side line number or null.
 */
export function parseHunkRows(hunk: string): HunkRow[] {
  const rows: HunkRow[] = [];
  let newLine = 0;

  for (const text of hunk.split("\n")) {
    // (1) Hunk header: capture the new-side start line, exactly like parseDiffHunks.
    const hunkMatch = text.match(HUNK_HEADER);
    if (hunkMatch) {
      newLine = parseInt(hunkMatch[1], 10);
      rows.push({ type: "meta", text, newLine: null });
      continue;
    }

    // (2) File headers: +++ b/... (or +++ /dev/null) and --- a/...
    if (text.startsWith("+++") || text.startsWith("---")) {
      rows.push({ type: "meta", text, newLine: null });
      continue;
    }

    // (3) File boundary.
    if (text.startsWith("diff --git")) {
      rows.push({ type: "meta", text, newLine: null });
      continue;
    }

    // (4) "\ No newline at end of file" marker.
    if (text.startsWith("\\")) {
      rows.push({ type: "meta", text, newLine: null });
      continue;
    }

    // (5) Exactly empty string (a blank line in the split) — meta/blank, no increment.
    if (text === "") {
      rows.push({ type: "meta", text, newLine: null });
      continue;
    }

    // Context line (space prefix) — commentable.
    if (text.startsWith(" ")) {
      rows.push({ type: "ctx", text, newLine });
      newLine++;
      continue;
    }

    // Added line (+ prefix) — commentable.
    if (text.startsWith("+")) {
      rows.push({ type: "add", text, newLine });
      newLine++;
      continue;
    }

    // Removed line (- prefix) — NOT commentable; does not increment new-side line.
    if (text.startsWith("-")) {
      rows.push({ type: "del", text, newLine: null });
      continue;
    }

    // Any other line (e.g. `index abc..def`, `new file mode 100644`) — metadata.
    rows.push({ type: "meta", text, newLine: null });
  }

  return rows;
}

/**
 * Find the index of the first row whose new-side line equals `targetLine`.
 *
 * @returns the matching row index, or null when the hunk is undefined/empty,
 *   `targetLine` is null, or no row carries that new-side line.
 */
export function locateDiffLine(
  hunk: string | undefined,
  targetLine: number | null,
): number | null {
  if (!hunk || targetLine === null) {
    return null;
  }
  const rows = parseHunkRows(hunk);
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].newLine === targetLine) {
      return i;
    }
  }
  return null;
}
