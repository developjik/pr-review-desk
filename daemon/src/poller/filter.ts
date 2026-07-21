/**
 * Discovery filters — repo include/exclude + trigger/skip labels.
 *
 * Pure, dependency-free matcher + two-phase predicate. The poller calls the
 * repo-phase pre-fetchPRMeta (excluded repos skip the meta fetch) and the
 * label-phase post-meta at the shouldReview point; shouldFilterPR exposes the
 * full ordered predicate so BOTH phases can be unit-tested at once.
 *
 * Matcher contract (LOAD-BEARING):
 *   - Case-insensitive: both sides lowercased before matching.
 *   - In-repo only (NO picomatch/minimatch — zero new deps).
 *   - Regex-escaped, anchored (full match), linear: star -> [^/] star (no
 *     backtracking), question -> [^/].
 *   - Segment-local star/question: they never cross a slash. The domain is
 *     owner/repo (exactly one slash), so this is unambiguous for every
 *     realistic pattern (e.g. org/STAR, STAR/widget, org/legacy-STAR); a bare
 *     STAR matches a single segment and does not span owner/repo.
 */
/**
 * Split a newline-separated textarea into trimmed, non-empty rules.
 *
 * Empty/whitespace lines are dropped; surrounding whitespace per line is
 * trimmed. Whitespace-only input yields `[]` (an inert rule set).
 */
export function splitLines(s: string): string[] {
  const out: string[] = [];
  for (const raw of s.split("\n")) {
    const line = raw.trim();
    if (line.length > 0) out.push(line);
  }
  return out;
}

/**
 * Match a single glob `pattern` against a repo name.
 *
 * Both sides are lowercased first. Regex specials in the pattern are escaped
 * (so `.`, `+`, `(`, etc. match literally), then the escaped glob metachars
 * `\*` → `[^/]*` and `\?` → `[^/]` are translated. The result is anchored to
 * the full string. Always returns a real boolean.
 */
export function repoGlob(pattern: string, repo: string): boolean {
  const p = pattern.toLowerCase();
  const r = repo.toLowerCase();
  // Escape every regex special (. + * ? ^ $ ( ) [ ] { } | \), then translate
  // the escaped glob forms. After escaping, glob `*`/`?` are `\*`/`\?`.
  const escaped = p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const translated = escaped
    .replace(/\\\*/g, "[^/]*")
    .replace(/\\\?/g, "[^/]");
  return new RegExp("^" + translated + "$").test(r) === true;
}

/**
 * True if ANY pattern matches the repo (case-insensitive, via {@link repoGlob}).
 * An empty `patterns` array matches nothing (an inert rule set).
 */
export function matchRepo(repo: string, patterns: string[]): boolean {
  for (const pattern of patterns) {
    if (repoGlob(pattern, repo)) return true;
  }
  return false;
}

/** Why a PR was (or would be) filtered out of discovery. */
export type FilterReason = "label:skip" | "repo:exclude" | "repo:include" | "label:trigger";

/** Inputs to the full ordered filter predicate. */
export interface FilterInput {
  repo: string;
  labels: string[];
  repoInclude: string;
  repoExclude: string;
  triggerLabels: string;
  skipLabels: string;
}

/** Outcome of the filter predicate. `filtered: false` carries no `reason`. */
export interface FilterResult {
  filtered: boolean;
  reason?: FilterReason;
}

/**
 * True if `labels` and `rules` share at least one entry, compared
 * case-insensitively. An empty `rules` set intersects nothing.
 */
function intersectIgnoreCase(labels: string[], rules: string[]): boolean {
  if (rules.length === 0) return false;
  const lowerRules = rules.map((l) => l.toLowerCase());
  for (const label of labels) {
    if (lowerRules.includes(label.toLowerCase())) return true;
  }
  return false;
}

/**
 * Full ordered discovery predicate. Phases mirror the runtime split:
 *
 *   Phase 1 (repo, pre-meta):
 *     1. repoExclude hit  → { filtered: true, reason: "repo:exclude" }
 *     2. repoInclude set + miss → { filtered: true, reason: "repo:include" }
 *   Phase 2 (labels, post-meta):
 *     3. skipLabels hit            → { filtered: true, reason: "label:skip" }
 *     4. triggerLabels set + miss  → { filtered: true, reason: "label:trigger" }
 *   else { filtered: false }
 *
 * Empty rule sets are inert. Phase 1 short-circuits before Phase 2 runs
 * (repoExclude+skipLabel → "repo:exclude"); within Phase 2, skip precedes
 * trigger.
 */
export function shouldFilterPR(input: FilterInput): FilterResult {
  // Phase 1: repo filters (pre-meta).
  const exclude = splitLines(input.repoExclude);
  if (matchRepo(input.repo, exclude)) {
    return { filtered: true, reason: "repo:exclude" };
  }
  const include = splitLines(input.repoInclude);
  if (include.length > 0 && !matchRepo(input.repo, include)) {
    return { filtered: true, reason: "repo:include" };
  }

  // Phase 2: label filters (post-meta), case-insensitive.
  const skip = splitLines(input.skipLabels);
  if (intersectIgnoreCase(input.labels, skip)) {
    return { filtered: true, reason: "label:skip" };
  }
  const trigger = splitLines(input.triggerLabels);
  if (trigger.length > 0 && !intersectIgnoreCase(input.labels, trigger)) {
    return { filtered: true, reason: "label:trigger" };
  }

  return { filtered: false };
}
