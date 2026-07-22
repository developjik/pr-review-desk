/**
 * Domain types for the PR Review daemon.
 *
 * These describe the in-process model used by the orchestrator / poller /
 * reviewer / publisher. They are richer than the wire snapshots in
 * `@pr-review/shared` (which only carry what crosses the IPC boundary).
 */

/** Lifecycle of a GitHub pull request as observed by the poller. */
export type PrState = "open" | "closed" | "merged" | "draft";

/** A pull request tracked by the daemon. */
export interface PullRequest {
  /** Internal surrogate id (DB primary key). */
  id: number;
  /** GitHub PR number within the repo. */
  number: number;
  title: string;
  state: PrState;
  repo: string; // "owner/name"
  author: string;
  headSha: string;
  baseSha: string;
  url: string;
  updatedAt: string; // ISO 8601
}

/** Severity bucket for a single finding (used when showSeverity is on). */
export type Severity = "info" | "low" | "medium" | "high" | "critical";

/** A single LLM-produced review comment, pre-line-map classification. */
export interface ReviewFinding {
  id: string;
  file: string;
  /** New-side line number, or null when the finding cannot be mapped inline. */
  line: number | null;
  severity: Severity;
  rule: string;
  message: string;
  /** True when the line falls inside the diff hunk (inline comment candidate). */
  inline: boolean;
}

/** Per-file outcome reported on the `review:file` event. */
export type ReviewFileStatus = "ok" | "findings" | "skipped" | "error";

export interface ReviewFileResult {
  prId: number;
  file: string;
  status: ReviewFileStatus;
  findings: number;
}

/** A complete review for a PR, including publish accounting. */
export interface Review {
  prId: number;
  createdAt: string; // ISO 8601
  findings: ReviewFinding[];
  posted: number;
  degraded: number;
  retried: number;
}

// ---------------------------------------------------------------------------
// P4 — Reviewer model (LLM-produced, pre-line-map classification)
// ---------------------------------------------------------------------------

/** The four review areas the LLM is asked to cover. */
export type Area = "bug" | "style" | "structure" | "security";

/**
 * A single LLM-produced finding, as returned by the reviewer.
 *
 * Distinct from {@link ReviewFinding} (the wire/DB type with an `inline` flag
 * and a stable `id`): this is the raw shape emitted by the LLM client before
 * diff-line-map classification.
 */
export interface Finding {
  file: string;
  /** New-side line number, or null when the LLM could not pin one down. */
  line: number | null;
  severity: Severity;
  area: Area;
  comment: string;
  /** Optional suggested fix (suggestion block, R28). */
  suggestion?: string;
}

/**
 * Token usage reported by the LLM provider for a single review (or aggregated
 * across a file / PR). The canonical home for this type; `FileUsage` (below)
 * and the DB layer re-export / extend it.
 */
export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

/** Token usage tagged with the file it was billed against (`null` = aggregate). */
export interface FileUsage extends TokenUsage {
  file: string | null;
}

/** A file the chunker decided not to send to the LLM. */
export interface SkippedFile {
  file: string;
  reason: string;
}

/** Per-file review output (LLM response for one file). */
export interface FileReview {
  file: string;
  findings: Finding[];
  summary: string;
  usage?: TokenUsage | null;
}

/** Tally of findings by severity. */
export type SeverityCounts = Record<Severity, number>;

/** Complete review result for a PR (returned by the reviewer). */
export interface ReviewResult {
  prId: number;
  findings: Finding[];
  summary: string;
  severityCounts: SeverityCounts;
  skipped: SkippedFile[];
  usage: TokenUsage;
  fileUsage: FileUsage[];
}

/**
 * Everything the reviewer needs to review a PR.
 *
 * Built by the orchestrator from the queue row + `fetchPRContext`. The wire
 * types in `@pr-review/shared` only carry snapshots; this carries the full diff
 * and file contents needed for LLM review.
 */
export interface ReviewContext {
  prId: number;
  number: number;
  repo: string; // "owner/name"
  title: string;
  body: string;
  author: string;
  headSha: string;
  baseSha: string;
  url: string;
  /** Unified diff of the PR. */
  diff: string;
  /** Full new-side contents of each changed file: path -> source. */
  files: Record<string, string>;
  /** Composed review guidelines (global config rules + per-repo .prreview/rules.md). */
  reviewRules?: string;
}
