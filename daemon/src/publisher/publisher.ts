/**
 * Publisher — atomically submit a GitHub PR review (P5).
 *
 * GitHub's review POST is all-or-nothing: a single invalid comment rejects the
 * whole review (HTTP 422). This module handles that atomicity with progressive
 * trim, ensuring no-loss publishing (AC #3 / #7):
 *
 *   1. Build the payload (inline comments + degraded findings folded into body).
 *   2. Fetch existing review comments and drop duplicates (R16).
 *   3. POST the review. On success, post any degraded findings as a separate
 *      PR issue comment so nothing is lost.
 *   4. On HTTP 422, identify the offending comment from the error response when
 *      possible; otherwise binary-search by moving half of the comments into the
 *      degraded set, then re-POST. Repeat up to {@link MAX_TRIM_ROUNDS} times.
 *   5. On HTTP 5xx / network errors, retry the whole POST with backoff.
 *   6. If every inline comment is trimmed away, fall back to a summary-only
 *      review (body only, no comments) so the PR still gets feedback.
 *
 * PRs with no findings are skipped silently (R24).
 */
import type { Octokit } from "@octokit/rest";
import type { Finding } from "../types/domain";
import { getLogger } from "../logging/logger";
import {
  buildCommentBody,
  buildInlineComment,
  buildReviewBody,
  buildReviewPayload,
  type MappedReview,
  type ReviewBuilderConfig,
  type ReviewPayload,
} from "./review-builder";
import { commentKey, fetchExistingComments, partitionByExisting } from "./dedupe";
import { withReviewRetry } from "./retry";

/** Progressive trim is bounded so a pathological payload can't loop forever. */
const MAX_TRIM_ROUNDS = 5;

export type PublisherConfig = ReviewBuilderConfig;

export interface PublishResult {
  /** Inline comments successfully posted in the review. */
  posted: number;
  /** Total findings posted as degraded (original degraded + trimmed-from-inline). */
  degraded: number;
  /** Number of progressive-trim rounds performed (422 recovery). */
  retried: number;
  /** Dedupe-matched findings posted as replies to existing threads (auto mode). */
  replied: number;
}
/** Result of {@link createPendingReview}. */
export interface PendingReviewResult {
  /** GitHub id of the created pending review. */
  reviewId: number;
  /** Inline comments successfully posted in the pending review. */
  posted: number;
  /** Total findings folded into the review body as degraded. */
  degraded: number;
  /** Number of progressive-trim rounds performed (422 recovery). */
  retried: number;
}

/** Error thrown upward from {@link postReviewOnce} when a 422 requires trim. */
class TrimRequiredError extends Error {
  constructor(public readonly original: unknown) {
    super("review rejected with HTTP 422; progressive trim required");
    this.name = "TrimRequiredError";
  }
}

/**
 * Publish the review for a PR. Returns counts for the `publish:review` event.
 *
 * Never throws on publish-level failures — degrades gracefully so the
 * orchestrator can still record `review_state` (R27) and move on. Truly
 * fatal errors (auth, 404) are caught and logged; the returned counts reflect
 * what actually made it to GitHub.
 */
export async function publishReview(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
  mapped: MappedReview,
  config: PublisherConfig,
): Promise<PublishResult> {
  const log = getLogger();

  // R24 — nothing to say, say nothing.
  if (mapped.inline.length === 0 && mapped.degraded.length === 0) {
    return { posted: 0, degraded: 0, retried: 0, replied: 0 };
  }

  // Dedupe inline findings against existing review comments (R16). A failed
  // fetch is non-fatal — treat as "no existing comments" (duplicates are
  // annoying, not corrupting).
  let inline: Finding[];
  let replied = 0;
  try {
    const existing = await fetchExistingComments(octokit, owner, repo, prNumber);

    if (config.replyToThreads) {
      // #7 — instead of dropping dedupe-matched inline findings, reply to them
      // in their existing comment thread. Partition at the comment level (each
      // finding is rendered to its NewComment body), then route matches to
      // `createReplyForReviewComment` and post the rest (`keep`) as a fresh review.
      const pairs = mapped.inline.map((f) => ({
        finding: f,
        comment: buildInlineComment(f, config),
      }));
      const findingByComment = new Map(pairs.map((p) => [p.comment, p.finding]));
      const partition = partitionByExisting(existing, pairs.map((p) => p.comment));

      // `keep` findings post as a normal review below.
      inline = partition.keep
        .map((c) => findingByComment.get(c))
        .filter((f): f is Finding => f !== undefined);

      // `reply` findings are best-effort: each call is isolated; a failure is
      // logged but never throws or retries, and only successes bump `replied`.
      for (const { new: comment, target } of partition.reply) {
        if (target.pull_request_review_id === null) {
          // Standalone (non-review) comment — no owning review_id. Deliberate
          // product policy: only reply into threads owned by a review, so drop
          // this finding rather than auto-reply into a human-authored/standalone
          // thread. (The reply endpoint accepts any comment_id; this is a policy
          // choice, not an API constraint.)
          log.warn(
            {
              code: "reply_no_review_id",
              owner,
              repo,
              prNumber,
              comment_id: target.id,
              path: target.path,
              line: target.line,
            },
            "existing comment has no review_id; dropping finding (no reply)",
          );
          continue;
        }
        try {
          await octokit.rest.pulls.createReplyForReviewComment({
            owner,
            repo,
            pull_number: prNumber,
            comment_id: target.id,
            // The NewComment body == the matched finding's rendered body.
            body: comment.body,
          });
          replied += 1;
        } catch (err) {
          log.warn(
            {
              code: "reply_failed",
              owner,
              repo,
              prNumber,
              comment_id: target.id,
              review_id: target.pull_request_review_id,
            },
            messageOf(err),
          );
        }
      }
    } else {
      // Today's behavior: silently drop dedupe-matched inline findings.
      const existingKeys = new Set(existing.map(commentKey));
      inline = mapped.inline.filter((f) => {
        const comment = buildInlineComment(f, config);
        return !existingKeys.has(commentKey(comment));
      });
    }
  } catch (err) {
    log.warn({ code: "dedupe_fetch_failed", owner, repo, prNumber }, messageOf(err));
    inline = mapped.inline; // fetch failed — keep all inline findings
    replied = 0;
  }

  // Degraded findings — starts with the mapper's degraded set, grows as inline
  // comments are trimmed during 422 recovery.
  const degraded: Finding[] = [...mapped.degraded];

  // Nothing new to post after dedupe (all inline were duplicates, no degraded).
  // `replied` may be non-zero here — replies were already sent above.
  if (inline.length === 0 && degraded.length === 0) {
    return { posted: 0, degraded: 0, retried: 0, replied };
  }

  let postedInline = 0;
  let reviewPosted = false;
  let retried = 0;

  // --- Progressive trim loop -------------------------------------------------
  while (inline.length > 0) {
    const currentInline = [...inline];
    const payload = buildReviewPayload(
      { inline: currentInline, degraded, summary: mapped.summary },
      config,
    );
    try {
      await postReviewOnce(octokit, owner, repo, prNumber, payload);
      postedInline = currentInline.length;
      reviewPosted = true;
      break;
    } catch (err) {
      if (!(err instanceof TrimRequiredError)) {
        // Unrecoverable (auth failure, 404, etc.) — log and bail. Degraded
        // comments are still posted below as a best-effort safety net.
        log.error(
          { code: "review_post_failed", owner, repo, prNumber, inline: currentInline.length },
          messageOf(err),
        );
        break;
      }

      // 422 — progressive trim.
      retried += 1;
      if (retried > MAX_TRIM_ROUNDS) {
        // Trim budget exhausted: move all remaining inline to degraded and
        // fall through to the summary-only review below.
        degraded.push(...inline);
        break;
      }

      const { trim, keep } = pickToTrim(err.original, inline);
      log.info(
        { code: "review_trim", owner, repo, prNumber, round: retried, trimmed: trim.length, kept: keep.length },
        "422 — moving comments to degraded and retrying",
      );
      degraded.push(...trim);
      inline = keep;
    }
  }

  // --- Summary-only fallback -------------------------------------------------
  // If no inline comments survived (or there were none), post a review with
  // just the summary body so the PR still gets feedback.
  if (!reviewPosted && degraded.length > 0) {
    const body = buildReviewBody(mapped.summary, degraded, config);
    try {
      await postReviewOnce(octokit, owner, repo, prNumber, {
        event: "COMMENT",
        body,
        comments: [],
      });
      reviewPosted = true;
    } catch (err) {
      log.error(
        { code: "review_summary_post_failed", owner, repo, prNumber },
        messageOf(err),
      );
    }
  }

  // --- Degraded as standalone PR comment (AC #7 — no-loss) -------------------
  if (degraded.length > 0) {
    const body = renderDegradedComment(degraded, config);
    try {
      await octokit.rest.issues.createComment({
        owner,
        repo,
        issue_number: prNumber,
        body,
      });
    } catch (err) {
      log.warn(
        { code: "degraded_comment_failed", owner, repo, prNumber },
        messageOf(err),
      );
    }
  }

  return { posted: postedInline, degraded: degraded.length, retried, replied };
}
/**
 * Create a GitHub PENDING review (visible only to the reviewer until submitted).
 *
 * Unlike {@link publishReview}, this THROWS on fatal errors so the orchestrator
 * can fail/retry the queue item. Degraded findings are folded into the review
 * body — never posted as a standalone issue comment, since that would be
 * immediately visible and defeat the pending-review semantics.
 */
export async function createPendingReview(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
  mapped: MappedReview,
  config: PublisherConfig,
): Promise<PendingReviewResult> {
  const log = getLogger();

  if (mapped.inline.length === 0 && mapped.degraded.length === 0) {
    throw new Error("createPendingReview called with no findings");
  }

  // Dedupe inline findings against existing review comments (R16).
  let inline: Finding[];
  try {
    const existing = await fetchExistingComments(octokit, owner, repo, prNumber);
    const existingKeys = new Set(existing.map(commentKey));
    inline = mapped.inline.filter((f) => {
      const comment = buildInlineComment(f, config);
      return !existingKeys.has(commentKey(comment));
    });
  } catch (err) {
    log.warn({ code: "dedupe_fetch_failed", owner, repo, prNumber }, messageOf(err));
    inline = mapped.inline;
  }

  const degraded: Finding[] = [...mapped.degraded];

  if (inline.length === 0 && degraded.length === 0) {
    throw new Error("createPendingReview: all findings deduped, nothing to post");
  }

  let postedInline = 0;
  let reviewId = 0;
  let retried = 0;

  // --- Progressive trim loop (event: PENDING) -------------------------------
  while (inline.length > 0) {
    const currentInline = [...inline];
    const payload = buildReviewPayload(
      { inline: currentInline, degraded, summary: mapped.summary },
      config,
      "PENDING",
    );
    try {
      reviewId = await postReviewOnce(octokit, owner, repo, prNumber, payload);
      postedInline = currentInline.length;
      break;
    } catch (err) {
      if (!(err instanceof TrimRequiredError)) throw err; // fatal → propagate
      retried += 1;
      if (retried > MAX_TRIM_ROUNDS) {
        degraded.push(...inline);
        break;
      }
      const { trim, keep } = pickToTrim(err.original, inline);
      log.info(
        { code: "pending_trim", owner, repo, prNumber, round: retried, trimmed: trim.length, kept: keep.length },
        "422 — moving comments to degraded and retrying",
      );
      degraded.push(...trim);
      inline = keep;
    }
  }

  // --- Summary-only fallback (PENDING, body only) ---------------------------
  // All inline comments were trimmed; post a body-only PENDING review so the
  // degraded findings + summary are still captured for later submission.
  if (reviewId === 0 && degraded.length > 0) {
    const body = buildReviewBody(mapped.summary, degraded, config);
    reviewId = await postReviewOnce(octokit, owner, repo, prNumber, {
      event: "PENDING",
      body,
      comments: [],
    });
  }

  if (reviewId === 0) {
    throw new Error("createPendingReview: failed to create any review");
  }

  return { reviewId, posted: postedInline, degraded: degraded.length, retried };
}

/**
 * Submit a pending GitHub review as a COMMENT (makes it visible to everyone).
 * The review's body + inline comments were already attached at creation time.
 */
export async function submitPendingReview(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
  reviewId: number,
): Promise<void> {
  await octokit.rest.pulls.submitReview({
    owner,
    repo,
    pull_number: prNumber,
    review_id: reviewId,
    event: "COMMENT",
  });
}

/**
 * Discard (delete) a pending GitHub review so it never becomes visible.
 */
export async function discardPendingReview(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
  reviewId: number,
): Promise<void> {
  await octokit.rest.pulls.deletePendingReview({
    owner,
    repo,
    pull_number: prNumber,
    review_id: reviewId,
  });
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

/**
 * POST a review payload, retrying on 5xx / network errors. Returns the GitHub
 * review id from the response. Throws {@link TrimRequiredError} on 422 so the
 * caller can progressive-trim.
 */
async function postReviewOnce(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
  payload: ReviewPayload,
): Promise<number> {
  const outcome = await withReviewRetry(async () => {
    try {
      const res = await octokit.rest.pulls.createReview({
        owner,
        repo,
        pull_number: prNumber,
        // GitHub creates a PENDING (unsubmitted) review when `event` is omitted.
        // Passing "PENDING" is not accepted by the REST API.
        ...(payload.event === "COMMENT" ? { event: "COMMENT" } : {}),
        body: payload.body,
        comments: payload.comments,
      });
      return res.data.id;
    } catch (err) {
      if (isUnprocessable(err)) throw new TrimRequiredError(err);
      throw err;
    }
  });
  return outcome.value;
}

/**
 * Pick which inline findings to move to degraded on a 422.
 *
 * Strategy:
 *   1. Try to identify the offending comment(s) from the error response.
 *   2. If that fails, binary-search: keep the front half, move the back half
 *      to degraded, and retry the front half. When only one comment remains,
 *      move it to degraded (it is the offender).
 */
function pickToTrim(
  err: unknown,
  findings: Finding[],
): { trim: Finding[]; keep: Finding[] } {
  const identified = identifyOffending(err, findings);
  if (identified.length > 0) {
    const trimSet = new Set(identified);
    return {
      trim: identified,
      keep: findings.filter((f) => !trimSet.has(f)),
    };
  }

  // Binary search: keep the front half, degrade the back half.
  const keepCount = findings.length > 1 ? Math.floor(findings.length / 2) : 0;
  return {
    trim: findings.slice(keepCount),
    keep: findings.slice(0, keepCount),
  };
}

/** Best-effort: identify the offending comment(s) from a 422 error response. */
function identifyOffending(err: unknown, findings: Finding[]): Finding[] {
  const hints = extractHints(err);
  if (hints.length === 0) return [];

  const identified = new Set<Finding>();
  for (const hint of hints) {
    for (const f of findings) {
      const pathMatch = hint.path === null || hint.path === f.file;
      const lineMatch = hint.line === null || hint.line === f.line;
      if (pathMatch && lineMatch) identified.add(f);
    }
  }
  return [...identified];
}

interface OffendingHint {
  path: string | null;
  line: number | null;
}

/** Extract `(path, line)` hints from a GitHub 422 error response. */
function extractHints(err: unknown): OffendingHint[] {
  if (!err || typeof err !== "object") return [];
  const response = (err as { response?: { data?: unknown } }).response;
  const data = response?.data;
  if (!data || typeof data !== "object") return [];
  const errors = (data as { errors?: unknown }).errors;
  if (!Array.isArray(errors)) return [];

  const hints: OffendingHint[] = [];
  for (const e of errors) {
    if (!e || typeof e !== "object") continue;
    const obj = e as Record<string, unknown>;
    const field = typeof obj.field === "string" ? obj.field : "";
    const value = obj.value;
    const message = typeof obj.message === "string" ? obj.message : "";

    // GitHub sometimes reports the offending line as `value` on a line field.
    if (field.includes("line") && typeof value === "number") {
      hints.push({ path: null, line: value });
    }
    // Try to extract "path:line" from the message text.
    const pathMatch = message.match(/([^\s:]+\.\w+):(\d+)/);
    if (pathMatch) {
      hints.push({ path: pathMatch[1], line: parseInt(pathMatch[2], 10) });
    }
  }
  return hints;
}

/** Render the standalone PR comment body for degraded findings (AC #7). */
function renderDegradedComment(degraded: Finding[], config: PublisherConfig): string {
  const lines = degraded.map((f) => {
    const loc = f.line !== null ? `${f.file}:${f.line}` : f.file;
    return `- \`${loc}\` — ${buildCommentBody(f, config)}`;
  });
  return `### Review findings (not placed inline)\n\n${lines.join("\n")}`;
}

/** Does this error represent a 422 "Validation Failed" from GitHub? */
function isUnprocessable(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  return (err as { status?: unknown }).status === 422;
}

/** Extract a human-readable message from an unknown error. */
function messageOf(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

