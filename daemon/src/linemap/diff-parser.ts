/**
 * Unified-diff parser.
 *
 * Extracts new-side line information from a GitHub unified diff so the
 * diff-line-mapper can classify findings as inline or degraded.
 *
 * Two exports:
 *   - {@link parseDiffHunks} — the set of commentable line numbers per file.
 *   - {@link splitDiffByFile} — the raw diff text per file (used by the
 *     chunker to count diff lines and by the reviewer to build the LLM prompt).
 *
 * Validated against the P0 spike (`spikes/review-line-map/diff-line-mapper.js`):
 * context lines (space prefix) and added lines (+ prefix) are commentable;
 * removed lines (- prefix) are NOT (they have no new-side line number).
 */

/**
 * Parse a unified diff and return the set of commentable (new-side) line
 * numbers for each file.
 *
 * A line is commentable when it exists on the new side of the diff — i.e.
 * context lines (` ` prefix) and added lines (`+` prefix). Removed lines
 * (`-` prefix) have no new-side equivalent and are excluded.
 *
 * @returns `Map<filePath, Set<lineNumber>>` — only files with a `+++ b/path`
 * header appear; deletions (`+++ /dev/null`) are skipped.
 */
export function parseDiffHunks(diff: string): Map<string, Set<number>> {
  const validLines = new Map<string, Set<number>>();
  let currentFile: string | null = null;
  let newLineNum = 0;

  for (const line of diff.split("\n")) {
    // File header: +++ b/path (or +++ /dev/null for deletions)
    if (line.startsWith("+++ ")) {
      const m = line.match(/^\+\+\+ b\/(.+)$/);
      if (m) {
        currentFile = m[1];
        validLines.set(currentFile, new Set());
      } else {
        currentFile = null; // /dev/null or unparseable — not a new-side file
      }
      continue;
    }

    // Hunk header: @@ -start,count +start,count @@
    const hunkMatch = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/);
    if (hunkMatch && currentFile) {
      newLineNum = parseInt(hunkMatch[1], 10);
      continue;
    }

    if (!currentFile) continue;

    // "\ No newline at end of file" marker — metadata, skip.
    if (line.startsWith("\\")) continue;

    // Context line (space prefix) — commentable.
    if (line.startsWith(" ")) {
      validLines.get(currentFile)!.add(newLineNum);
      newLineNum++;
      continue;
    }

    // Added line (+ prefix) — commentable. (The +++ header was handled above.)
    if (line.startsWith("+")) {
      validLines.get(currentFile)!.add(newLineNum);
      newLineNum++;
      continue;
    }

    // Removed line (- prefix) — NOT commentable; does not increment new-side
    // line number. The --- header is also caught here but is a no-op.
  }

  return validLines;
}

/**
 * Split a unified diff into per-file diff text.
 *
 * Returns the hunk body for each file (everything from the first `@@` header
 * onward, excluding the `diff --git` / `index` / `---` / `+++` metadata lines).
 * Used by the chunker to count diff lines and by the reviewer to pass diff
 * hunks to the LLM.
 *
 * @returns `Map<filePath, diffText>`
 */
export function splitDiffByFile(diff: string): Map<string, string> {
  const result = new Map<string, string>();
  let currentFile: string | null = null;
  const buffer: string[] = [];

  const flush = (): void => {
    if (currentFile !== null) {
      result.set(currentFile, buffer.join("\n"));
      buffer.length = 0;
      currentFile = null;
    }
  };

  for (const line of diff.split("\n")) {
    // `diff --git` marks the start of a new file section.
    if (line.startsWith("diff --git ")) {
      flush();
      continue;
    }
    const m = line.match(/^\+\+\+ b\/(.+)$/);
    if (m) {
      flush();
      currentFile = m[1];
      continue;
    }
    if (currentFile !== null) {
      buffer.push(line);
    }
  }
  flush();
  return result;
}
