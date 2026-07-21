/**
 * Poller — the discovery engine + cron scheduler.
 *
 * Owns the polling cadence (node-cron, `config.pollIntervalMin`) and the
 * discovery pass:
 *
 *   searchReviewRequestedPRs → repo-enumerator (fallback) → dedupe (filter)
 *   → enqueue → emit `poll:found`
 *
 * The poller does NOT own daemon lifecycle state: on each cron tick it invokes
 * `onTick` (the orchestrator's full cycle, which sets `polling`, calls
 * {@link Poller.discover}, processes the queue, and returns to `idle`). This
 * keeps state transitions in one place (orchestrator) while the poller focuses
 * on "when" and "what changed".
 *
 * Reliability:
 *   - R25: a failed discover is caught by the orchestrator; the next tick runs
 *     normally. GitHub rate-limit backoff lives in `github-client`.
 *   - sleep/wake catch-up: `lastPollTime` is recorded; on a tick, if the
 *     elapsed since the last poll exceeds 1.5× the interval we log a catch-up
 *     (the tick itself polls immediately, which is the catch-up action).
 */
import { schedule, validate, type ScheduledTask } from "node-cron";
import type { DatabaseSync } from "node:sqlite";
import type { PrSnapshot } from "@pr-review/shared";
import type { Transport } from "../ipc/transport";
import { getLogger } from "../logging/logger";
import type { Config } from "../config/schema";
import type { Octokit } from "@octokit/rest";
import {
  fetchPRMeta,
  searchReviewRequestedPRs,
  type DiscoveredPR,
} from "./github-client";
import { reapStaleQueue } from "./reaper";
import { enumerateRepos } from "./repo-enumerator";
import { createDedupe } from "./dedupe";
import { prId } from "./util";
import { hasPendingReview } from "../db/pending-reviews";
import { splitLines, matchRepo, shouldFilterPR } from "./filter";

export interface PollerDeps {
  transport: Transport;
  db: DatabaseSync;
  /** Cached Octokit provider (owned by the orchestrator). */
  getOctokit: (cfg: Config) => Octokit;
  /** Full poll cycle (orchestrator-owned): state + discover + queue. */
  onTick: () => Promise<void>;
}

/** Run the expensive repo-enumerator reconciliation every Nth cycle. */
const ENUMERATOR_EVERY_N_CYCLES = 4;
/** Overdue threshold for sleep/wake catch-up (multiples of the interval). */
const CATCH_UP_FACTOR = 1.5;

export class Poller {
  private cfg: Config | null = null;
  private task: ScheduledTask | null = null;
  private lastPollTime: number | null = null;
  private cycleCount = 0;

  /** Lazily-prepared statements (db is stable for the daemon's lifetime). */
  private enqueueStmt: ReturnType<DatabaseSync["prepare"]> | null = null;

  constructor(private readonly deps: PollerDeps) {}

  /** Apply the initial config and start the cron schedule. */
  start(cfg: Config): void {
    this.cfg = cfg;
    this.enqueueStmt = this.deps.db.prepare(
      `INSERT OR IGNORE INTO queue (pr_id, repo, head_sha, number, enqueued_at, status)
       VALUES (?, ?, ?, ?, ?, 'pending')`,
    );
    this.schedule(cfg);
  }

  /** Hot-reload config; reschedule only if the cadence changed. */
  updateConfig(cfg: Config): void {
    const prev = this.cfg;
    this.cfg = cfg;
    if (!prev || prev.pollIntervalMin !== cfg.pollIntervalMin || prev.githubPat !== cfg.githubPat) {
      this.schedule(cfg);
    }
  }

  /** Pause: stop the cron task but keep config (for `pause` command). */
  suspend(): void {
    this.task?.stop();
    this.task = null;
  }

  /** Resume: re-arm the cron with the current config. */
  resume(): void {
    if (this.cfg) this.schedule(this.cfg);
  }

  /** Shutdown: stop scheduling and drop config. */
  stop(): void {
    this.suspend();
    this.cfg = null;
  }

  /**
   * One discovery pass. Emits `poll:found` for each PR newly queued for review.
   * Throws on unrecoverable GitHub errors so the orchestrator can log + recover.
   */
  async discover(): Promise<void> {
    const cfg = this.cfg;
    if (!cfg) return;
    const log = getLogger();

    const octokit = this.deps.getOctokit(cfg);
    const dedupe = createDedupe(this.deps.db);

    // (0) Reap — prune pending entries whose PRs were merged/closed since the
    //     last cycle so they don't linger in the queue forever.
    await reapStaleQueue({
      db: this.deps.db,
      fetchMeta: (owner, repo, number) =>
        fetchPRMeta(octokit, owner, repo, number).catch((err) => {
          log.warn(
            { code: "reap_meta_failed", repo: `${owner}/${repo}`, number },
            err instanceof Error ? err.message : String(err),
          );
          return null;
        }),
      onSkip: (prId, reason) => {
        void this.deps.transport.emit({
          type: "event",
          event: "poll:skipped",
          prId,
          reason,
        });
      },
    });

    // (1) Search — primary discovery path.
    const found = await searchReviewRequestedPRs(octokit, cfg.githubUsername);

    // (2) Enumerator — slow reconciliation pass every Nth cycle (R-8). Search
    //     must have succeeded; the enumerator is best-effort on top of it.
    let extra: DiscoveredPR[] = [];
    this.cycleCount += 1;
    if (this.cycleCount % ENUMERATOR_EVERY_N_CYCLES === 0) {
      try {
        extra = await enumerateRepos(octokit, cfg.githubUsername, found);
      } catch (err) {
        log.warn({ code: "enumerator_failed" }, err instanceof Error ? err.message : String(err));
      }
    }

    // (3) Dedupe + enqueue + emit, per discovered PR.
    const all = [...found, ...extra];
    for (const pr of all) {
      const repo = `${pr.owner}/${pr.repo}`;
      const id = prId(repo, pr.number);
      // Phase 1 — repo include/exclude (PRE-meta: excluded repos skip the fetch).
      if (matchRepo(repo, splitLines(cfg.repoExclude))) {
        log.info({ code: "filtered", reason: "repo:exclude", repo, number: pr.number }, "pr filtered: repo");
        continue;
      }
      const includePatterns = splitLines(cfg.repoInclude);
      if (includePatterns.length > 0 && !matchRepo(repo, includePatterns)) {
        log.info({ code: "filtered", reason: "repo:include", repo, number: pr.number }, "pr filtered: repo");
        continue;
      }

      // Cheap headSha fetch lets us dedupe BEFORE the expensive diff/files pull
      // (which is deferred to the reviewer, P4).
      const meta = await fetchPRMeta(octokit, pr.owner, pr.repo, pr.number).catch((err) => {
        log.warn({ code: "pr_meta_failed", repo, number: pr.number }, err instanceof Error ? err.message : String(err));
        return null;
      });
      if (!meta || !meta.headSha) continue;
      // Phase 2 — label skip/trigger (POST-meta: labels come from pulls.get).
      const labelResult = shouldFilterPR({
        repo,
        labels: meta.labels,
        repoInclude: "",
        repoExclude: "",
        triggerLabels: cfg.triggerLabels,
        skipLabels: cfg.skipLabels,
      });
      if (labelResult.filtered) {
        log.info({ code: "filtered", reason: labelResult.reason, repo, number: pr.number, labels: meta.labels }, "pr filtered: label");
        continue;
      }

      const shouldReview = (await dedupe.shouldReview(id, meta.headSha)) && !hasPendingReview(this.deps.db, id, meta.headSha);
      if (!shouldReview) continue; // already reviewed at this commit (R9)

      this.enqueue(id, repo, meta.headSha, pr.number);
      const snapshot: PrSnapshot = {
        id,
        number: pr.number,
        title: pr.title,
        repo,
        author: pr.author,
        headSha: meta.headSha,
        url: pr.url,
        updatedAt: pr.updatedAt,
      };
      await this.deps.transport.emit({ type: "event", event: "poll:found", pr: snapshot });
    }

    this.lastPollTime = Date.now();
  }

  // ----------------------------------------------------------------- internals

  private schedule(cfg: Config): void {
    this.task?.stop();
    this.task = null;
    const minutes = Math.max(1, cfg.pollIntervalMin);
    const expr = `*/${minutes} * * * *`;
    if (!validate(expr)) {
      getLogger().error({ code: "bad_cron", expr }, "invalid cron expression");
      return;
    }
    this.task = schedule(expr, () => {
      void this.tick();
    });
  }

  private async tick(): Promise<void> {
    const cfg = this.cfg;
    if (!cfg) return;
    const log = getLogger();

    // sleep/wake catch-up detection (informational; the tick polls regardless).
    if (this.lastPollTime !== null) {
      const intervalMs = Math.max(1, cfg.pollIntervalMin) * 60_000;
      const elapsed = Date.now() - this.lastPollTime;
      if (elapsed > CATCH_UP_FACTOR * intervalMs) {
        log.info({ elapsedMs: elapsed }, "catch-up poll: overdue since last cycle");
      }
    }

    try {
      await this.deps.onTick();
    } catch (err) {
      // Defensive: the orchestrator's cycle handles its own errors, but a stray
      // throw here must not kill the cron loop (R25).
      log.error({ code: "poll_tick_failed" }, err instanceof Error ? err.message : String(err));
    }
  }

  private enqueue(prId: number, repo: string, headSha: string, number: number): void {
    this.enqueueStmt?.run(prId, repo, headSha, number, new Date().toISOString());
  }
}
