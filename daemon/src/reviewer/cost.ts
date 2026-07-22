/**
 * LLM cost math — pure pricing + cost computation (G001).
 *
 * Given a newline-separated pricing string (the `llmPricing` config field) and a
 * blended `defaultPer1M` fallback, produces a typed {@link Pricing} table that
 * {@link computeCost} uses to bill a {@link TokenUsage} against a model. Never
 * throws — malformed pricing lines are silently skipped, and NaN/non-finite
 * inputs coerce to 0 (mirrors the `toFiniteNumber` coercion in llm-client.ts).
 */
import type { TokenUsage } from "../types/domain";

/** Per-model $/1M-token rate for prompt and completion tokens. */
export interface ModelRate {
  promptPer1M: number;
  completionPer1M: number;
}

/** Resolved pricing table: per-model rates + a blended fallback. */
export interface Pricing {
  defaultPer1M: number;
  rates: Map<string, ModelRate>;
}

/**
 * Parse newline-separated `model:promptPer1M,completionPer1M` lines into a
 * {@link Pricing} table. Blank and malformed lines are silently skipped (never
 * throws). An empty string yields a Pricing with an empty Map (everything falls
 * back to `defaultPer1M`).
 *
 * Example input:
 *   "gpt-4o:2.50,10.00\nglm-5.2:0.50,1.50"
 */
export function parsePricing(llmPricing: string, defaultPer1M: number): Pricing {
  const rates = new Map<string, ModelRate>();
  if (!llmPricing) return { defaultPer1M, rates };

  for (const rawLine of llmPricing.split("\n")) {
    const line = rawLine.trim();
    if (!line) continue; // skip blank lines

    // Expected shape: "model:promptPer1M,completionPer1M"
    const colonIdx = line.indexOf(":");
    if (colonIdx < 0) continue; // malformed — no colon
    const model = line.slice(0, colonIdx).trim();
    if (!model) continue; // empty model name

    const rest = line.slice(colonIdx + 1);
    const parts = rest.split(",");
    if (parts.length < 2) continue; // malformed — need two comma-separated values

    const promptPer1M = Number(parts[0].trim());
    const completionPer1M = Number(parts[1].trim());
    if (!Number.isFinite(promptPer1M) || !Number.isFinite(completionPer1M)) continue; // malformed — non-numeric
    if (promptPer1M < 0 || completionPer1M < 0) continue; // malformed — negative

    rates.set(model, { promptPer1M, completionPer1M });
  }

  return { defaultPer1M, rates };
}

/**
 * Compute the dollar cost of a token-usage row billed against `model`.
 *
 * Rate lookup: `pricing.rates.get(model)` when available, otherwise a blended
 * fallback using `pricing.defaultPer1M` for BOTH prompt and completion. Cost =
 * (promptTokens/1e6)*rate.promptPer1M + (completionTokens/1e6)*rate.completionPer1M.
 *
 * NaN/Infinity guard: any non-finite input is treated as 0, so the result is
 * always a finite number ≥ 0 (mirrors `toFiniteNumber` in llm-client.ts).
 */
export function computeCost(usage: TokenUsage, model: string, pricing: Pricing): number {
  const rate = pricing.rates.get(model) ?? {
    promptPer1M: pricing.defaultPer1M,
    completionPer1M: pricing.defaultPer1M,
  };

  const promptTokens = Number.isFinite(usage.promptTokens) ? usage.promptTokens : 0;
  const completionTokens = Number.isFinite(usage.completionTokens) ? usage.completionTokens : 0;
  const promptRate = Number.isFinite(rate.promptPer1M) ? rate.promptPer1M : 0;
  const completionRate = Number.isFinite(rate.completionPer1M) ? rate.completionPer1M : 0;

  const cost = (promptTokens / 1e6) * promptRate + (completionTokens / 1e6) * completionRate;
  return Number.isFinite(cost) && cost > 0 ? cost : 0;
}
