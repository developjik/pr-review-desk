/**
 * Review-history data access.
 *
 * Persists one row per completed review (a "review ledger") so the UI can show
 * history, severity/author/repo breakdowns, and usage/cost charts without
 * re-scanning ephemeral provider responses. Mirrors the `review-usage.ts`
 * conventions: caller-supplied explicit ISO timestamps (`reviewedAt`,
 * `createdAt`) with NO SQL DEFAULT — timezone-consistent — prepared statements,
 * COALESCE on every SUM (NULL → 0, never NaN), and typed snake_case →
 * camelCase row mapping.
 *
 * Schema lives in migration v7 (`review_history`).
 */
import type { DatabaseSync } from "node:sqlite";

/** Parameters for {@link insertReviewHistory}. Timestamps are caller-supplied ISO. */
export interface InsertReviewHistoryParams {
  prId: number;
  prNumber: number;
  repo: string;
  headSha: string;
  title?: string | null;
  author?: string | null;
  /** Defaults to `'auto'` when omitted. */
  reviewMode?: string;
  findingsTotal: number;
  sevHigh: number;
  sevMedium: number;
  sevLow: number;
  posted: number;
  degraded: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  costUsd: number;
  /** Defaults to `'published'` when omitted. */
  status?: string;
  /** REQUIRED ISO timestamp — caller passes `new Date().toISOString()` (L1). */
  reviewedAt: string;
  /** REQUIRED ISO timestamp — caller passes `new Date().toISOString()` (L1). */
  createdAt: string;
}

/** A typed `review_history` row (camelCase mapping of the snake_case columns). */
export interface ReviewHistoryRow {
  id: number;
  prId: number;
  prNumber: number;
  repo: string;
  headSha: string;
  title: string | null;
  author: string | null;
  reviewMode: string;
  findingsTotal: number;
  sevHigh: number;
  sevMedium: number;
  sevLow: number;
  posted: number;
  degraded: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  costUsd: number;
  status: string;
  reviewedAt: string;
  createdAt: string;
}

/** Optional filters for {@link getHistory}. All comparisons are inclusive. */
export interface HistoryFilters {
  /** Exact `repo` match (e.g. `"owner/repo"`). */
  repo?: string;
  /** Inclusive lower bound on `reviewed_at` (ISO). */
  since?: string;
  /** Inclusive upper bound on `reviewed_at` (ISO). */
  until?: string;
  /** `'high' | 'medium' | 'low'` — keeps rows where `sev_<severity> > 0`. */
  severity?: string;
  /** Exact `author` match. */
  author?: string;
  /** Row cap. Defaults to 200, clamped to [1, 1000]. */
  limit?: number;
}

/** Aggregated totals for a slice of `review_history` (never NaN). */
export interface StatsSummary {
  totalReviews: number;
  totalFindings: number;
  totalPosted: number;
  totalDegraded: number;
  totalCostUsd: number;
  totalPromptTokens: number;
  totalCompletionTokens: number;
  totalTokens: number;
}

/** One calendar day's rolled-up review activity. */
export interface DailyStat {
  /** `YYYY-MM-DD` (UTC). */
  date: string;
  reviews: number;
  findings: number;
  costUsd: number;
}

/** A raw `review_history` row (snake_case DB columns). */
interface HistoryDbRow {
  id: number;
  pr_id: number;
  pr_number: number;
  repo: string;
  head_sha: string;
  title: string | null;
  author: string | null;
  review_mode: string;
  findings_total: number;
  sev_high: number;
  sev_medium: number;
  sev_low: number;
  posted: number;
  degraded: number;
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  cost_usd: number;
  status: string;
  reviewed_at: string;
  created_at: string;
}

/** Whitelist mapping from severity aliases to their `sev_*` columns. */
const SEVERITY_COLUMNS: Record<string, string> = {
  high: "sev_high",
  medium: "sev_medium",
  low: "sev_low",
};

/**
 * Insert a review-history row and return the new row id
 * (`lastInsertRowid`). `reviewMode` defaults to `'auto'` and `status` defaults
 * to `'published'`; `title`/`author` default to `null`. Timestamps are taken
 * verbatim from the caller (NO SQL DEFAULT — timezone-consistent).
 */
export function insertReviewHistory(db: DatabaseSync, params: InsertReviewHistoryParams): number {
  const result = db.prepare(
    `INSERT INTO review_history
       (pr_id, pr_number, repo, head_sha, title, author, review_mode,
        findings_total, sev_high, sev_medium, sev_low, posted, degraded,
        prompt_tokens, completion_tokens, total_tokens, cost_usd, status,
        reviewed_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    params.prId,
    params.prNumber,
    params.repo,
    params.headSha,
    params.title ?? null,
    params.author ?? null,
    params.reviewMode ?? "auto",
    params.findingsTotal,
    params.sevHigh,
    params.sevMedium,
    params.sevLow,
    params.posted,
    params.degraded,
    params.promptTokens,
    params.completionTokens,
    params.totalTokens,
    params.costUsd,
    params.status ?? "published",
    params.reviewedAt,
    params.createdAt,
  );
  return Number(result.lastInsertRowid);
}

/**
 * Set `status` on every history row matching `(prId, headSha)`. Used when a
 * pending review is approved/rejected so the ledger reflects the final
 * disposition. Affects zero rows when no matching review exists.
 */
export function updateReviewHistoryStatus(
  db: DatabaseSync,
  prId: number,
  headSha: string,
  status: string,
): void {
  db.prepare(
    `UPDATE review_history SET status = ? WHERE pr_id = ? AND head_sha = ?`,
  ).run(status, prId, headSha);
}

/**
 * Query history rows, newest-first by `reviewed_at`, applying any subset of
 * {@link HistoryFilters} (all AND-combined, inclusive). `repo`/`author` are
 * exact matches; `since`/`until` bound `reviewed_at`; `severity` keeps rows
 * with `sev_<severity> > 0`. `limit` defaults to 200 and is clamped to
 * [1, 1000]. Returns rows mapped to {@link ReviewHistoryRow}.
 */
export function getHistory(db: DatabaseSync, filters: HistoryFilters): ReviewHistoryRow[] {
  const conditions: string[] = [];
  const args: (string | number)[] = [];

  if (filters.repo) {
    conditions.push("repo = ?");
    args.push(filters.repo);
  }
  if (filters.since) {
    conditions.push("reviewed_at >= ?");
    args.push(filters.since);
  }
  if (filters.until) {
    conditions.push("reviewed_at <= ?");
    args.push(filters.until);
  }
  if (filters.severity && SEVERITY_COLUMNS[filters.severity]) {
    conditions.push(`${SEVERITY_COLUMNS[filters.severity]} > 0`);
  }
  if (filters.author) {
    conditions.push("author = ?");
    args.push(filters.author);
  }

  const limit = Math.max(1, Math.min(1000, filters.limit ?? 200));
  const where = conditions.length ? `WHERE ${conditions.join(" AND ")}` : "";

  const rows = db.prepare(
    `SELECT id, pr_id, pr_number, repo, head_sha, title, author, review_mode,
            findings_total, sev_high, sev_medium, sev_low, posted, degraded,
            prompt_tokens, completion_tokens, total_tokens, cost_usd, status,
            reviewed_at, created_at
     FROM review_history
     ${where}
     ORDER BY reviewed_at DESC
     LIMIT ?`,
  ).all(...args, limit) as unknown as HistoryDbRow[];

  return rows.map(rowToHistory);
}

/**
 * Aggregate totals across every history row whose `reviewed_at >= sinceIso`.
 * Every sum is `COALESCE`d so missing/zero rows contribute 0 (never NaN);
 * returns a zero-aggregate when no rows match.
 */
export function getStatsSince(db: DatabaseSync, sinceIso: string): StatsSummary {
  const row = db.prepare(
    `SELECT
       COUNT(*)                            AS total_reviews,
       COALESCE(SUM(findings_total), 0)    AS total_findings,
       COALESCE(SUM(posted), 0)            AS total_posted,
       COALESCE(SUM(degraded), 0)          AS total_degraded,
       COALESCE(SUM(cost_usd), 0)          AS total_cost_usd,
       COALESCE(SUM(prompt_tokens), 0)     AS total_prompt_tokens,
       COALESCE(SUM(completion_tokens), 0) AS total_completion_tokens,
       COALESCE(SUM(total_tokens), 0)      AS total_tokens
     FROM review_history
     WHERE reviewed_at >= ?`,
  ).get(sinceIso) as {
    total_reviews: number;
    total_findings: number;
    total_posted: number;
    total_degraded: number;
    total_cost_usd: number;
    total_prompt_tokens: number;
    total_completion_tokens: number;
    total_tokens: number;
  } | undefined;

  return {
    totalReviews: Number(row?.total_reviews ?? 0),
    totalFindings: Number(row?.total_findings ?? 0),
    totalPosted: Number(row?.total_posted ?? 0),
    totalDegraded: Number(row?.total_degraded ?? 0),
    totalCostUsd: Number(row?.total_cost_usd ?? 0),
    totalPromptTokens: Number(row?.total_prompt_tokens ?? 0),
    totalCompletionTokens: Number(row?.total_completion_tokens ?? 0),
    totalTokens: Number(row?.total_tokens ?? 0),
  };
}

/**
 * Per-day rollup over the last `days` calendar days ending on the date of
 * `sinceIso` (inclusive). Builds the full date range in JS so zero-activity
 * days appear with zeroed counts; the DB is queried for actual aggregates and
 * merged in. Returns `[]` when there is no activity in the window (including
 * an empty table). `findings` sums `findings_total`, `costUsd` sums `cost_usd`,
 * `reviews` counts rows.
 */
export function getStatsByDay(db: DatabaseSync, sinceIso: string, days: number): DailyStat[] {
  const dates = buildDateRange(sinceIso, days);
  if (dates.length === 0) return [];

  const startIso = `${dates[0]}T00:00:00.000Z`;
  const rows = db.prepare(
    `SELECT DATE(reviewed_at)              AS date,
            COUNT(*)                       AS reviews,
            COALESCE(SUM(findings_total), 0) AS findings,
            COALESCE(SUM(cost_usd), 0)       AS cost_usd
     FROM review_history
     WHERE reviewed_at >= ?
     GROUP BY DATE(reviewed_at)`,
  ).all(startIso) as { date: string; reviews: number; findings: number; cost_usd: number }[];

  if (rows.length === 0) return [];

  const byDate = new Map<string, { reviews: number; findings: number; costUsd: number }>();
  for (const r of rows) {
    byDate.set(r.date, {
      reviews: Number(r.reviews ?? 0),
      findings: Number(r.findings ?? 0),
      costUsd: Number(r.cost_usd ?? 0),
    });
  }

  return dates.map((date) => {
    const entry = byDate.get(date);
    return {
      date,
      reviews: entry?.reviews ?? 0,
      findings: entry?.findings ?? 0,
      costUsd: entry?.costUsd ?? 0,
    };
  });
}

/** Build the inclusive list of `days` UTC dates ending on the date of `endIso`. */
function buildDateRange(endIso: string, days: number): string[] {
  if (days <= 0) return [];
  const dates: string[] = [];
  const end = new Date(endIso);
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setUTCDate(d.getUTCDate() - i);
    dates.push(d.toISOString().slice(0, 10));
  }
  return dates;
}

/** Map a snake_case DB row to a typed {@link ReviewHistoryRow}. */
function rowToHistory(row: HistoryDbRow): ReviewHistoryRow {
  return {
    id: row.id,
    prId: row.pr_id,
    prNumber: row.pr_number,
    repo: row.repo,
    headSha: row.head_sha,
    title: row.title,
    author: row.author,
    reviewMode: row.review_mode,
    findingsTotal: row.findings_total,
    sevHigh: row.sev_high,
    sevMedium: row.sev_medium,
    sevLow: row.sev_low,
    posted: row.posted,
    degraded: row.degraded,
    promptTokens: row.prompt_tokens,
    completionTokens: row.completion_tokens,
    totalTokens: row.total_tokens,
    costUsd: row.cost_usd,
    status: row.status,
    reviewedAt: row.reviewed_at,
    createdAt: row.created_at,
  };
}
