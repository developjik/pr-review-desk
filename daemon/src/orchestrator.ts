/**
 * Orchestrator — owns daemon lifecycle state and drives the poll → review cycle.
 *
 * Responsibilities:
 *   - Maintain the {@link DaemonState} machine surfaced on the wire.
 *   - Own the queue-processing loop (sequential review of enqueued PRs).
 *   - Wire `poll:now` / `pause` / `resume` commands.
 *   - Own the {@link DatabaseSync} handle (opened from `config.dbPath`).
 *
 * Discovery + cron scheduling are delegated to {@link Poller}. On each cron tick
 * the poller calls back into {@link Orchestrator.runPoll}, which:
 *   1. transitions to `polling` and emits `poll:started`,
 *   2. runs `poller.discover()` (search → enumerate → dedupe → enqueue,
 *      emitting `poll:found` per new PR),
 *   3. drains the queue sequentially: for each PR it fetches the full context
 *      (diff + files), runs the reviewer (P4), classifies findings via the
 *      diff-line-mapper, and emits `publish:review` as a P5 stub,
 *   4. returns to `idle`.
 */
import type { DaemonState, PendingFinding, FindingEdit, UsageSummary } from "@pr-review/shared";
import type { Transport } from "./ipc/transport";
import type { Config } from "./config/schema";
import type { Octokit } from "@octokit/rest";
import { closeDatabase, openDatabase } from "./db/connection";
import { pruneQueue, prunePendingReviews } from "./db/cleanup";
import { insertPendingReview, getPendingReview, listPendingReviews, resolvePendingReview } from "./db/pending-reviews";
import { insertUsage, getUsageByModelSince } from "./db/review-usage";
import type { DatabaseSync } from "node:sqlite";
import { getLogger } from "./logging/logger";
import { Poller } from "./poller/poller";
import { createGitHubClient, fetchAuthenticatedUser, fetchFileContent, fetchPRContext, fetchPRMeta } from "./poller/github-client";
import { recordReview } from "./poller/dedupe";
import { reviewPR } from "./reviewer/reviewer";
import { composeGuidelines } from "./reviewer/prompts";
import { parsePricing, computeCost } from "./reviewer/cost";
import { parseDiffHunks, splitDiffByFile } from "./linemap/diff-parser";
import { mapFindings } from "./linemap/diff-line-mapper";
import { publishReview, createPendingReview, submitPendingReview, discardPendingReview } from "./publisher/publisher";
import type { ReviewContext } from "./types/domain";

interface QueueRow {
  id: number;
  pr_id: number;
  repo: string;
  head_sha: string;
  number: number;
  retry_count: number;
}

export class Orchestrator {
  /** Current lifecycle state (mirrored on the wire as `daemon:status`). */
  state: DaemonState = "idle";

  private cfg: Config | null = null;
  private paused = false;
  private db: DatabaseSync | null = null;
  private poller: Poller | null = null;
  private pollCycle: Promise<void> | null = null;
  private readonly unsubs: Array<() => void> = [];
  private octokit: Octokit | null = null;
  private cachedPat: string | null = null;

  constructor(private readonly transport: Transport) {}

  /** Wire command listeners. Call once before the first config arrives. */
  async init(): Promise<void> {
    this.unsubs.push(
      this.transport.on("poll:now", () => {
        void this.runPoll();
      }),
      this.transport.on("pause", () => {
        this.pause();
      }),
      this.transport.on("resume", () => {
        this.resume();
      }),
      this.transport.on("approve:review", (c) => {
        void this.approveReview(c.reviewId, c.findingIds, c.edits);
      }),
      this.transport.on("reject:review", (c) => {
        void this.rejectReview(c.reviewId);
      }),
      this.transport.on("pending:list", () => {
        void this.emitPendingSnapshot();
      }),
      this.transport.on("get_usage", () => {
        void this.emitUsageSummary();
      }),
    );
  }

  /** Open the DB, start the poller, and enter the idle state. */
  async start(cfg: Config): Promise<void> {
    // Auto-fetch GitHub username from PAT if not provided (GET /user).
    if (!cfg.githubUsername) {
      try {
        const octokit = createGitHubClient(cfg.githubPat);
        const login = await fetchAuthenticatedUser(octokit);
        cfg = { ...cfg, githubUsername: login };
        this.transport.log("info", `GitHub username auto-detected: ${login}`);
      } catch (err) {
        this.transport.log("error", `Failed to auto-detect GitHub username: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
    this.cfg = cfg;
    this.paused = false;
    this.db = openDatabase(cfg.dbPath);
    // Reclaim orphaned processing rows from a previous crash
    const stuckCutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString(); // 30 min
    const stuck = this.db
      .prepare(
        "UPDATE queue SET status = 'pending', claimed_at = NULL WHERE status = 'processing' AND claimed_at < ?",
      )
      .run(stuckCutoff);
    if (stuck.changes > 0) {
      getLogger().info({ code: "orphan_reclaim", count: stuck.changes }, "reclaimed orphaned processing rows");
    }
    // Initialise the cached GitHub client for this PAT.
    this.getOctokit(cfg);
    this.poller = new Poller({
      transport: this.transport,
      db: this.db,
      getOctokit: (c) => this.getOctokit(c),
      onTick: () => this.runPoll(),
    });
    this.poller.start(cfg);
    await this.setState("idle");
  }

  /** Hot-reload config; reschedule if runtime-affecting fields changed. */
  async applyConfig(cfg: Config): Promise<void> {
    this.cfg = cfg;
    this.poller?.updateConfig(cfg);
  }

  /** Tear down poller + DB + listeners. */
  async stop(): Promise<void> {
    for (const unsub of this.unsubs) unsub();
    this.unsubs.length = 0;
    this.poller?.stop();
    this.poller = null;
    closeDatabase();
    this.db = null;
  }

  pause(): void {
    this.paused = true;
    this.poller?.suspend();
    void this.setState("idle");
  }

  resume(): void {
    this.paused = false;
    this.poller?.resume();
    void this.setState("idle");
  }

  // ----------------------------------------------------------------- internals

  /** Run one poll cycle. Re-entrant-safe: collapses concurrent triggers. */
  private runPoll(): Promise<void> {
    if (this.pollCycle) return this.pollCycle;
    this.pollCycle = (async () => {
      if (this.paused || !this.cfg || !this.poller) return;
      const log = getLogger();

      await this.setState("polling");
      await this.transport.emit({ type: "event", event: "poll:started" });

      try {
        await this.poller.discover();
        await this.processQueue();
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        log.error({ code: "poll_failed" }, message);
        await this.transport.error("poll_failed", message).catch(() => undefined);
      }

      // Recover to idle whether the cycle succeeded or not (R25 / AC #6).
      await this.setState("idle");
    })()
      .catch(async (err) => {
        const message = err instanceof Error ? err.message : String(err);
        await this.transport.error("poll_failed", message).catch(() => undefined);
        await this.setState("idle");
      })
      .finally(() => {
        this.pollCycle = null;
      });
    return this.pollCycle;
  }

  /** Return a cached Octokit, rebuilding only when the PAT changes. */
  private getOctokit(cfg: Config): Octokit {
    if (this.octokit && this.cachedPat === cfg.githubPat) {
      return this.octokit;
    }
    this.octokit = createGitHubClient(cfg.githubPat);
    this.cachedPat = cfg.githubPat;
    return this.octokit;
  }

  /**
   * Drain the queue sequentially. For each pending PR:
   *   1. Fetch the full PR context (metadata + diff + file contents) from GitHub.
   *   2. Run the reviewer (P4): per-file LLM review → findings + summary.
   *   3. Classify findings via the diff-line-mapper (inline vs. degraded).
   *   4. Emit `publish:review` as a P5 stub (posted = inline, degraded = degraded).
   *   5. Record the review for dedupe so the next poll skips this commit (R9).
   */
  private async processQueue(): Promise<void> {
    const db = this.db;
    const cfg = this.cfg;
    if (!db || !cfg) return;

    // Retention cleanup — prune terminal-status rows older than 7 days
    pruneQueue(db);
    prunePendingReviews(db);

    const pending = db
      .prepare("SELECT COUNT(*) AS n FROM queue WHERE status = 'pending'")
      .get() as { n: number } | undefined;
    if (!pending || pending.n === 0) return;

    await this.setState("reviewing");

    const claimNext = db.prepare(
      `UPDATE queue SET status = 'processing', claimed_at = ?
       WHERE id = (
         SELECT id FROM queue
         WHERE status = 'pending'
           AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
         ORDER BY id ASC LIMIT 1
       )
       RETURNING id, pr_id, repo, head_sha, number, retry_count`,
    );
    const markDone = db.prepare("UPDATE queue SET status = 'done' WHERE id = ?");
    const markFailed = db.prepare("UPDATE queue SET status = 'failed', fail_reason = ? WHERE id = ?");
    const markRetry = db.prepare(
      `UPDATE queue SET status = 'pending', retry_count = retry_count + 1, next_attempt_at = ?, fail_reason = ? WHERE id = ?`,
    );

    const MAX_QUEUE_RETRIES = 3;
    const now = () => new Date().toISOString();
    const backoffDelays = [60000, 300000, 900000]; // 1min, 5min, 15min

    for (;;) {
      const row = claimNext.get(now(), now()) as QueueRow | undefined;
      if (!row) break;
      try {
        await this.reviewQueueItem(cfg, row);
        markDone.run(row.id);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (row.retry_count < MAX_QUEUE_RETRIES) {
          const delay = backoffDelays[row.retry_count] ?? 900000;
          const nextAttempt = new Date(Date.now() + delay).toISOString();
          markRetry.run(nextAttempt, message, row.id);
        } else {
          markFailed.run(message, row.id);
          getLogger().error(
            { code: "queue_item_dead_letter", prId: row.pr_id, attempts: row.retry_count + 1 },
            message,
          );
        }
      }
    }
  }

  /**
   * Review a single queue item: fetch context → review → line-map → publish stub.
   */
  private async reviewQueueItem(cfg: Config, row: QueueRow): Promise<void> {
    const log = getLogger();
    const db = this.db;
    if (!db) return;

    // G001 budget gate: if a monthly budget is set and already exceeded, skip
    // this review without calling reviewPR. Emits budget:exceeded so the host
    // can surface a paused state in the UI (AC4.7).
    if (cfg.monthlyBudgetUsd > 0) {
      const summary = getMonthlyCostSummary(db, cfg);
      if (summary.monthlyCost >= cfg.monthlyBudgetUsd) {
        log.warn(
          { code: "budget_exceeded", prId: row.pr_id, monthlyCost: summary.monthlyCost, monthlyBudgetUsd: cfg.monthlyBudgetUsd },
          "monthly budget exceeded; skipping review",
        );
        await this.transport.emit({
          type: "event",
          event: "budget:exceeded",
          prId: row.pr_id,
          monthlyCost: summary.monthlyCost,
          monthlyBudgetUsd: cfg.monthlyBudgetUsd,
        });
        await this.emitUsageSummary();
        return;
      }
    }

    // Parse "owner/name" from repo.
    const slash = row.repo.indexOf("/");
    if (slash < 0) {
      log.warn({ code: "bad_repo", repo: row.repo }, "cannot parse owner/name");
      return;
    }
    const owner = row.repo.slice(0, slash);
    const name = row.repo.slice(slash + 1);

    // Fetch the full PR context (meta + diff + files) — the heavy call deferred
    // from the poll loop (R18).
    const octokit = this.getOctokit(cfg);
    const prCtx = await fetchPRContext(octokit, owner, name, row.number);
    // Defensive: the reaper (discover step 0) catches most stale PRs, but a PR
    // can still merge in the small window between reap and review. Bail early
    // rather than post a review on a merged/closed PR.
    if (prCtx.merged || prCtx.state === "closed") {
      log.info(
        { code: "review_skipped_merged", prId: row.pr_id, merged: prCtx.merged },
        "pr no longer open; skipping review",
      );
      await this.transport.emit({
        type: "event",
        event: "poll:skipped",
        prId: row.pr_id,
        reason: prCtx.merged ? "merged" : "closed",
      });
      return;
    }

    // F1: best-effort fetch of per-repo .prreview/rules.md at head_sha
    // (404 / miss ⇒ null ⇒ ignored). Composed with global config rules.
    let repoRules: string | null;
    try {
      repoRules = await fetchFileContent(octokit, owner, name, ".prreview/rules.md", row.head_sha);
    } catch {
      repoRules = null;
    }

    const ctx: ReviewContext = {
      prId: row.pr_id,
      number: row.number,
      repo: row.repo,
      title: prCtx.title,
      body: prCtx.body,
      author: prCtx.author,
      headSha: prCtx.headSha,
      baseSha: prCtx.baseSha,
      url: prCtx.url,
      diff: prCtx.diff,
      files: prCtx.files,
      reviewRules: composeGuidelines(cfg.reviewRules, repoRules),
    };

    // P4: Review (emits review:file per file + review:summary).
    const result = await reviewPR(ctx, cfg);
    // Persist per-file token usage (covers BOTH auto + pending modes).
    // Runs BEFORE the reviewMode branch so a pending-mode createPendingReview
    // throw + queue retry is deduped by INSERT OR IGNORE (H2). result.fileUsage
    // is always present (REQUIRED on ReviewResult).
    for (const fu of result.fileUsage) {
      insertUsage(db, {
        prId: row.pr_id,
        prNumber: row.number,
        repo: row.repo,
        headSha: row.head_sha,
        file: fu.file,
        model: cfg.llmModel,
        usage: fu,
        createdAt: new Date().toISOString(),
      });
    }

    // G001: emit an updated usage:summary after persisting this review's usage
    // so the host UI can update the cost bar live (AC4.8).
    await this.emitUsageSummary();

    // Line-map verification: classify findings as inline or degraded.
    const validLines = parseDiffHunks(prCtx.diff);
    const { inline, degraded } = mapFindings(validLines, result.findings);
    // Pending review mode: create a GitHub PENDING review + store locally.
    if (cfg.reviewMode === "pending") {
      // R24-consistent: if no findings, record + return (no pending row for empty review)
      if (inline.length === 0 && degraded.length === 0) {
        recordReview(db, row.pr_id, row.head_sha);
        return;
      }
      // F1: snapshot the per-file diff subset for files-with-findings only,
      // stored as diff_json so the pending diff viewer renders offline (a PR
      // that merges/closes before approval still reviews from this snapshot).
      const fileDiffs = splitDiffByFile(prCtx.diff);
      const findingFiles = new Set([...inline, ...degraded].map((f) => f.file));
      const diff: Record<string, string> = {};
      for (const f of findingFiles) {
        const h = fileDiffs.get(f);
        if (h) diff[f] = h;
      }
      const diffJson = JSON.stringify(diff);
      if (diffJson.length > 262144) {
        getLogger().warn({ code: "diff_json_large", prId: row.pr_id, bytes: diffJson.length }, "diff_json exceeds 256 KiB");
      }
      // Create a GitHub PENDING review (visible only to the reviewer until
      // submitted/discarded). Throws on fatal error → queue item retries.
      const pendingRes = await createPendingReview(
        octokit,
        owner,
        name,
        row.number,
        { inline, degraded, summary: result.summary },
        { showSeverity: cfg.showSeverity },
      );
      const reviewId = insertPendingReview(db, {
        prId: row.pr_id,
        prNumber: row.number,
        repo: row.repo,
        headSha: row.head_sha,
        title: prCtx.title,
        summary: result.summary,
        inline,
        degraded,
        githubReviewId: pendingRes.reviewId,
        diff,
      });
      // Emit review:pending with the full payload (get stamped findings from DB)
      const pending = getPendingReview(db, reviewId);
      if (pending) {
        await this.transport.emit({
          type: "event",
          event: "review:pending",
          reviewId: pending.reviewId,
          prId: pending.prId,
          prNumber: pending.prNumber,
          repo: pending.repo,
          title: pending.title,
          headSha: pending.headSha,
          summary: pending.summary,
          findings: pending.findings,
          diff: pending.diff,
        });
      }
      return; // do NOT publishReview; do NOT recordReview (deferred to approve/reject)
    }

    // P5: Publish the review to GitHub (atomic POST + progressive trim).
    // Skips silently when there is nothing to say (R24). Never throws on
    // publish-level failures — degrades gracefully so the orchestrator can
    // still record `review_state` below (R27).
    const pubResult = await publishReview(
      octokit,
      owner,
      name,
      row.number,
      { inline, degraded, summary: result.summary },
      { showSeverity: cfg.showSeverity },
    );

    await this.transport.emit({
      type: "event",
      event: "publish:review",
      prId: row.pr_id,
      posted: pubResult.posted,
      degraded: pubResult.degraded,
      retried: pubResult.retried,
    });

    // Record for dedupe so the next poll skips this commit (R9 / R27).
    // Only reached after a successful (or gracefully-degraded) publish.
    recordReview(db, row.pr_id, row.head_sha);
  }

  /** Approve a pending review: resolve → recordReview → submit/discard on GitHub. */
  private async approveReview(reviewId: number, findingIds?: string[], edits?: Record<string, FindingEdit>): Promise<void> {
    const db = this.db;
    const cfg = this.cfg;
    if (!db || !cfg) return;
    const log = getLogger();

    try {
      // F1: recordReview BEFORE publish (decision final even if publish throws)
      const claimed = resolvePendingReview(db, reviewId, "approved");
      if (!claimed) return; // already resolved — idempotent no-op

      recordReview(db, claimed.prId, claimed.headSha);

      const parsed = JSON.parse(claimed.findingsJson) as {
        inline: PendingFinding[];
        degraded: PendingFinding[];
        summary: string;
      };
      // F2: apply user edits (comment/line/severity/suggestion) BEFORE the
      // selection filter. applyEdits never mutates input and only overrides
      // present fields, leaving finding counts unchanged — so the selection-
      // complete comparison below runs against the edited, same-length sets.
      if (edits) {
        parsed.inline = applyEdits(parsed.inline, edits);
        parsed.degraded = applyEdits(parsed.degraded, edits);
      }

      // Parse owner/name once (needed for all GitHub calls below).
      const slash = claimed.repo.indexOf("/");
      if (slash < 0) return;
      const owner = claimed.repo.slice(0, slash);
      const name = claimed.repo.slice(slash + 1);
      const octokit = this.getOctokit(cfg);

      // Best-effort discard helper (the decision is already final via recordReview).
      const safeDiscard = (label: string) =>
        claimed.githubReviewId
          ? discardPendingReview(octokit, owner, name, claimed.prNumber, claimed.githubReviewId).catch((err) => {
              log.warn({ code: label, reviewId }, err instanceof Error ? err.message : String(err));
            })
          : Promise.resolve();

      // Filter to approved subset
      let keepInline = parsed.inline;
      let keepDegraded = parsed.degraded;
      if (findingIds && findingIds.length > 0) {
        const idSet = new Set(findingIds);
        keepInline = parsed.inline.filter((f) => idSet.has(f.id));
        keepDegraded = parsed.degraded.filter((f) => idSet.has(f.id));
      }

      // F10: nothing approved — discard the GitHub pending review, no publish.
      if (keepInline.length === 0 && keepDegraded.length === 0) {
        await safeDiscard("discard_nothing_approved");
        await this.transport.emit({
          type: "event",
          event: "pending:resolved",
          reviewId,
          prId: claimed.prId,
          status: "approved",
        });
        return;
      }

      // F3: re-check PR still open
      const meta = await fetchPRMeta(octokit, owner, name, claimed.prNumber);
      if (meta.merged || meta.state === "closed") {
        log.info({ code: "approve_skipped_merged", prId: claimed.prId }, "pr no longer open at approve time");
        await safeDiscard("discard_merged");
        await this.transport.emit({
          type: "event",
          event: "pending:resolved",
          reviewId,
          prId: claimed.prId,
          status: "approved",
        });
        return;
      }

      // F2: decouple the approval decision. `isSelectionComplete` (full subset OR
      // no subset requested) governs summary preservation: a full approval keeps
      // claimed.summary even when edits force the discard + republish path
      // (submitPendingReview would otherwise surface the original, un-edited
      // content). edits-present ALWAYS forces discard + publishReview.
      const { hasEdits, isSelectionComplete, useSubmitPath } = decideApproval({
        findingIds,
        keepInline: keepInline.length,
        keepDegraded: keepDegraded.length,
        totalInline: parsed.inline.length,
        totalDegraded: parsed.degraded.length,
        edits,
        githubReviewId: claimed.githubReviewId,
      });

      let posted = 0;
      let pubDegraded = 0;
      let retried = 0;
      if (useSubmitPath) {
        await submitPendingReview(octokit, owner, name, claimed.prNumber, claimed.githubReviewId!);
        posted = parsed.inline.length;
        pubDegraded = parsed.degraded.length;
      } else {
        await safeDiscard(hasEdits ? "discard_edited" : "discard_partial");
        const pubResult = await publishReview(
          octokit,
          owner,
          name,
          claimed.prNumber,
          {
            inline: keepInline as any,
            degraded: keepDegraded as any,
            summary: isSelectionComplete ? claimed.summary : "",
          },
          { showSeverity: cfg.showSeverity },
        );
        posted = pubResult.posted;
        pubDegraded = pubResult.degraded;
        retried = pubResult.retried;
      }

      await this.transport.emit({
        type: "event",
        event: "publish:review",
        prId: claimed.prId,
        posted,
        degraded: pubDegraded,
        retried,
      });
      await this.transport.emit({
        type: "event",
        event: "pending:resolved",
        reviewId,
        prId: claimed.prId,
        status: "approved",
      });
    } catch (err) {
      // F4 + M1: emit daemon:error AND pending:resolved (decision already final via recordReview)
      const message = err instanceof Error ? err.message : String(err);
      getLogger().error({ code: "approve_failed", reviewId }, message);
      await this.transport.error("approve_failed", message).catch(() => undefined);
      await this.transport.emit({
        type: "event",
        event: "pending:resolved",
        reviewId,
        prId: 0,
        status: "approved",
      }).catch(() => undefined);
    }
  }

  /** Reject a pending review: resolve → recordReview → discard on GitHub → emit. */
  private async rejectReview(reviewId: number): Promise<void> {
    const db = this.db;
    const cfg = this.cfg;
    if (!db || !cfg) return;
    const log = getLogger();

    try {
      const claimed = resolvePendingReview(db, reviewId, "rejected");
      if (!claimed) return; // already resolved
      recordReview(db, claimed.prId, claimed.headSha);

      // Discard the GitHub pending review so it never becomes visible.
      if (claimed.githubReviewId) {
        const slash = claimed.repo.indexOf("/");
        if (slash >= 0) {
          const owner = claimed.repo.slice(0, slash);
          const name = claimed.repo.slice(slash + 1);
          const octokit = this.getOctokit(cfg);
          await discardPendingReview(octokit, owner, name, claimed.prNumber, claimed.githubReviewId).catch((err) => {
            log.warn({ code: "discard_rejected", reviewId }, err instanceof Error ? err.message : String(err));
          });
        }
      }

      await this.transport.emit({
        type: "event",
        event: "pending:resolved",
        reviewId,
        prId: claimed.prId,
        status: "rejected",
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      getLogger().error({ code: "reject_failed", reviewId }, message);
      await this.transport.error("reject_failed", message).catch(() => undefined);
      await this.transport.emit({
        type: "event",
        event: "pending:resolved",
        reviewId,
        prId: 0,
        status: "rejected",
      }).catch(() => undefined);
    }
  }

  /** Emit a snapshot of all pending reviews (response to pending:list command). */
  private async emitPendingSnapshot(): Promise<void> {
    const db = this.db;
    if (!db) return;
    const reviews = listPendingReviews(db);
    await this.transport.emit({
      type: "event",
      event: "pending:snapshot",
      reviews,
    });
  }

  /**
   * Compute and emit a monthly usage:summary event (response to get_usage command
   * + after each review / budget-exceeded). Requires an active config + DB.
   */
  private async emitUsageSummary(): Promise<void> {
    const db = this.db;
    const cfg = this.cfg;
    if (!db || !cfg) return;
    await this.transport.emit({
      type: "event",
      event: "usage:summary",
      summary: getMonthlyCostSummary(db, cfg),
    });
  }

  private async setState(state: DaemonState): Promise<void> {
    this.state = state;
    await this.transport.status(state);
  }
}

// ---------------------------------------------------------------------------
// G001: cost/budget helpers (extracted for testability)
// ---------------------------------------------------------------------------

/**
 * Compute the month-start ISO timestamp (UTC, first day of current month, 00:00).
 * Used as the cutoff for monthly cost aggregation.
 */
function monthStartIso(): string {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
}

/**
 * Compute the monthly cost summary for the budget gate + usage:summary event.
 * Aggregates per-model token usage since the start of the current (UTC) month,
 * applies per-model pricing (falling back to defaultPer1M for unknown models),
 * and derives a `paused` flag when the budget is set and exceeded (AC4.6).
 */
export function getMonthlyCostSummary(db: DatabaseSync, config: Config): UsageSummary {
  const pricing = parsePricing(config.llmPricing, config.defaultPer1M);
  const rows = getUsageByModelSince(db, monthStartIso());

  const byModel: Record<string, { cost: number; tokens: number }> = {};
  let monthlyCost = 0;
  let tokensThisMonth = 0;
  for (const row of rows) {
    const cost = computeCost(row, row.model, pricing);
    monthlyCost += cost;
    tokensThisMonth += row.totalTokens;
    byModel[row.model] = { cost, tokens: row.totalTokens };
  }

  return {
    monthlyCost,
    monthlyBudgetUsd: config.monthlyBudgetUsd,
    tokensThisMonth,
    paused: config.monthlyBudgetUsd > 0 && monthlyCost >= config.monthlyBudgetUsd,
    byModel,
  };
}

// ---------------------------------------------------------------------------
// F2: pure approval helpers (extracted for testability — see orchestrator.test.ts)
// ---------------------------------------------------------------------------

/**
 * Apply user edits to findings. Returns a NEW array; never mutates the input.
 * For each finding whose `id` appears in `edits`, overrides only the fields
 * present on the edit (comment / line / severity / suggestion). Findings with
 * no matching edit — or edits for unknown ids — are passed through untouched.
 *
 * Edits never add or remove findings, so the result has the same length and
 * order as the input (the selection-complete comparison is stable).
 */
export function applyEdits<T extends {
  id: string;
  comment: string;
  line: number | null;
  severity: string;
  area: string;
  suggestion?: string;
}>(findings: T[], edits: Record<string, FindingEdit>): T[] {
  return findings.map((f) => {
    const edit = edits[f.id];
    if (!edit) return f;
    return {
      ...f,
      ...(edit.comment !== undefined && { comment: edit.comment }),
      ...(edit.line !== undefined && { line: edit.line }),
      ...(edit.severity !== undefined && { severity: edit.severity }),
      ...(edit.suggestion !== undefined && { suggestion: edit.suggestion }),
    } as T;
  });
}

/**
 * Decide the approve path from selection + edits + GitHub review state.
 *
 *   - `hasEdits`            — were any (present) edits supplied?
 *   - `isSelectionComplete` — does the kept subset equal the full set, or was
 *                             no subset requested? Governs summary preservation
 *                             (full approval keeps claimed.summary).
 *   - `useSubmitPath`       — submit the existing PENDING review as COMMENT
 *                             (original content). Only when selection is full,
 *                             there are NO edits, and a github_review_id exists.
 *
 * Edits force the discard + republish path because submitPendingReview would
 * otherwise surface the original (un-edited) comments.
 */
export function decideApproval(args: {
  findingIds?: string[];
  keepInline: number;
  keepDegraded: number;
  totalInline: number;
  totalDegraded: number;
  edits?: Record<string, unknown>;
  githubReviewId: number | null;
}): { hasEdits: boolean; isSelectionComplete: boolean; useSubmitPath: boolean } {
  const hasEdits = !!args.edits && Object.keys(args.edits).length > 0;
  const isSelectionComplete =
    !args.findingIds ||
    (args.keepInline === args.totalInline && args.keepDegraded === args.totalDegraded);
  const useSubmitPath = isSelectionComplete && !hasEdits && !!args.githubReviewId;
  return { hasEdits, isSelectionComplete, useSubmitPath };
}
