/**
 * Pending-reviews data access.
 * Stores LLM findings for user approval before posting to GitHub.
 * Finding ids are synthesized at insert time: "i0","i1",... for inline,
 * "d0","d1",... for degraded.
 */
import type { DatabaseSync } from "node:sqlite";
import type { Finding } from "../types/domain";
import type { PendingFinding, PendingReview } from "@pr-review/shared";

export interface InsertPendingParams {
  prId: number;
  prNumber: number;
  repo: string;
  headSha: string;
  title: string;
  summary: string;
  inline: Finding[];
  degraded: Finding[];
  githubReviewId: number;
  /** Per-file diff hunk text (file → hunks), stored as diff_json. */
  diff?: Record<string, string> | null;
}

/** Stamp stable ids onto findings (copies, never mutates input). */
function stampIds(inline: Finding[], degraded: Finding[]): { inline: PendingFinding[]; degraded: PendingFinding[] } {
  return {
    inline: inline.map((f, i) => ({ ...f, id: `i${i}` })),
    degraded: degraded.map((f, i) => ({ ...f, id: `d${i}` })),
  };
}

/** Insert a pending review. Returns the new review id. */
export function insertPendingReview(db: DatabaseSync, params: InsertPendingParams): number {
  const stamped = stampIds(params.inline, params.degraded);
  const findingsJson = JSON.stringify({
    inline: stamped.inline,
    degraded: stamped.degraded,
    summary: params.summary,
  });
  const diffJson = params.diff ? JSON.stringify(params.diff) : null;
  const result = db.prepare(
    `INSERT INTO pending_reviews (pr_id, pr_number, repo, head_sha, title, summary, findings_json, github_review_id, diff_json, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
  ).run(
    params.prId,
    params.prNumber,
    params.repo,
    params.headSha,
    params.title,
    params.summary,
    findingsJson,
    params.githubReviewId,
    diffJson,
    new Date().toISOString(),
  );
  return Number(result.lastInsertRowid);
}

/** Get a single pending review by id (any status). Returns null if not found. */
export function getPendingReview(db: DatabaseSync, reviewId: number): PendingReview | null {
  const row = db.prepare(
    "SELECT id, pr_id, pr_number, repo, head_sha, title, summary, findings_json, diff_json, created_at FROM pending_reviews WHERE id = ?",
  ).get(reviewId) as PendingReviewRow | undefined;
  if (!row) return null;
  return rowToPendingReview(row);
}

/** List all pending (unresolved) reviews, oldest first. */
export function listPendingReviews(db: DatabaseSync): PendingReview[] {
  const rows = db.prepare(
    "SELECT id, pr_id, pr_number, repo, head_sha, title, summary, findings_json, diff_json, created_at FROM pending_reviews WHERE status = 'pending' ORDER BY id ASC",
  ).all() as unknown as PendingReviewRow[];
  return rows.map(rowToPendingReview);
}

/** Does an unresolved pending review exist for (prId, headSha)? */
export function hasPendingReview(db: DatabaseSync, prId: number, headSha: string): boolean {
  const row = db.prepare(
    "SELECT 1 FROM pending_reviews WHERE pr_id = ? AND head_sha = ? AND status = 'pending' LIMIT 1",
  ).get(prId, headSha);
  return row !== undefined;
}

/** Atomically resolve a pending review. Returns claimed row data or null if already resolved. */
export function resolvePendingReview(
  db: DatabaseSync,
  reviewId: number,
  status: "approved" | "rejected",
): { prId: number; headSha: string; prNumber: number; repo: string; summary: string; findingsJson: string; githubReviewId: number | null } | null {
  const row = db.prepare(
    `UPDATE pending_reviews SET status = ?, resolved_at = ?
     WHERE id = ? AND status = 'pending'
     RETURNING pr_id, head_sha, pr_number, repo, summary, findings_json, github_review_id`,
  ).get(status, new Date().toISOString(), reviewId) as ResolveRow | undefined;
  if (!row) return null;
  return {
    prId: row.pr_id,
    headSha: row.head_sha,
    prNumber: row.pr_number,
    repo: row.repo,
    summary: row.summary,
    findingsJson: row.findings_json,
    githubReviewId: row.github_review_id,
  };
}

// ---- helpers ----

interface PendingReviewRow {
  id: number;
  pr_id: number;
  pr_number: number;
  repo: string;
  head_sha: string;
  title: string | null;
  summary: string;
  findings_json: string;
  diff_json: string | null;
  created_at: string;
}

interface ResolveRow {
  pr_id: number;
  head_sha: string;
  pr_number: number;
  repo: string;
  summary: string;
  findings_json: string;
  github_review_id: number | null;
}

function rowToPendingReview(row: PendingReviewRow): PendingReview {
  const parsed = JSON.parse(row.findings_json) as { inline: PendingFinding[]; degraded: PendingFinding[] };
  const findings = [...parsed.inline, ...parsed.degraded];
  const diff = row.diff_json ? (JSON.parse(row.diff_json) as Record<string, string>) : undefined;
  return {
    reviewId: row.id,
    prId: row.pr_id,
    prNumber: row.pr_number,
    repo: row.repo,
    title: row.title ?? undefined,
    headSha: row.head_sha,
    summary: row.summary,
    findings,
    diff,
    createdAt: row.created_at,
  };
}
