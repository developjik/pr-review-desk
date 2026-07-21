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
    a.llmModel !== b.llmModel
  );
}
