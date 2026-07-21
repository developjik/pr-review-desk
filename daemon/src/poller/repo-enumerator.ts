/**
 * Repo enumerator — Search-index lag fallback (R-8).
 *
 * GitHub's `/search/issues` index trails canonical state by a few seconds, so a
 * freshly review-requested PR can be absent from search results. This module
 * reconciles by walking the authenticated user's repos (`/user/repos`), listing
 * each repo's open PRs, and keeping only those whose `requested_reviewers`
 * include `username` and that were NOT already returned by the search step.
 *
 * It is expensive (1 + (#repos) requests), so the poller only runs it on a slow
 * cadence (every Nth cycle) and only as a reconciliation pass over the search
 * result set — never as the primary discovery path.
 */
import type { Octokit } from "@octokit/rest";
import { withRateLimitRetry, type DiscoveredPR } from "./github-client";

/**
 * Discover review-requested PRs missed by the search step.
 *
 * @param known PRs already returned by {@link searchReviewRequestedPRs}; these
 *              are de-duplicated against so the result contains only additions.
 */
export async function enumerateRepos(
  octokit: Octokit,
  username: string,
  known: DiscoveredPR[],
): Promise<DiscoveredPR[]> {
  const seen = new Set(known.map((p) => `${p.owner}/${p.repo}#${p.number}`));
  const extra: DiscoveredPR[] = [];

  const repos = await withRateLimitRetry(() =>
    octokit.rest.repos.listForAuthenticatedUser({
      affiliation: "owner,collaborator,organization_member",
      per_page: 100,
    }),
  );

  for (const repo of repos.data) {
    const { full_name } = repo;
    const slash = full_name.indexOf("/");
    if (slash < 0) continue;
    const owner = full_name.slice(0, slash);
    const name = full_name.slice(slash + 1);

    let pulls: Awaited<ReturnType<typeof octokit.rest.pulls.list>>["data"];
    try {
      const resp = await withRateLimitRetry(() =>
        octokit.rest.pulls.list({ owner, repo: name, state: "open", per_page: 100 }),
      );
      pulls = resp.data;
    } catch {
      // A single repo failure (private/suspended/etc) must not abort the pass.
      continue;
    }

    for (const pr of pulls) {
      if (pr.draft === true) continue; // R22
      const reviewers = pr.requested_reviewers ?? [];
      if (!reviewers.some((r) => r?.login === username)) continue;
      const key = `${owner}/${name}#${pr.number}`;
      if (seen.has(key)) continue;
      seen.add(key);
      extra.push({
        number: pr.number,
        owner,
        repo: name,
        title: pr.title ?? "",
        author: pr.user?.login ?? "",
        url: pr.html_url ?? "",
        updatedAt: pr.updated_at ?? "",
      });
    }
  }

  return extra;
}
