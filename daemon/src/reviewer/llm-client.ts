/**
 * LLM client — OpenAI-compatible chat completions for code review.
 *
 * Uses the `openai` SDK pointed at `config.llmBaseUrl` with BYOK
 * (`config.llmApiKey`). JSON mode (`response_format: { type: "json_object" }`)
 * ensures the model returns parseable JSON.
 *
 * Reliability:
 *   - Exponential backoff retry on HTTP 429, 5xx, timeouts, and connection
 *     errors (up to {@link MAX_RETRIES} = 3 attempts).
 *   - Malformed JSON responses are best-effort normalized rather than thrown.
 */
import OpenAI from "openai";
import type { Config } from "../config/schema";
import type { Area, Finding, Severity } from "../types/domain";
import { buildSystemPrompt, buildUserPrompt, type PrPromptMeta } from "./prompts";
import { isTransientError } from "../util/retry";

const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** Per-file review output from the LLM. */
export interface LlmFileReview {
  findings: Finding[];
  summary: string;
}

export interface LlmClient {
  /**
   * Review a single file. Returns the parsed findings and summary. Throws only
   * after exhausting retries on retryable errors.
   */
  reviewFile(
    fileName: string,
    fileContent: string,
    diffHunks: string,
    prMeta: PrPromptMeta,
    language: string,
    rules?: string,
  ): Promise<LlmFileReview>;
}

/** Build an LLM client from the daemon config. */
export function createLlmClient(config: Config): LlmClient {
  const client = new OpenAI({
    baseURL: config.llmBaseUrl,
    apiKey: config.llmApiKey,
  });

  return {
    async reviewFile(fileName, fileContent, diffHunks, prMeta, language, rules) {
      const system = buildSystemPrompt(config.showSeverity, language, rules ?? "");
      const user = buildUserPrompt(fileName, fileContent, diffHunks, prMeta);

      let lastError: unknown;
      for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
          const resp = await client.chat.completions.create({
            model: config.llmModel,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user },
            ],
            ...(config.llmJsonMode ? { response_format: { type: "json_object" as const } } : {}),
          });
          const content = resp.choices[0]?.message?.content ?? "{}";
          return parseReviewResponse(content, fileName);
        } catch (err) {
          lastError = err;
          if (!isTransientError(err) || attempt === MAX_RETRIES - 1) break;
          await sleep(INITIAL_BACKOFF_MS * 2 ** attempt);
        }
      }

      throw lastError instanceof Error
        ? lastError
        : new Error(`LLM review failed for ${fileName}`);
    },
  };
}

// --------------------------------------------------------------------------- internals

/**
 * Parse and normalize the LLM's JSON response into typed findings.
 *
 * Tolerant of missing/malformed fields: a finding without a comment is dropped,
 * unknown severities/areas fall back to safe defaults, and a non-JSON body
 * yields an empty result rather than throwing.
 */
function parseReviewResponse(content: string, defaultFile: string): LlmFileReview {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    // Try extracting first balanced { ... } block (defense-in-depth for both modes).
    const braceMatch = content.match(/\{[\s\S]*\}/);
    if (braceMatch) {
      try {
        parsed = JSON.parse(braceMatch[0]);
      } catch {
        return { findings: [], summary: "Failed to parse LLM response as JSON." };
      }
    } else {
      return { findings: [], summary: "Failed to parse LLM response as JSON." };
    }
  }

  const obj = parsed as Record<string, unknown>;
  const rawFindings = Array.isArray(obj.findings) ? obj.findings : [];
  const summary = typeof obj.summary === "string" ? obj.summary : "";

  const findings: Finding[] = [];
  for (const raw of rawFindings) {
    const f = normalizeFinding(raw, defaultFile);
    if (f) findings.push(f);
  }

  return { findings, summary };
}

/** Coerce a raw finding object into a typed {@link Finding}, or null if unusable. */
function normalizeFinding(raw: unknown, defaultFile: string): Finding | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;

  const comment = typeof r.comment === "string" ? r.comment.trim() : "";
  if (!comment) return null; // a finding without a comment is useless

  const file = typeof r.file === "string" && r.file ? r.file : defaultFile;
  const line = typeof r.line === "number" && Number.isFinite(r.line) ? r.line : null;
  const severity = normalizeSeverity(r.severity);
  const area = normalizeArea(r.area);
  const suggestion = typeof r.suggestion === "string" ? r.suggestion : undefined;

  return { file, line, severity, area, comment, suggestion };
}

function normalizeSeverity(raw: unknown): Severity {
  const s = String(raw ?? "")
    .toLowerCase()
    .trim();
  if (s === "critical" || s === "high") return "high";
  if (s === "medium") return "medium";
  if (s === "info") return "info";
  return "low";
}

function normalizeArea(raw: unknown): Area {
  const a = String(raw ?? "")
    .toLowerCase()
    .trim();
  if (a === "bug" || a === "style" || a === "structure" || a === "security") return a;
  return "style";
}

/** Should this error trigger a retry? (429, 5xx, timeouts, connection errors) */
export function isRetryable(err: unknown): boolean {
  return isTransientError(err);
}
