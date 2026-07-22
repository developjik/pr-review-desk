/**
 * Zod schema for daemon configuration.
 *
 * Authority for validation lives in the daemon: the host sends a raw
 * {@link ConfigPayload}; the daemon parses/validates/defaults it into a frozen
 * {@link Config} snapshot. Both sides should stay field-compatible with
 */
import { z } from "zod";

const httpUrl = z
  .string()
  .min(1)
  .refine((v) => /^https?:\/\/[^\s]+$/i.test(v), {
    message: "must be an http(s) URL",
  });

export const configSchema = z.object({
  githubUsername: z.string().default(""),
  githubPat: z.string().min(1),
  llmBaseUrl: httpUrl,
  llmApiKey: z.string().min(1),
  llmJsonMode: z.boolean().default(true),
  llmModel: z.string().min(1),
  pollIntervalMin: z.number().int().positive().default(15),
  showSeverity: z.boolean().default(true),
  osNotify: z.boolean().default(false),
  reviewMode: z.enum(["auto", "pending"]).default("auto"),
  reviewRules: z.string().default(""),
  repoInclude: z.string().default(""),
  repoExclude: z.string().default(""),
  triggerLabels: z.string().default(""),
  skipLabels: z.string().default(""),
  // --- Review-quality feature cluster (defaults = prior hardcoded behavior) ---
  // Newline-separated glob include/exclude (mirrors repoInclude/repoExclude).
  fileInclude: z.string().default(""),
  fileExclude: z.string().default(""),
  // Per-file diff-line skip ceiling (was ABSOLUTE_MAX_DIFF_LINES).
  maxDiffLines: z.number().int().positive().default(5000),
  // Reviewable-files budget before trim/abort (was MAX_FILES).
  maxFiles: z.number().int().positive().default(50),
  // Over-budget policy: "trim" (drop lowest-priority) or "abort" (skip all).
  largePrPolicy: z.enum(["trim", "abort"]).default("trim"),
  // --- Cost & budget feature cluster (G001) ---
  // Newline-separated "model:promptPer1M,completionPer1M" pricing lines.
  llmPricing: z.string().default(""),
  // Blended fallback $/1M tokens (0 = free/unknown).
  defaultPer1M: z.number().nonnegative().default(0),
  // Monthly LLM spend ceiling; 0 = unlimited. Exceeding pauses reviews.
  monthlyBudgetUsd: z.number().nonnegative().default(0),
  dbPath: z.string().min(1),
  logDir: z.string().min(1),
});

/** Fully-resolved, validated config snapshot (defaults applied). */
export type Config = z.infer<typeof configSchema>;

/** Validate + apply defaults. Throws `ZodError` on invalid input. */
export function parseConfig(input: unknown): Config {
  return configSchema.parse(input);
}
/**
 * Best-effort "did anything change?" check used to decide whether a hot-reload
 * should re-run orchestrator scheduling. Cheap structural equality over the
 * fields that affect runtime behavior.
 */
export function configAffectsRuntime(a: Config, b: Config): boolean {
  return (
    a.pollIntervalMin !== b.pollIntervalMin ||
    a.githubUsername !== b.githubUsername ||
    a.githubPat !== b.githubPat ||
    a.llmBaseUrl !== b.llmBaseUrl ||
    a.llmApiKey !== b.llmApiKey ||
    a.llmModel !== b.llmModel ||
    a.monthlyBudgetUsd !== b.monthlyBudgetUsd
  );
}
