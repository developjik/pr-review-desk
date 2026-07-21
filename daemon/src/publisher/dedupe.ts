/**
 * Dedupe — skip review comments already posted on the PR (R16).
 *
 * GitHub offers no idempotency for review comments. To avoid re-posting
 * identical comments on a re-review of the same commit (e.g. after a partial
 * publish + retry), we fetch the existing review comments and drop any new
 * comment whose `(path, line, body)` triple already exists.
 */
import type { Octokit } from "@octokit/rest";

/** Minimal shape of an existing review comment, for dedupe comparison. */
export interface ExistingComment {
  path: string;
  line: number | null;
  body: string;
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
