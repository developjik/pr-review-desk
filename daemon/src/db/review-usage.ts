/**
 * Review token-usage data access.
 *
 * Persists per-file token usage reported by the LLM provider so later slices
 * (cost math, budget-pause, UI charts) have a stable data model with no extra
 * migration. Mirrors the `pending-reviews.ts` conventions: caller-supplied
 * explicit ISO `createdAt` (NO SQL DEFAULT — timezone-consistent), prepared
 * statements, and typed row mapping.
 *
 * Retry safety (H2): `insertUsage` uses `INSERT ... ON CONFLICT(pr_id,
 * head_sha, file, model) DO NOTHING` scoped to the unique index, so a
 * queue-retry re-run of `reviewPR` for the same commit cannot double-count —
 * while NOT NULL/CHECK/FK violations still surface.
 */
import type { DatabaseSync } from "node:sqlite";
import type { FileUsage, TokenUsage } from "../types/domain";

export interface InsertUsageParams {
  prId: number;
  prNumber: number;
  repo: string;
  headSha: string;
  /** Reviewed file path (`null` reserved for a future aggregate row — out of scope). */
  file: string | null;
  model: string;
  usage: TokenUsage;
  /** REQUIRED ISO timestamp — caller passes `new Date().toISOString()` (L1). */
  createdAt: string;
}

/** A raw `review_usage` row (snake_case DB columns). */
interface UsageRow {
  pr_id: number;
  file: string | null;
  model: string;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  created_at: string;
}

/**
 * Insert a per-file usage row. Uses `INSERT ... ON CONFLICT(pr_id, head_sha,
 * file, model) DO NOTHING` scoped to the `review_usage_pr_file_model_uniq`
 * unique index so a queue-retry re-run (same key tuple) is a no-op rather than
 * a duplicate — while NOT NULL/CHECK/FK violations still surface. Returns the
 * new row id (0 if the insert was ignored as a duplicate).
 */
export function insertUsage(db: DatabaseSync, params: InsertUsageParams): number {
  const result = db.prepare(
    `INSERT INTO review_usage
       (pr_id, pr_number, repo, head_sha, file, model, prompt_tokens, completion_tokens, total_tokens, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(pr_id, head_sha, file, model) DO NOTHING`,
  ).run(
    params.prId,
    params.prNumber,
    params.repo,
    params.headSha,
    params.file,
    params.model,
    params.usage.promptTokens,
    params.usage.completionTokens,
    params.usage.totalTokens,
    params.createdAt,
  );
  return Number(result.lastInsertRowid);
}

/**
 * All per-file usage rows for a PR, in insertion order. Each row maps back to a
 * {@link FileUsage} (`file` + the three token counts).
 */
export function getUsageByPr(db: DatabaseSync, prId: number): FileUsage[] {
  const rows = db.prepare(
    `SELECT pr_id, file, model, prompt_tokens, completion_tokens, total_tokens, created_at
     FROM review_usage
     WHERE pr_id = ?
     ORDER BY id ASC`,
  ).all(prId) as unknown as UsageRow[];
  return rows.map(rowToUsage);
}

/**
 * Sum token usage across all PRs whose rows were created at or after `sinceIso`.
 * Rows with missing/coerced-zero counts contribute 0 (never NaN). Returns a
 * zero-aggregate when no rows match.
 */
export function getUsageTotalSince(db: DatabaseSync, sinceIso: string): TokenUsage {
  const row = db.prepare(
    `SELECT
       COALESCE(SUM(prompt_tokens), 0)     AS prompt_tokens,
       COALESCE(SUM(completion_tokens), 0) AS completion_tokens,
       COALESCE(SUM(total_tokens), 0)      AS total_tokens
     FROM review_usage
     WHERE created_at >= ?`,
  ).get(sinceIso) as { prompt_tokens: number; completion_tokens: number; total_tokens: number } | undefined;
  return {
    promptTokens: Number(row?.prompt_tokens ?? 0),
    completionTokens: Number(row?.completion_tokens ?? 0),
    totalTokens: Number(row?.total_tokens ?? 0),
  };
}

/**
 * Sum token usage GROUPED BY model across all PRs whose rows were created at or
 * after `sinceIso`. Rows with missing/coerced-zero counts contribute 0 (never
 * NaN). Returns `[]` when no rows match. Used for per-model cost math (G001).
 */
export function getUsageByModelSince(
  db: DatabaseSync,
  sinceIso: string,
): { model: string; promptTokens: number; completionTokens: number; totalTokens: number }[] {
  const rows = db.prepare(
    `SELECT model,
       COALESCE(SUM(prompt_tokens), 0)     AS prompt_tokens,
       COALESCE(SUM(completion_tokens), 0) AS completion_tokens,
       COALESCE(SUM(total_tokens), 0)      AS total_tokens
     FROM review_usage
     WHERE created_at >= ?
     GROUP BY model`,
  ).all(sinceIso) as { model: string; prompt_tokens: number; completion_tokens: number; total_tokens: number }[];
  return rows.map((r) => ({
    model: r.model,
    promptTokens: Number(r.prompt_tokens ?? 0),
    completionTokens: Number(r.completion_tokens ?? 0),
    totalTokens: Number(r.total_tokens ?? 0),
  }));
}

/** Map a snake_case DB row to a typed {@link FileUsage}. */
function rowToUsage(row: UsageRow): FileUsage {
  return {
    file: row.file,
    promptTokens: row.prompt_tokens,
    completionTokens: row.completion_tokens,
    totalTokens: row.total_tokens,
  };
}
