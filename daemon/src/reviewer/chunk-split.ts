/**
 * Chunk splitting + result merging for large-file review (F2).
 *
 * When a file's diff exceeds the per-chunk diff-line budget (500), the diff is
 * split on `@@` hunk boundaries into ≤500-line chunks. Each chunk is reviewed
 * in its own LLM call (full file content always sent), and the per-chunk
 * results are merged + deduped back into a single per-file review.
 *
 * Line-mapping invariant (D2): hunks are NEVER split mid-body — an absolute
 * `@@ -a,b +start,count @@` header is kept with its hunk body so the
 * whole-file `parseDiffHunks` line mapper keeps working on the original diff,
 * independent of how chunks were carved out here.
 */
import type { Finding, Severity } from "../types/domain";
import type { LlmFileReview } from "./llm-client";
import { countDiffLines } from "./chunker";

/**
 * Severity ranking used to pick a winner among deduped findings. `critical` is
 * retained defensively even though `normalizeSeverity` currently collapses it
 * to `high` (see llm-client.ts).
 */
export const SEVERITY_RANK: Record<Severity, number> = {
  info: 0,
  low: 1,
  medium: 2,
  high: 3,
  critical: 4,
};

/**
 * Split a per-file diff into ≤`budgetDiffLines` chunks, cutting only on `@@`
 * hunk boundaries.
 *
 * Consecutive hunks are greedily packed into a running buffer while
 * `countDiffLines(buffer) + countDiffLines(hunk) <= budgetDiffLines`; the
 * buffer is flushed as soon as the next hunk would exceed the budget. A single
 * hunk larger than the budget becomes its own chunk (a hunk is never split —
 * that would break absolute line numbers). Chunk order preserves the original
 * left→right hunk order, so the split is deterministic.
 *
 * @param diffText         the per-file diff (hunks, as produced by
 *                         `splitDiffByFile`).
 * @param budgetDiffLines  max content diff lines per chunk (e.g.
 *                         {@link MAX_CHUNK_DIFF_LINES}).
 * @returns one or more chunk strings; `[diffText]` when there is no `@@` hunk
 *          header or the input is empty.
 */
export function splitFileIntoChunks(
  diffText: string,
  budgetDiffLines: number,
): string[] {
  // No @@ hunk headers / empty input → a single chunk.
  if (!diffText) {
    return [diffText];
  }

  // Carve out hunks: each starts at a `@@` header line and runs until the next
  // `@@` header. Any leading lines before the first `@@` are captured as a
  // preamble (file metadata) and prepended to the first chunk so no content is
  // dropped — in practice `splitDiffByFile` yields hunks only.
  const lines = diffText.split("\n");
  const hunks: string[] = [];
  const preamble: string[] = [];
  let current: string[] | null = null;

  for (const line of lines) {
    if (line.startsWith("@@")) {
      if (current !== null) {
        hunks.push(current.join("\n"));
      }
      current = [line];
    } else if (current !== null) {
      current.push(line);
    } else {
      preamble.push(line);
    }
  }
  if (current !== null) {
    hunks.push(current.join("\n"));
  }

  // `@@` may appear mid-content without ever heading a line → no real hunk.
  if (hunks.length === 0) {
    return [diffText];
  }

  if (preamble.length > 0) {
    hunks[0] = [...preamble, hunks[0]].join("\n");
  }

  // Greedy pack: accumulate consecutive hunks while they fit the budget.
  const chunks: string[] = [];
  let buffer = "";
  for (const hunk of hunks) {
    if (buffer === "") {
      // First hunk in a chunk (also makes an oversized hunk its own chunk).
      buffer = hunk;
      continue;
    }
    if (countDiffLines(buffer) + countDiffLines(hunk) <= budgetDiffLines) {
      buffer += "\n" + hunk;
    } else {
      chunks.push(buffer);
      buffer = hunk;
    }
  }
  if (buffer !== "") {
    chunks.push(buffer);
  }
  return chunks;
}

/**
 * Merge per-chunk LLM reviews for one file into a single review, deduping
 * overlapping findings emitted by adjacent chunks.
 *
 * - Empty input → `{ findings: [], summary: "" }` (NEVER throws).
 * - Findings are deduped by `${file}|${line ?? "null"}|${comment}`. Among
 *   colliding copies the winner is the highest {@link SEVERITY_RANK}; ties go
 *   to the earliest chunk (first seen). The winner's `area` and `severity` are
 *   retained.
 * - The suggestion is the FIRST non-empty `suggestion` across all copies of a
 *   key, scanned in chunk order (so a later, higher-severity winner still picks
 *   up an earlier copy's richer suggestion).
 * - `summary` is `results[0]?.summary ?? ""` (the caller's `aggregate()`
 *   ignores per-file summaries).
 *
 * @param results per-chunk reviews for a single file, in chunk order.
 */
export function mergeChunkResults(results: LlmFileReview[]): LlmFileReview {
  if (results.length === 0) {
    return { findings: [], summary: "" };
  }

  // key → winning finding (highest severity; earliest on tie).
  const winners = new Map<string, Finding>();
  // key → first non-empty suggestion seen, in scan (chunk) order.
  const firstSuggestion = new Map<string, string>();

  for (const result of results) {
    for (const finding of result.findings) {
      const key = `${finding.file}|${finding.line ?? "null"}|${finding.comment}`;
      const existing = winners.get(key);
      if (existing === undefined) {
        winners.set(key, finding);
      } else if (SEVERITY_RANK[finding.severity] > SEVERITY_RANK[existing.severity]) {
        // Strictly higher severity wins; ties keep the earlier (first seen).
        winners.set(key, finding);
      }
      if (finding.suggestion && !firstSuggestion.has(key)) {
        firstSuggestion.set(key, finding.suggestion);
      }
    }
  }

  const findings: Finding[] = [];
  for (const [key, winner] of winners) {
    findings.push({
      ...winner,
      suggestion: firstSuggestion.get(key) ?? winner.suggestion,
    });
  }

  return {
    findings,
    summary: results[0]?.summary ?? "",
  };
}
