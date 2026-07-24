/**
 * Dedupe — skip review comments already posted on the PR (R16).
 *
 * GitHub offers no idempotency for review comments. To avoid re-posting
 * identical comments on a re-review of the same commit (e.g. after a partial
 * publish + retry), we fetch the existing review comments and drop any new
 * comment whose `(path, line, body)` triple already exists.
 */
import type { Octokit } from "@octokit/rest";

/** Minimal shape of an existing review comment, for dedupe + reply routing. */
export interface ExistingComment {
  path: string;
  line: number | null;
  body: string;
  /** GitHub review-comment id (used as `comment_id` for replies). */
  id: number;
  /** Owning review id (used as `review_id` for replies); null when unknown. */
  pull_request_review_id: number | null;
}

/** New-comment shape used for dedupe (mirrors {@link ReviewCommentPayload}). */
export interface NewComment {
  path: string;
  line: number;
  body: string;
}

/**
 * Stable key for dedupe comparison: `path \0 line \0 body`.
 *
 * Exported so the publisher can build the same key for inline findings.
 */
export function commentKey(c: {
  path: string;
  line: number | null;
  body: string;
}): string {
  return `${c.path}\u0000${c.line ?? ""}\u0000${c.body}`;
}

/**
 * Fetch existing review comments on a PR.
 *
 * `GET /repos/:o/:r/pulls/:n/comments` — paginated; we fetch the first 100,
 * which is sufficient for the typical review size. A failure to fetch (e.g.
 * transient 5xx) is non-fatal: the publisher treats it as "no existing
 * comments" and proceeds (duplicates are annoying, not corrupting).
 */
export async function fetchExistingComments(
  octokit: Octokit,
  owner: string,
  repo: string,
  prNumber: number,
): Promise<ExistingComment[]> {
  const resp = await octokit.rest.pulls.listReviewComments({
    owner,
    repo,
    pull_number: prNumber,
    per_page: 100,
  });
  return resp.data.map((c) => ({
    path: c.path ?? "",
    line: c.line ?? c.original_line ?? null,
    body: c.body ?? "",
    id: c.id,
    pull_request_review_id: c.pull_request_review_id ?? null,
  }));
}

/**
 * Drop new comments that already exist on the PR (same path + line + body).
 *
 * @returns New comments that are NOT duplicates of any existing comment.
 */
export function filterDuplicates(
  existing: ExistingComment[],
  newComments: NewComment[],
): NewComment[] {
  const keys = new Set(existing.map(commentKey));
  return newComments.filter((c) => !keys.has(commentKey(c)));
}
/**
 * Partition new comments into those with no existing match (`keep`) and those
 * that match an existing comment (`reply`), carrying the matched existing
 * comment so the publisher can reply into the original thread.
 *
 * Stable first-match tie-break: when several existing comments share a key, the
 * FIRST one (in `existing` order) is chosen as the reply target. Each new
 * comment is routed independently — two new comments matching the same thread
 * each produce their own reply.
 *
 * @returns `keep` posts as a fresh review; `reply` are sent via
 * `octokit.rest.pulls.createReviewReply`.
 */
export function partitionByExisting(
  existing: ExistingComment[],
  newComments: NewComment[],
): { keep: NewComment[]; reply: { new: NewComment; target: ExistingComment }[] } {
  const keep: NewComment[] = [];
  const reply: { new: NewComment; target: ExistingComment }[] = [];
  for (const nc of newComments) {
    const key = commentKey(nc);
    const target = existing.find((e) => commentKey(e) === key);
    if (target) reply.push({ new: nc, target });
    else keep.push(nc);
  }
  return { keep, reply };
}
