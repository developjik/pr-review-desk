/**
 * Retry — review-unit retry for the publisher (P5).
 *
 * Handles transient failures of the review POST (`POST /repos/:o/:r/pulls/:n/
 * reviews`): HTTP 5xx responses and network errors are retried with exponential
 * backoff (1s, 2s, 4s; up to 3 retries). 422 "Validation Failed" responses are
 * NOT retried here — those are handled by progressive trim in the publisher.
 */
import { sleep } from "../poller/util";
import { isTransientError, extractRetryAfter } from "../util/retry";

/** Default backoff schedule (ms): 1s, 2s, 4s. */
const DEFAULT_BACKOFF_MS = [1000, 2000, 4000];

/** Default retry budget: the initial attempt plus 3 retries. */
const DEFAULT_MAX_RETRIES = 3;

/** Outcome of {@link withReviewRetry}. */
export interface RetryOutcome<T> {
  value: T;
  /** Total attempts made, including the successful one (1 = first try). */
  attempts: number;
}

/**
 * Is the thrown error a retryable 5xx or network failure?
 *
 * @octokit/rest throws `RequestError` with a numeric `status` for HTTP failures
 * and a Node `code` (ECONNRESET, ETIMEDOUT, …) for transport-level drops.
 */
export function isRetryableError(err: unknown): boolean {
  return isTransientError(err);
}

/**
 * Run `fn`, retrying on {@link isRetryableError} with exponential backoff.
 *
 * Non-retryable errors propagate immediately (including 422 — the publisher's
 * progressive-trim loop handles those). `fn` receives the 1-based attempt number
 * so it can adapt logging or payload on later attempts.
 *
 * @param fn          Thunk that performs the POST (may be retried).
 * @param maxRetries  Maximum retry attempts after the initial try (default 3).
 * @param backoffMs   Delays between retries (default [1000, 2000, 4000]).
 */
export async function withReviewRetry<T>(
  fn: (attempt: number) => Promise<T>,
  maxRetries: number = DEFAULT_MAX_RETRIES,
  backoffMs: number[] = DEFAULT_BACKOFF_MS,
): Promise<RetryOutcome<T>> {
  let attempt = 0;
  for (;;) {
    try {
      const value = await fn(attempt + 1);
      return { value, attempts: attempt + 1 };
    } catch (err) {
      if (!isRetryableError(err) || attempt >= maxRetries) throw err;
      const retryAfter = extractRetryAfter(err);
      const delay = retryAfter !== null ? retryAfter * 1000 : (backoffMs[attempt] ?? backoffMs[backoffMs.length - 1]);
      await sleep(delay);
      attempt += 1;
    }
  }
}
