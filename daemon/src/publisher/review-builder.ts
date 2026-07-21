/**
 * Review-builder — turn the line-mapped findings into a GitHub review payload.
 *
 * Maps the line-mapper output (inline + degraded findings) plus the PR summary
 * into the shape consumed by `POST /repos/:o/:r/pulls/:n/reviews`:
 *
 *   - `event: "COMMENT"` — findings only, no approve/request-changes (R3).
 *   - `body` — PR-level summary, with degraded findings appended as
 *     `` `path:line` — comment `` lines so nothing is lost when a finding
 *     cannot be pinned to a diff line.
 *   - `comments` — one inline comment per inline finding, carrying a fenced
 *     ```suggestion``` block when the finding supplies one (R28).
 *
 * When `showSeverity` is on, every comment body is prefixed with `[SEVERITY]`
 * (e.g. `[HIGH]`, `[MEDIUM]`, `[LOW]`).
 */
import type { Finding, Severity } from "../types/domain";

/** A single inline review comment in the GitHub payload shape. */
export interface ReviewCommentPayload {
  path: string;
  /** 1-based new-side line (validated upstream by the diff-line-mapper). */
  line: number;
  /** Markdown body — may include a fenced ```suggestion block. */
  body: string;
}

/** The full review payload consumed by `octokit.rest.pulls.createReview`. */
export interface ReviewPayload {
  event: "COMMENT" | "PENDING";
  body: string;
  comments: ReviewCommentPayload[];
}

/** Knobs passed through from the daemon {@link Config}. */
export interface ReviewBuilderConfig {
  /** Prefix comment bodies with `[SEVERITY]` when true. */
  showSeverity: boolean;
}

/** The line-mapped shape consumed by the builder. */
export interface MappedReview {
  inline: Finding[];
  degraded: Finding[];
  summary: string;
}

const SEVERITY_TAG: Record<Severity, string> = {
  info: "[INFO]",
  low: "[LOW]",
  medium: "[MEDIUM]",
  high: "[HIGH]",
  critical: "[CRITICAL]",
};

/**
 * Build a GitHub review payload from the line-mapped findings + summary.
 *
 * Inline findings become `comments`; degraded findings are folded into `body`
 * as `` `path:line` — comment `` lines so they are never lost.
 */
export function buildReviewPayload(
  mapped: MappedReview,
  config: ReviewBuilderConfig,
  event: "COMMENT" | "PENDING" = "COMMENT",
): ReviewPayload {
  const comments = mapped.inline.map((f) => buildInlineComment(f, config));
  const body = buildReviewBody(mapped.summary, mapped.degraded, config);
  return { event, body, comments };
}

/** Build a single inline comment payload from one finding. */
export function buildInlineComment(
  finding: Finding,
  config: ReviewBuilderConfig,
): ReviewCommentPayload {
  return {
    path: finding.file,
    // Inline findings always have a non-null line (the mapper guarantees this);
    // the `?? 0` is a defensive fallback that never fires in practice.
    line: finding.line ?? 0,
    body: buildCommentBody(finding, config),
  };
}

/**
 * Build a comment body: optional `[SEVERITY]` prefix, the comment text, and an
 * optional fenced ```suggestion``` block (R28).
 */
export function buildCommentBody(finding: Finding, config: ReviewBuilderConfig): string {
  const parts: string[] = [];
  if (config.showSeverity) parts.push(SEVERITY_TAG[finding.severity]);
  parts.push(finding.comment);
  const body = parts.join(" ");
  if (finding.suggestion && finding.suggestion.trim().length > 0) {
    return `${body}\n\n\`\`\`suggestion\n${finding.suggestion}\n\`\`\``;
  }
  return body;
}

/**
 * Build the review body: PR summary, with degraded findings appended as a
 * bulleted `` `path:line` — comment `` list so they are visible even when the
 * review is collapsed.
 */
export function buildReviewBody(
  summary: string,
  degraded: Finding[],
  config: ReviewBuilderConfig,
): string {
  if (degraded.length === 0) return summary;
  const lines = degraded.map((f) => formatDegradedLine(f, config));
  return `${summary}\n\n---\n\nAdditional findings that could not be placed on a specific line:\n\n${lines.join("\n")}`;
}

/** Format a degraded finding as `` - `path:line` — [SEVERITY] comment ``. */
function formatDegradedLine(finding: Finding, config: ReviewBuilderConfig): string {
  const loc = finding.line !== null ? `${finding.file}:${finding.line}` : finding.file;
  return `- \`${loc}\` — ${buildCommentBody(finding, config)}`;
}
