/**
 * Finding-feedback data access.
 *
 * Persists per-finding human feedback (`useful` | `false_positive`) so later
 * slices (accuracy dashboards, prompt-improvement signals) have a stable data
 * model with no extra migration. Mirrors the `review-usage.ts` conventions:
 * caller-supplied explicit ISO `createdAt` (NO SQL DEFAULT — timezone
 * consistent), prepared statements, and typed row mapping.
 *
 * Toggle semantics: `upsertFeedback` uses `INSERT ... ON CONFLICT(pr_id,
 * finding_key) DO UPDATE SET feedback = excluded.feedback, comment =
 * excluded.comment` scoped to the `UNIQUE(pr_id, finding_key)` constraint, so
 * re-submitting feedback for the same finding flips its value rather than
 * creating a duplicate — while NOT NULL violations still surface.
 */
import type { DatabaseSync } from "node:sqlite";

export interface UpsertFeedbackParams {
  prId: number;
  findingKey: string;
  file: string;
  line: number | null;
  comment: string;
  area?: string | null;
  severity?: string | null;
  /** `'useful' | 'false_positive'`. */
  feedback: string;
  /** REQUIRED ISO timestamp — caller passes `new Date().toISOString()` (L1). */
  createdAt: string;
}

/** A `finding_feedback` row mapped to camelCase. */
export interface FeedbackRow {
  id: number;
  prId: number;
  findingKey: string;
  file: string;
  line: number | null;
  comment: string;
  area: string | null;
  severity: string | null;
  feedback: string;
  createdAt: string;
}

/** Aggregate feedback counts across all rows. */
export interface FeedbackStats {
  useful: number;
  falsePositive: number;
  /** area → false_positive count (NULL areas excluded). */
  byArea: Record<string, number>;
}

/** A repeated false-positive signal (same comment in same file across PRs). */
export interface FalsePositivePattern {
  file: string;
  comment: string;
  count: number;
}

/** A raw `finding_feedback` row (snake_case DB columns). */
interface FeedbackDbRow {
  id: number;
  pr_id: number;
  finding_key: string;
  file: string;
  line: number | null;
  comment: string;
  area: string | null;
  severity: string | null;
  feedback: string;
  created_at: string;
}

/**
 * Insert or toggle feedback for a finding. Uses `INSERT ... ON CONFLICT(pr_id,
 * finding_key) DO UPDATE SET feedback = excluded.feedback, comment =
 * excluded.comment` scoped to the `UNIQUE(pr_id, finding_key)` constraint, so
 * re-submitting feedback for the same finding flips its value rather than
 * creating a duplicate — while NOT NULL violations still surface.
 */
export function upsertFeedback(db: DatabaseSync, params: UpsertFeedbackParams): void {
  db.prepare(
    `INSERT INTO finding_feedback
       (pr_id, finding_key, file, line, comment, area, severity, feedback, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(pr_id, finding_key) DO UPDATE SET
       feedback = excluded.feedback,
       comment  = excluded.comment`,
  ).run(
    params.prId,
    params.findingKey,
    params.file,
    params.line,
    params.comment,
    params.area ?? null,
    params.severity ?? null,
    params.feedback,
    params.createdAt,
  );
}

/**
 * All feedback rows for a PR, in insertion order (`ORDER BY id ASC`). Each row
 * is mapped to a {@link FeedbackRow}.
 */
export function getFeedbackByPr(db: DatabaseSync, prId: number): FeedbackRow[] {
  const rows = db.prepare(
    `SELECT id, pr_id, finding_key, file, line, comment, area, severity, feedback, created_at
     FROM finding_feedback
     WHERE pr_id = ?
     ORDER BY id ASC`,
  ).all(prId) as unknown as FeedbackDbRow[];
  return rows.map(rowToFeedback);
}

/**
 * Aggregate feedback counts across all rows. `useful` and `falsePositive` are
 * COALESCE'd to 0 (never NaN) so an empty table yields a zero-aggregate.
 * `byArea` groups false_positive rows by area (NULL areas excluded).
 */
export function getFeedbackStats(db: DatabaseSync): FeedbackStats {
  const totals = db.prepare(
    `SELECT
       COALESCE(SUM(CASE WHEN feedback = 'useful'         THEN 1 ELSE 0 END), 0) AS useful,
       COALESCE(SUM(CASE WHEN feedback = 'false_positive' THEN 1 ELSE 0 END), 0) AS false_positive
     FROM finding_feedback`,
  ).get() as { useful: number; false_positive: number } | undefined;

  const areaRows = db.prepare(
    `SELECT area, COUNT(*) AS count
     FROM finding_feedback
     WHERE feedback = 'false_positive' AND area IS NOT NULL
     GROUP BY area`,
  ).all() as { area: string; count: number }[];

  const byArea: Record<string, number> = {};
  for (const r of areaRows) {
    byArea[r.area] = Number(r.count);
  }

  return {
    useful: Number(totals?.useful ?? 0),
    falsePositive: Number(totals?.false_positive ?? 0),
    byArea,
  };
}

/**
 * Repeated false-positive signals: groups false_positive rows by `(file,
 * comment)`, counts occurrences, and returns the top `limit` ordered by count
 * DESC (ties broken by file/comment). Used to surface the same comment firing
 * in the same file across PRs for future prompt improvement. Returns `[]` when
 * no rows match.
 */
export function getFalsePositivePatterns(db: DatabaseSync, limit: number): FalsePositivePattern[] {
  const rows = db.prepare(
    `SELECT file, comment, COUNT(*) AS count
     FROM finding_feedback
     WHERE feedback = 'false_positive'
     GROUP BY file, comment
     ORDER BY count DESC, file ASC, comment ASC
     LIMIT ?`,
  ).all(limit) as { file: string; comment: string; count: number }[];
  return rows.map((r) => ({
    file: r.file,
    comment: r.comment,
    count: Number(r.count),
  }));
}

/** Map a snake_case DB row to a typed {@link FeedbackRow}. */
function rowToFeedback(row: FeedbackDbRow): FeedbackRow {
  return {
    id: row.id,
    prId: row.pr_id,
    findingKey: row.finding_key,
    file: row.file,
    line: row.line,
    comment: row.comment,
    area: row.area,
    severity: row.severity,
    feedback: row.feedback,
    createdAt: row.created_at,
  };
}
