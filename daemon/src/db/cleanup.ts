/**
 * Retention cleanup for the queue table.
 * Deletes terminal-status rows (done/failed/skipped) older than retentionDays.
 * Never touches pending or processing rows.
 */
import type { DatabaseSync } from "node:sqlite";

const DEFAULT_RETENTION_DAYS = 7;

/**
 * Prune terminal-status queue rows older than `retentionDays`.
 * Safe to call every poll cycle (cheap, indexed by status).
 */
export function pruneQueue(
  db: DatabaseSync,
  retentionDays: number = DEFAULT_RETENTION_DAYS,
): number {
  const cutoff = new Date(
    Date.now() - retentionDays * 24 * 60 * 60 * 1000,
  ).toISOString();
  const result = db.prepare(
    `DELETE FROM queue
     WHERE status IN ('done', 'failed', 'skipped')
       AND enqueued_at < ?`,
  ).run(cutoff);
  return Number(result.changes);
}
const DEFAULT_PENDING_RETENTION_DAYS = 30;

/** Prune terminal (approved/rejected) pending_reviews older than retentionDays. */
export function prunePendingReviews(
  db: DatabaseSync,
  retentionDays: number = DEFAULT_PENDING_RETENTION_DAYS,
): number {
  const cutoff = new Date(Date.now() - retentionDays * 24 * 60 * 60 * 1000).toISOString();
  const result = db.prepare(
    "DELETE FROM pending_reviews WHERE status IN ('approved', 'rejected') AND resolved_at < ?",
  ).run(cutoff);
  return Number(result.changes);
}
