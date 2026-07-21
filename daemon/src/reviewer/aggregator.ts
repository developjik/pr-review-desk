/**
 * Aggregator — collect per-file findings into a PR-level summary.
 *
 * Folds all {@link FileReview} objects into a flat findings list, tallies
 * severity counts, and generates a one-paragraph summary. Emits a
 * `review:summary` event on the wire so the host can display the result.
 */
import type {
  FileReview,
  Finding,
  SeverityCounts,
} from "../types/domain";
import { transport } from "../ipc/transport";

export interface AggregateResult {
  findings: Finding[];
  summary: string;
  severityCounts: SeverityCounts;
}

/**
 * Aggregate per-file reviews into a PR-level result and emit `review:summary`.
 *
 * @param fileReviews  One {@link FileReview} per successfully-reviewed file.
 * @param prId         The PR surrogate id (for the wire event).
 */
export function aggregate(fileReviews: FileReview[], prId: number): AggregateResult {
  const findings: Finding[] = [];
  const counts = emptyCounts();

  for (const fr of fileReviews) {
    for (const f of fr.findings) {
      findings.push(f);
      counts[f.severity] += 1;
    }
  }

  const fileCount = fileReviews.length;
  const summary = buildSummary(fileCount, findings.length, counts);

  void transport.emit({
    type: "event",
    event: "review:summary",
    prId,
    summary,
    findings: findings.length,
    severityCounts: counts,
  });

  return { findings, summary, severityCounts: counts };
}

/** Create a zero-initialized severity tally covering all {@link Severity} values. */
function emptyCounts(): SeverityCounts {
  return { info: 0, low: 0, medium: 0, high: 0, critical: 0 };
}

/** Render a human-readable summary line with severity counts. */
function buildSummary(
  fileCount: number,
  findingCount: number,
  counts: SeverityCounts,
): string {
  if (findingCount === 0) {
    return `Reviewed ${fileCount} file${fileCount === 1 ? "" : "s"}. No issues found.`;
  }

  const parts: string[] = [];
  if (counts.high > 0) parts.push(`${counts.high} high`);
  if (counts.medium > 0) parts.push(`${counts.medium} medium`);
  if (counts.low > 0) parts.push(`${counts.low} low`);
  if (counts.info > 0) parts.push(`${counts.info} info`);

  const sevStr = parts.length > 0 ? ` (${parts.join(", ")})` : "";
  return `Reviewed ${fileCount} file${fileCount === 1 ? "" : "s"}, found ${findingCount} issue${findingCount === 1 ? "" : "s"}${sevStr}.`;
}
