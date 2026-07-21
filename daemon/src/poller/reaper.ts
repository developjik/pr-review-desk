/**
 * Reaper — prune stale pending queue entries whose PRs have been merged or
 * closed on GitHub since they were enqueued.
 *
 * Without this pass a PR that is approved/merged *before* the daemon reviews it
 * lingers in the queue forever (the poller only ever appends; it never removes).
 * Each poll cycle calls {@link reapStaleQueue} first, so the queue reflects the
 * PRs that are genuinely still awaiting review.
 *
 * The GitHub fetch is injected so the unit is testable without a live API.
 */
import type { DatabaseSync } from "node:sqlite";
import { getLogger } from "../logging/logger";

/** The subset of {@link PRMeta} the reaper consults to decide staleness. */
export interface ReapPRMeta {
  merged: boolean;
  state: "open" | "closed";
}

export type SkipReason = "merged" | "closed";

export interface ReapDeps {
  db: DatabaseSync;
  /** Fetch PR meta; return `null` on failure so the row is left for next cycle. */
  fetchMeta: (
    owner: string,
    repo: string,
    number: number,
  ) => Promise<ReapPRMeta | null>;
  /** Invoked once per stale PR — caller marks the row + emits the wire event. */
  onSkip: (prId: number, reason: SkipReason) => void;
}

/**
 * Scan every distinct pending PR in the queue. For each, fetch its GitHub state
 * and — if merged or closed — invoke {@link ReapDeps.onSkip}. Fetch failures are
 * tolerated (the row survives to the next cycle); a malformed `owner/name` repo
 * string is skipped with a warning.
 */
export async function reapStaleQueue(deps: ReapDeps): Promise<void> {
  const log = getLogger();
  const selectPending = deps.db.prepare(
    "SELECT DISTINCT pr_id, repo, number FROM queue WHERE status = 'pending'",
  );
  const markSkipped = deps.db.prepare(
    "UPDATE queue SET status = 'skipped' WHERE pr_id = ? AND status = 'pending'",
  );
  const rows = selectPending.all() as Array<{
    pr_id: number;
    repo: string;
    number: number;
  }>;
  if (rows.length === 0) return;

  for (const row of rows) {
    const slash = row.repo.indexOf("/");
    if (slash < 0) {
      log.warn(
        { code: "reap_bad_repo", repo: row.repo },
        "cannot parse owner/name; skipping reap",
      );
      continue;
    }
    const owner = row.repo.slice(0, slash);
    const name = row.repo.slice(slash + 1);

    const meta = await deps.fetchMeta(owner, name, row.number);
    if (!meta) continue; // fetch failed; leave for next cycle

    let reason: SkipReason | null = null;
    if (meta.merged) reason = "merged";
    else if (meta.state === "closed") reason = "closed";
    if (!reason) continue;

    markSkipped.run(row.pr_id);
    deps.onSkip(row.pr_id, reason);
    log.info(
      { code: "queue_reaped", repo: row.repo, number: row.number, reason },
      "stale pr removed from queue",
    );
  }
}
