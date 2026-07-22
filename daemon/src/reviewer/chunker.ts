/**
 * Chunker — file-level filtering before LLM review (R8).
 *
 * Two rules:
 *   1. **Diff size limit**: files whose diff exceeds
 *      {@link ABSOLUTE_MAX_DIFF_LINES} (5000) lines are skipped. Files with
 *      501–5000 diff lines are still reviewed (split into ≤500-line hunk
 *      chunks by the reviewer); {@link MAX_DIFF_LINES} (500) is kept as the
 *      legacy per-chunk budget reference.
 *   2. **File budget**: when a PR exceeds {@link MAX_FILES} (50) reviewable
 *      files, lower-priority files (tests, docs, generated) are dropped in
 *      favor of source code.
 *
 * The function is pure: it takes the files map + per-file diff text and
 * returns the reviewable file paths + skipped reasons. The caller (reviewer)
 * iterates the reviewable set and looks up content/diff from its own maps.
 */
import type { SkippedFile } from "../types/domain";
import { matchAnyPath } from "../util/glob";
import { splitLines } from "../poller/filter";

/**
 * Legacy maximum diff lines per file (R8); kept as a per-chunk budget reference.
 * @deprecated use {@link ChunkOptions.maxDiffLines}; kept for backward-compat imports.
 */
export const MAX_DIFF_LINES = 500;
/**
 * Maximum reviewable files per PR before lower-priority files are trimmed (R8).
 * The default source for {@link ChunkOptions.maxFiles} — `chunkFiles` reads it
 * directly when the caller omits the override.
 */
export const MAX_FILES = 50;
/**
 * Hard-skip ceiling: only diffs larger than this many lines are skipped (R8).
 * The default source for {@link ChunkOptions.maxDiffLines} — `chunkFiles` reads
 * it directly when the caller omits the override.
 */
export const ABSOLUTE_MAX_DIFF_LINES = 5000;
/**
 * Per-chunk diff-line budget used when splitting a large file's diff across
 * multiple LLM calls (F2). Equals the legacy {@link MAX_DIFF_LINES} limit so a
 * file ≤500 diff lines reviews byte-for-byte identical to today.
 */
export const MAX_CHUNK_DIFF_LINES = 500;

/** Extensions treated as primary source code (highest review priority). */
const SOURCE_EXTENSIONS = new Set([
  ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".vue", ".svelte",
  ".py", ".rb", ".go", ".rs", ".java", ".kt", ".swift",
  ".c", ".h", ".cpp", ".cc", ".cxx", ".hpp", ".hh",
  ".cs", ".php", ".scala", ".clj", ".ex", ".exs", ".erl", ".hs",
  ".ml", ".lua", ".r", ".dart", ".jl", ".zig", ".nim",
]);

/** Extensions treated as documentation (lowest review priority). */
const DOC_EXTENSIONS = new Set([
  ".md", ".markdown", ".txt", ".rst", ".adoc", ".asciidoc", ".org",
]);

/** Patterns identifying test / fixture files (lowest priority after docs). */
const TEST_PATTERNS = [
  /\.test\./i,
  /\.spec\./i,
  /(?:^|\/)tests?\//i,
  /(?:^|\/)__tests__\//i,
  /(?:^|\/)__fixtures__\//i,
  /(?:^|\/)__mocks__\//i,
];

export interface ChunkResult {
  /** File paths cleared for LLM review. */
  reviewable: string[];
  /** Files excluded, each with a human-readable reason. */
  skipped: SkippedFile[];
}

/**
 * Per-call overrides for {@link chunkFiles}. All fields optional; omitted
 * fields fall back to defaults equal to the prior hardcoded behavior
 * (`maxDiffLines=5000`, `maxFiles=50`, `largePrPolicy="trim"`, empty globs).
 */
export interface ChunkOptions {
  /** Per-file diff-line skip ceiling (default: {@link ABSOLUTE_MAX_DIFF_LINES}). */
  maxDiffLines?: number;
  /** Reviewable-files budget before trim/abort (default: {@link MAX_FILES}). */
  maxFiles?: number;
  /** Over-budget policy: `"trim"` (drop lowest-priority) or `"abort"` (skip all). */
  largePrPolicy?: "trim" | "abort";
  /** Newline-separated glob include list (empty ⇒ include everything). */
  fileInclude?: string;
  /** Newline-separated glob exclude list (empty ⇒ exclude nothing). */
  fileExclude?: string;
}

/**
 * Filter and prioritize files for review.
 *
 * Three ordered stages:
 *   0. **Glob include/exclude** — user globs (`fileInclude`/`fileExclude`); a
 *      file failing the include list or matching the exclude list is skipped
 *      with a `fileInclude`/`fileExclude` reason. Runs FIRST so excluded files
 *      never burn a review slot or an LLM call.
 *   1. **Diff-size** — files whose diff exceeds `maxDiffLines` are skipped.
 *   2. **File-budget** — when more than `maxFiles` candidates survive, either
 *      trim lowest-priority files (`largePrPolicy="trim"`) or skip all
 *      candidates (`largePrPolicy="abort"`).
 *
 * @param files   path → full file content (the set of changed files).
 * @param diffs   path → per-file diff text (from {@link splitDiffByFile}).
 * @param opts    optional per-call overrides; omitted ⇒ today's defaults.
 */
export function chunkFiles(
  files: Record<string, string>,
  diffs: Map<string, string>,
  opts: ChunkOptions = {},
): ChunkResult {
  const maxDiffLines = opts.maxDiffLines ?? ABSOLUTE_MAX_DIFF_LINES;
  const maxFiles = opts.maxFiles ?? MAX_FILES;
  const largePrPolicy = opts.largePrPolicy ?? "trim";
  const includePatterns = splitLines(opts.fileInclude ?? "");
  const excludePatterns = splitLines(opts.fileExclude ?? "");
  const skipped: SkippedFile[] = [];
  const candidates: string[] = [];

  // (0) Glob include/exclude filter — runs FIRST, before size/budget.
  // (1) Diff-size filter: skip files with no diff or whose diff exceeds the
  //     per-file line limit.
  for (const path of Object.keys(files)) {
    if (includePatterns.length > 0 && !matchAnyPath(path, includePatterns)) {
      skipped.push({ file: path, reason: "excluded by fileInclude (no pattern match)" });
      continue;
    }
    if (excludePatterns.length > 0 && matchAnyPath(path, excludePatterns)) {
      skipped.push({ file: path, reason: "excluded by fileExclude (pattern matched)" });
      continue;
    }
    const diffText = diffs.get(path);
    if (!diffText) {
      skipped.push({ file: path, reason: "no diff available (binary or unchanged)" });
      continue;
    }
    const lineCount = countDiffLines(diffText);
    if (lineCount > maxDiffLines) {
      skipped.push({
        file: path,
        reason: `diff too large (${lineCount} > ${maxDiffLines} lines)`,
      });
      continue;
    }
    candidates.push(path);
  }

  // (2) File-budget filter: if over the limit, keep highest-priority files.
  if (candidates.length <= maxFiles) {
    return { reviewable: candidates, skipped };
  }

  if (largePrPolicy === "abort") {
    for (const path of candidates) {
      skipped.push({ file: path, reason: `largePrPolicy=abort (PR exceeds ${maxFiles}-file budget)` });
    }
    return { reviewable: [], skipped };
  }

  candidates.sort((a, b) => {
    const pa = filePriority(a);
    const pb = filePriority(b);
    return pa !== pb ? pa - pb : a.localeCompare(b);
  });

  const reviewable = candidates.slice(0, maxFiles);
  for (const path of candidates.slice(maxFiles)) {
    skipped.push({ file: path, reason: `PR exceeds ${maxFiles}-file budget (lower priority)` });
  }
  return { reviewable, skipped };
}

/**
 * Priority rank for file trimming (lower = higher priority).
 *
 *   0 — source code
 *   1 — other code-like files (configs, scripts)
 *   2 — documentation
 *   3 — tests / fixtures / mocks
 */
function filePriority(path: string): number {
  if (TEST_PATTERNS.some((p) => p.test(path))) return 3;
  const dot = path.lastIndexOf(".");
  const ext = dot >= 0 ? path.slice(dot).toLowerCase() : "";
  if (DOC_EXTENSIONS.has(ext)) return 2;
  if (SOURCE_EXTENSIONS.has(ext)) return 0;
  return 1;
}

/** Count content lines in a per-file diff (excludes hunk headers + metadata). */
export function countDiffLines(diffText: string): number {
  let count = 0;
  for (const line of diffText.split("\n")) {
    if (line === "") continue;
    if (line.startsWith("\\")) continue; // "\ No newline at end of file"
    if (line.startsWith("@@")) continue; // hunk header
    count++;
  }
  return count;
}
