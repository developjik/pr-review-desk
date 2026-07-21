/**
 * Poller-local helpers.
 */

/**
 * Stable 32-bit surrogate id for a PR.
 *
 * The schema keys tables on `pr_id` (INTEGER) but GitHub exposes no global
 * integer id for a PR — only the per-repo `number`. We derive a stable, safely
 * positive id from `repo#number` with FNV-1a so the same PR maps to the same
 * `pr_id` across polls (required by dedupe + queue).
 *
 * Collision probability is negligible for the realistic working set (a few
 * dozen review-requested PRs); SQLite INTEGER is 64-bit regardless.
 */
export function prId(repo: string, number: number): number {
  const key = `${repo}#${number}`;
  // FNV-1a 32-bit offset basis / prime.
  let h = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Resolve after `ms` milliseconds. */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
