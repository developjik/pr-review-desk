/**
 * Reviewer — the per-PR review orchestrator (P4).
 *
 * Given a {@link ReviewContext} (diff + full file contents + PR metadata) and a
 * daemon {@link Config}, this module:
 *
 *   1. Splits the diff by file and runs the {@link chunker} to decide which
 *      files to review (R8: skip oversized diffs, trim large PRs to source).
 *   2. For each reviewable file, calls the {@link LlmClient} with the file
 *      content + diff hunks + PR metadata (the LLM client retries transient
 *      failures internally; a permanently failed file is skipped, R19).
 *   3. Emits a `review:file` event for every file outcome.
 *   4. {@link Aggregates | aggregate} the per-file results into a single
 *      summary, emitting `review:summary`.
 *
 * The orchestrator calls {@link reviewPR}, then runs the diff-line-mapper on
 * the returned findings to classify them as inline/degraded for publishing.
 */
import type { Config } from "../config/schema";
import type {
  FileReview,
  FileUsage,
  ReviewContext,
  ReviewResult,
  TokenUsage,
} from "../types/domain";
import type { ReviewFileStatus } from "@pr-review/shared";
import { getLogger } from "../logging/logger";
import { transport } from "../ipc/transport";
import { splitDiffByFile } from "../linemap/diff-parser";
import { chunkFiles, MAX_CHUNK_DIFF_LINES } from "./chunker";
import { createLlmClient, type LlmClient, type LlmFileReview } from "./llm-client";
import { splitFileIntoChunks, mergeChunkResults } from "./chunk-split";
import { aggregate } from "./aggregator";
import { detectLanguage, type PrPromptMeta } from "./prompts";

/**
 * Review all files in a PR.
 *
 * @returns The aggregated findings, summary, severity counts, and skipped files.
 */
export async function reviewPR(ctx: ReviewContext, config: Config): Promise<ReviewResult> {
  const log = getLogger();
  const llm = createLlmClient(config);
  const language = detectLanguage(ctx.title, ctx.body);

  // (1) Split diff by file → chunker decides what to review.
  const fileDiffs = splitDiffByFile(ctx.diff);
  const { reviewable, skipped } = chunkFiles(ctx.files, fileDiffs, {
    maxDiffLines: config.maxDiffLines,
    maxFiles: config.maxFiles,
    largePrPolicy: config.largePrPolicy,
    fileInclude: config.fileInclude,
    fileExclude: config.fileExclude,
  });
  for (const s of skipped) {
    log.info({ code: "review_skip", prId: ctx.prId, file: s.file, reason: s.reason }, "skipping file");
    await emitFileEvent(ctx.prId, s.file, "skipped", 0);
  }

  // (2) Review each file. Per-file retry lives in the LLM client.
  const prMeta: PrPromptMeta = {
    title: ctx.title,
    body: ctx.body,
    author: ctx.author,
    number: ctx.number,
    repo: ctx.repo,
  };
  const rules = ctx.reviewRules ?? "";

  // Per-file usage accumulators feed the PR aggregate (usageAcc) + a per-file
  // row (fileUsage). ALWAYS initialized so a fully-failed PR still yields a
  // zero-aggregate + empty-array ReviewResult (the #4 guarantee holds even
  // when no LLM call succeeds).
  const usageAcc: TokenUsage = { promptTokens: 0, completionTokens: 0, totalTokens: 0 };
  const fileUsage: FileUsage[] = [];

  const fileReviews: FileReview[] = [];
  for (const file of reviewable) {
    const content = ctx.files[file] ?? "";
    const diffHunks = fileDiffs.get(file) ?? "";
    // Per-file accumulator: mutated by reviewSingleFile as each chunk succeeds.
    // A chunk that throws contributes 0; a fully-failed file stays {0,0,0} and
    // is NOT recorded (null return ⇒ no fileUsage row, AC4.2b).
    const fileAcc: TokenUsage = { promptTokens: 0, completionTokens: 0, totalTokens: 0 };
    const review = await reviewSingleFile(llm, ctx.prId, file, content, diffHunks, prMeta, language, rules, fileAcc);
    if (review) {
      fileReviews.push(review);
      fileUsage.push({ file, ...fileAcc });
      addUsage(usageAcc, fileAcc);
    }
  }

  // (3) Aggregate + emit review:summary (carries the PR-aggregate usage).
  const agg = aggregate(fileReviews, ctx.prId, usageAcc);

  return {
    prId: ctx.prId,
    findings: agg.findings,
    summary: agg.summary,
    severityCounts: agg.severityCounts,
    skipped,
    usage: usageAcc,
    fileUsage,
  };
}
/**
 * Review a single file. Returns null on failure (the file is skipped, R19).
 * The LLM client's own retry loop (MAX_RETRIES) handles transient errors;
 * once exhausted, the file is skipped. Emits `review:file` for every outcome.
 */
async function reviewSingleFile(
  llm: LlmClient,
  prId: number,
  file: string,
  content: string,
  diffHunks: string,
  prMeta: PrPromptMeta,
  language: string,
  rules: string,
  fileAcc: TokenUsage,
): Promise<FileReview | null> {
  try {
    const chunks = splitFileIntoChunks(diffHunks, MAX_CHUNK_DIFF_LINES);

    let result: LlmFileReview;
    if (chunks.length === 1) {
      // FAST PATH == today: full content + whole diffHunks (byte-identical).
      result = await llm.reviewFile(file, content, diffHunks, prMeta, language, rules);
      addUsage(fileAcc, result.usage);
    } else {
      // Multi-chunk: per-chunk try/catch; full content is sent on EVERY call
      // (user override — quality over cost). A thrown chunk is logged + skipped;
      // only when ALL chunks fail does the file fail.
      const successes: LlmFileReview[] = [];
      let lastErr: unknown = new Error(`all chunks failed for ${file}`);
      for (let i = 0; i < chunks.length; i++) {
        try {
          const chunkResult = await llm.reviewFile(file, content, chunks[i], prMeta, language, rules);
          // Accumulate usage BEFORE mergeChunkResults (which folds only
          // findings/summary). A chunk that throws never reaches here ⇒ 0.
          addUsage(fileAcc, chunkResult.usage);
          successes.push(chunkResult);
        } catch (err) {
          lastErr = err;
          getLogger().error(
            { code: "review_chunk_failed", prId, file, chunk: i },
            err instanceof Error ? err.message : String(err),
          );
        }
      }
      if (successes.length === 0) {
        throw lastErr; // all chunks failed ⇒ outer catch ⇒ review:file error + R19 skip
      }
      result = mergeChunkResults(successes);
    }

    const status: ReviewFileStatus = result.findings.length > 0 ? "findings" : "ok";
    await emitFileEvent(prId, file, status, result.findings.length);
    return { file, findings: result.findings, summary: result.summary, usage: fileAcc };
  } catch (err) {
    getLogger().error(
      { code: "review_failed", prId, file },
      err instanceof Error ? err.message : String(err),
    );
    await emitFileEvent(prId, file, "error", 0);
    return null; // skip after retries exhausted (R19)
  }
}

/** Emit a `review:file` event. */
async function emitFileEvent(
  prId: number,
  file: string,
  status: ReviewFileStatus,
  findings: number,
): Promise<void> {
  await transport.emit({
    type: "event",
    event: "review:file",
    prId,
    file,
    status,
    findings,
  });
}
/**
 * Add a (possibly null/absent) per-chunk usage into an accumulator in place.
 * A null/undefined contribution (no `resp.usage`, or a chunk that threw before
 * `resp` existed) adds zero — usage is never fabricated, never NaN.
 */
function addUsage(acc: TokenUsage, usage: TokenUsage | null | undefined): void {
  acc.promptTokens += usage?.promptTokens ?? 0;
  acc.completionTokens += usage?.completionTokens ?? 0;
  acc.totalTokens += usage?.totalTokens ?? 0;
}
