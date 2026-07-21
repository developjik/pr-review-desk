/**
 * Lightweight, dependency-free token-budget estimation.
 *
 * Used only to bound the size of injected review guidelines (F1). Keeps the
 * `@yao-pkg/pkg` CJS sidecar bundle free of tokenizer/WASM/native dependencies
 * (plan ADR D1: bundling safety). Coarse and deterministic; never used for
 * billing or exact context-window accounting — only for truncation guards.
 */

/** Approximate characters per token for a coarse budget estimate. */
export const CHARS_PER_TOKEN = 4;

/**
 * Estimate the number of tokens in `text` as ceil(length / CHARS_PER_TOKEN).
 *
 * An empty string yields 0 tokens; longer strings scale proportionally.
 */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / CHARS_PER_TOKEN);
}
