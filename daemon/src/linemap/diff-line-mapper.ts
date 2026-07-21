/**
 * Diff-line-mapper — classify findings as inline or degraded.
 *
 * After the LLM produces findings with line numbers, this module checks each
 * finding's `(file, line)` against the set of commentable (new-side) lines
 * extracted from the diff by {@link parseDiffHunks}.
 *
 * Classification:
 *   - **inline**: the file exists in the diff AND the line number falls on a
 *     new-side diff line (context or added). These can be posted as inline PR
 *     review comments.
 *   - **degraded**: the file is absent from the diff, the line is null, or the
 *     line falls outside the diff hunks. These must be posted as a summary
 *     comment instead (GitHub rejects inline comments on non-diff lines with
 *     HTTP 422).
 *
 * This is the P0-validated pre-flight check that prevents 422 errors in the
 * Publisher (P5).
 */
import type { Finding } from "../types/domain";

export interface LineMapResult {
  /** Findings whose (file, line) fall on a new-side diff line. */
  inline: Finding[];
  /** Findings that cannot be posted inline (line outside diff or file missing). */
  degraded: Finding[];
}

/**
 * Classify findings as inline or degraded against the valid diff lines.
 *
 * @param validLines Output of {@link parseDiffHunks}: per-file commentable
 *                   line sets.
 * @param findings   Raw LLM findings with `file` and `line` fields.
 */
export function mapFindings(
  validLines: Map<string, Set<number>>,
  findings: Finding[],
): LineMapResult {
  const inline: Finding[] = [];
  const degraded: Finding[] = [];

  for (const f of findings) {
    const lines = validLines.get(f.file);
    if (lines && f.line !== null && lines.has(f.line)) {
      inline.push(f);
    } else {
      degraded.push(f);
    }
  }

  return { inline, degraded };
}
