/**
 * Dedupe against the `review_state` table (R9).
 *
 * A PR is "already reviewed" iff `review_state` holds a row for `pr_id` whose
 * `commit_sha` equals the current head. A new commit on the same PR therefore
 * re-qualifies it for review (R9: "새 커밋 → 재리뷰 대상").
 *
 * {@link recordReview} writes to `review_state` after a successful review so
 * this module owns all access to the table.
 */
import type { DatabaseSync } from "node:sqlite";

export interface Dedupe {
  /**
   * `true` if the (prId, commitSha) pair has NOT been reviewed yet — i.e. the PR
   * is new or its head has advanced since the last review.
   */
  shouldReview(prId: number, commitSha: string): Promise<boolean>;
}

export function createDedupe(db: DatabaseSync): Dedupe {
  const selectSha = db.prepare("SELECT commit_sha FROM review_state WHERE pr_id = ?");
  return {
    shouldReview(prId, commitSha) {
      const row = selectSha.get(prId) as { commit_sha?: string } | undefined;
      // Never reviewed → review. Reviewed at a different commit → re-review.
      return Promise.resolve(!row || row.commit_sha !== commitSha);
    },
  };
}

/**
 * Mark a (prId, commitSha) pair as reviewed at `now`. Called by the reviewer
 * (P4) after a successful review so the next poll skips it (R9).
 */
export function recordReview(
  db: DatabaseSync,
  prId: number,
  commitSha: string,
  reviewedAt: string = new Date().toISOString(),
): void {
  db.prepare(
    `INSERT INTO review_state (pr_id, commit_sha, reviewed_at)
     VALUES (?, ?, ?)
     ON CONFLICT(pr_id) DO UPDATE SET
       commit_sha  = excluded.commit_sha,
       reviewed_at = excluded.reviewed_at`,
  ).run(prId, commitSha, reviewedAt);
}
