/**
 * Unified transient-error classifier shared by all retry paths.
 *
 * The LLM client (`reviewer/llm-client.ts`) and the publisher
 * (`publisher/retry.ts`) both retry on transient failures. Centralizing the
 * definition here keeps the two retry loops in sync.
 */

/** Node errno codes that indicate a transient transport-level failure. */
const ERRNO_CODES = [
  "ECONNRESET",
  "ETIMEDOUT",
  "ENOTFOUND",
  "ECONNREFUSED",
  "EPIPE",
  "EAI_AGAIN",
  "EHOSTUNREACH",
];

/** Should this error trigger a retry? (429, 5xx, timeouts, connection errors) */
export function isTransientError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const e = err as { status?: unknown; name?: string; message?: string; code?: unknown };

  // HTTP status-based retry (429, 5xx).
  if (typeof e.status === "number") {
    if (e.status === 429 || e.status >= 500) return true;
  }

  // Named error types from the openai SDK.
  const name = e.name ?? "";
  if (name === "APIConnectionError" || name === "APIConnectionTimeoutError") return true;

  // Node errno codes.
  const code = typeof e.code === "string" ? e.code : "";
  if (ERRNO_CODES.includes(code)) return true;

  // Fallback: message substring.
  const msg = (e.message ?? "").toLowerCase();
  return (
    msg.includes("timeout") ||
    msg.includes("timed out") ||
    msg.includes("econnreset") ||
    msg.includes("socket hang up") ||
    msg.includes("fetch failed")
  );
}

/** Extract Retry-After seconds from an error response, or null if absent. */
export function extractRetryAfter(err: unknown): number | null {
  if (!err || typeof err !== "object") return null;
  const headers = (err as { response?: { headers?: Record<string, unknown> } }).response?.headers ?? {};
  const raw = headers["retry-after"] ?? headers["Retry-After"];
  if (typeof raw === "string") {
    const n = parseInt(raw, 10);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return null;
}
