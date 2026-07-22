/**
 * GitHub REST client.
 *
 * Thin wrapper over `@octokit/rest` providing the three operations the poller
 * needs:
 *   - {@link searchReviewRequestedPRs} — PRs with `review-requested:<user>`.
 *   - {@link fetchPRMeta}               — lightweight PR metadata incl. headSha.
 *   - {@link fetchPRContext}            — full review payload (meta + diff +
 *                                         changed file contents); used by P4.
 *
 * All requests funnel through {@link withRateLimitRetry}, which handles the
 * "secondary" / "primary" rate-limit case (HTTP 403 + `X-RateLimit-Remaining:
 * 0`) by sleeping the `Retry-After` window and retrying (R25).
 */
import { Octokit } from "@octokit/rest";
import { sleep } from "./util";
import pLimit from "p-limit";

/** A PR discovered by the search / enumeration steps (no headSha yet). */
export interface DiscoveredPR {
  number: number;
  owner: string;
  repo: string; // "owner/name" split for direct octokit calls
  title: string;
  author: string;
  url: string;
  updatedAt: string; // ISO 8601
}

/** Lightweight PR metadata returned by {@link fetchPRMeta}. */
export interface PRMeta {
  title: string;
  body: string;
  headSha: string;
  baseSha: string;
  /** Has the PR been merged into its base branch? */
  merged: boolean;
  /** GitHub lifecycle state (`open` vs `closed`). */
  state: "open" | "closed";
  author: string;
  url: string;
  /**
   * PR label names (daemon-internal). Extracted from `pulls.get` for the
   * discovery skip/trigger label filters. NEVER placed on the wire
   * {@link PrSnapshot} — the poller consumes it locally at the shouldReview
   * gate and drops it before emitting.
   */
  labels: string[];
}

/** Full per-PR payload consumed by the reviewer (P4). */
export interface PRContext extends PRMeta {
  /** Unified diff of the PR (Accept: application/vnd.github.v3.diff). */
  diff: string;
  /** Full new-side contents of each changed file: path -> source. */
  files: Record<string, string>;
}

/** Fetch the authenticated user's login from the PAT (GET /user). */
export async function fetchAuthenticatedUser(octokit: Octokit): Promise<string> {
  const resp = await withRateLimitRetry(() => octokit.rest.users.getAuthenticated());
  return resp.data.login;
}

const MAX_RATE_LIMIT_RETRIES = 3;
const DEFAULT_RETRY_AFTER_SEC = 60;

/** Build an authenticated Octokit for the given PAT. `baseUrl` resolves from the
 *  explicit arg, then `PR_GITHUB_API_BASE_URL` (GitHub Enterprise / e2e mock),
 *  then the Octokit default (api.github.com). */
export function createGitHubClient(pat: string, baseUrl?: string): Octokit {
  const resolvedBase = baseUrl ?? process.env.PR_GITHUB_API_BASE_URL;
  return new Octokit({
    auth: pat,
    ...(resolvedBase ? { baseUrl: resolvedBase } : {}),
  });
}

/**
 * Run a request thunk, retrying on rate-limit exhaustion.
 *
 * Non-rate-limit errors propagate immediately (e.g. 401 on a bad PAT is not a
 * retryable condition). R25.
 */
export async function withRateLimitRetry<T>(
  thunk: () => Promise<T>,
  maxRetries: number = MAX_RATE_LIMIT_RETRIES,
): Promise<T> {
  let attempt = 0;
  while (true) {
    try {
      return await thunk();
    } catch (err) {
      if (!isRateLimited(err) || attempt >= maxRetries) throw err;
      const secs = retryAfterSeconds(err);
      await sleep(secs * 1000);
      attempt += 1;
    }
  }
}

/**
 * Search open, non-draft PRs with a review requested from `username` (R22:
 * draft PRs are excluded here; the enumerator mirrors this filter).
 *
 * Note: the search index lags the canonical state by a few seconds; the
 * repo-enumerator reconciles stragglers. See `repo-enumerator.ts` (R-8).
 */
export async function searchReviewRequestedPRs(
  octokit: Octokit,
  username: string,
): Promise<DiscoveredPR[]> {
  const resp = await withRateLimitRetry(() =>
    octokit.paginate(octokit.rest.search.issuesAndPullRequests, {
      q: `review-requested:${username} is:pr is:open`,
      per_page: 100,
    }),
  );
  const out: DiscoveredPR[] = [];
  for (const item of resp) {
    if (item.draft === true) continue; // R22 — drafts excluded
    const parsed = parseRepoFromUrl(item.repository_url);
    if (!parsed) continue;
    out.push({
      number: item.number,
      owner: parsed.owner,
      repo: parsed.name,
      title: item.title ?? "",
      author: item.user?.login ?? "",
      url: item.html_url,
      updatedAt: item.updated_at ?? "",
    });
  }
  return out;
}

/** Fetch the PR JSON (no diff) — cheap headSha source for dedupe. */
export async function fetchPRMeta(
  octokit: Octokit,
  owner: string,
  repo: string,
  pullNumber: number,
): Promise<PRMeta> {
  const resp = await withRateLimitRetry(() =>
    octokit.rest.pulls.get({ owner, repo, pull_number: pullNumber }),
  );
  return {
    title: resp.data.title ?? "",
    body: resp.data.body ?? "",
    headSha: resp.data.head?.sha ?? "",
    baseSha: resp.data.base?.sha ?? "",
    merged: resp.data.merged ?? false,
    state: resp.data.state === "closed" ? "closed" : "open",
    author: resp.data.user?.login ?? "",
    url: resp.data.html_url ?? "",
    labels: (resp.data.labels ?? [])
      .map((l) => (l?.name ?? "") as string)
      .filter((name): name is string => name.length > 0),
  };
}

/**
 * Fetch the full review payload: metadata + diff + new-side contents of every
 * changed file (R18). Deleted files are skipped (no content at the head).
 *
 * Heavy call — invoked by the reviewer (P4), not by the poll loop. The poller
 * uses {@link fetchPRMeta} for the cheap headSha needed to dedupe.
 */
export async function fetchPRContext(
  octokit: Octokit,
  owner: string,
  repo: string,
  pullNumber: number,
): Promise<PRContext> {
  const meta = await fetchPRMeta(octokit, owner, repo, pullNumber);
  const diff = await fetchPRDiff(octokit, owner, repo, pullNumber);
  const files = await fetchChangedFiles(octokit, owner, repo, pullNumber, meta.headSha);
  return { ...meta, diff, files };
}

/** Fetch the raw unified diff (`Accept: application/vnd.github.v3.diff`). */
export async function fetchPRDiff(
  octokit: Octokit,
  owner: string,
  repo: string,
  pullNumber: number,
): Promise<string> {
  const resp = await withRateLimitRetry(() =>
    octokit.rest.pulls.get({
      owner,
      repo,
      pull_number: pullNumber,
      mediaType: { format: "diff" },
    }),
  );
  // With the diff media type the body is the raw diff string; guard the shape.
  return typeof resp.data === "string" ? resp.data : String(resp.data ?? "");
}

/** Fetch full new-side contents of each changed file at `headSha` (R18). */
export async function fetchChangedFiles(
  octokit: Octokit,
  owner: string,
  repo: string,
  pullNumber: number,
  headSha: string,
): Promise<Record<string, string>> {
  const list = await withRateLimitRetry(() =>
    octokit.paginate(octokit.rest.pulls.listFiles, {
      owner, repo, pull_number: pullNumber, per_page: 100,
    }),
  );
  const limit = pLimit(4); // cap at 4 concurrent fetches
  const entries = await Promise.all(
    list
      .filter((f) => f.status !== "removed")
      .map((f) =>
        limit(() =>
          fetchFileContent(octokit, owner, repo, f.filename, headSha).then(
            (content) => [f.filename, content] as const,
          ),
        ),
      ),
  );
  const files: Record<string, string> = {};
  for (const [filename, content] of entries) {
    if (content !== null) files[filename] = content;
  }
  return files;
}
/**
 * Fetch the `base..head` compare for incremental review (G002). Returns the
 * unified diff + compare `status` ("ahead" when base is a clean ancestor of
 * head; "diverged"/"behind" on force-push/rebase) + the changed-file list.
 * On any failure (base not an ancestor → 404, rate limit, network) returns
 * `{ diff: null, status: null, changedFiles: [] }` so the caller falls back to
 * a full `base..head` review — incremental never blocks a review.
 */
export async function fetchCompareDiff(
  octokit: Octokit,
  owner: string,
  repo: string,
  base: string,
  head: string,
): Promise<{ diff: string | null; status: string | null; changedFiles: string[] }> {
  try {
    // JSON call: status + changed-file names (determines ahead vs fallback).
    const resp = await withRateLimitRetry(() =>
      octokit.rest.repos.compareCommits({ owner, repo, base, head }),
    );
    const status = (resp.data as { status?: string }).status ?? null;
    const files = (resp.data as { files?: { filename?: string }[] }).files ?? [];
    const changedFiles = files.map((f) => f.filename ?? "").filter((f) => f.length > 0);
    if (status !== "ahead") {
      // diverged/behind (force-push/rebase) — caller falls back to full review.
      return { diff: null, status, changedFiles };
    }
    // Diff call: the unified diff for the ahead compare (same format as
    // fetchPRContext's diff).
    const diffResp = await withRateLimitRetry(() =>
      octokit.rest.repos.compareCommits({
        owner,
        repo,
        base,
        head,
        headers: { accept: "application/vnd.github.v3.diff" },
      }),
    );
    const diff = typeof diffResp.data === "string" ? diffResp.data : null;
    return { diff: diff ?? "", status, changedFiles };
  } catch {
    // base not an ancestor (404) or transient error — fall back to full review.
    return { diff: null, status: null, changedFiles: [] };
  }
}

/** Fetch a single file's contents at `ref`; `null` if unavailable (404 etc). */
export async function fetchFileContent(
  octokit: Octokit,
  owner: string,
  repo: string,
  path: string,
  ref: string,
): Promise<string | null> {
  try {
    const resp = await withRateLimitRetry(() =>
      octokit.rest.repos.getContent({ owner, repo, path, ref }),
    );
    const data = resp.data;
    // A single file is returned as a content object; dirs/submodules differ.
    if (typeof data === "object" && data !== null && "content" in data) {
      const raw = (data as { content?: string; encoding?: string }).content;
      const encoding = (data as { encoding?: string }).encoding;
      if (typeof raw === "string") {
        if (encoding === "base64") {
          return Buffer.from(raw, "base64").toString("utf8");
        }
        return raw;
      }
    }
    return null;
  } catch {
    // Binary, too large, or missing at ref — skip gracefully.
    return null;
  }
}

// ----------------------------------------------------------------------------- internals

/** Parse `https://api.github.com/repos/{owner}/{name}` into its parts. */
function parseRepoFromUrl(repositoryUrl: string): { owner: string; name: string } | null {
  const marker = "/repos/";
  const idx = repositoryUrl.indexOf(marker);
  if (idx < 0) return null;
  const tail = repositoryUrl.slice(idx + marker.length);
  const [owner, name] = tail.split("/");
  if (!owner || !name) return null;
  return { owner, name };
}

/** Does this octokit error represent rate-limit exhaustion (R25)? */
function isRateLimited(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const e = err as { status?: unknown; response?: { headers?: Record<string, unknown>; data?: unknown } };
  if (e.status !== 403) return false;

  // Primary rate limit
  const headers = e.response?.headers ?? {};
  const remaining = headers["x-ratelimit-remaining"] ?? headers["X-RateLimit-Remaining"];
  if (remaining === "0" || remaining === 0) return true;

  // Secondary rate limit: 403 with retry-after header
  const retryAfter = headers["retry-after"] ?? headers["Retry-After"];
  if (retryAfter !== undefined) return true;

  // Secondary rate limit: body text
  const data = e.response?.data;
  if (data && typeof data === "object") {
    const msg = JSON.stringify(data).toLowerCase();
    if (msg.includes("secondary rate limit") || msg.includes("abuse")) return true;
  }

  return false;
}

/** Seconds to wait before retrying, from `Retry-After` (R25). */
function retryAfterSeconds(err: unknown): number {
  if (!err || typeof err !== "object") return DEFAULT_RETRY_AFTER_SEC;
  const headers = (err as { response?: { headers?: Record<string, unknown> } }).response
    ?.headers ?? {};
  const raw = headers["retry-after"] ?? headers["Retry-After"];
  const n = typeof raw === "string" ? parseInt(raw, 10) : Number.NaN;
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_RETRY_AFTER_SEC;
}
