/**
 * Pure toast-queue reducer.
 *
 * Extracted from ToastProvider so the append + cap-at-5 (drop-oldest) and
 * dismiss logic is unit-testable in node without React, Date, or setTimeout.
 *
 * PURITY CONTRACT
 *   - No React, no `Date.now()`, no `Math.random()`, no `setTimeout`.
 *   - The caller injects the toast id (via `state.nextId`) and `createdAt`
 *     (`now`), so two identical calls produce identical results.
 *   - Input state is never mutated; both functions return a fresh state.
 */

import type { ToastItem, ToastVariant } from "../components/ui/Toast";

export interface ToastQueueState {
  toasts: ToastItem[];
  nextId: number;
}

export const initialToastQueueState: ToastQueueState = {
  toasts: [],
  nextId: 1,
};

/**
 * Append a toast, capping the queue at `max` by dropping the OLDEST entries
 * on overflow. Pure: the caller injects the `id` AND `now` (becomes `createdAt`),
 * so two identical calls produce identical results; the returned state advances
 * `nextId` to `id + 1`. The caller owns synchronous id generation (e.g. a ref
 * counter) so batched pushes never collide on a stale `state.nextId` read.
 */
export function pushToast(
  state: ToastQueueState,
  id: number,
  variant: ToastVariant,
  title: string,
  desc: string | undefined,
  max: number,
  now: number,
): ToastQueueState {
  const item: ToastItem = { id, variant, title, desc, createdAt: now };
  const toasts = [...state.toasts, item];
  // Cap at max, dropping the OLDEST on overflow.
  if (toasts.length > max) {
    toasts.splice(0, toasts.length - max);
  }
  return { toasts, nextId: id + 1 };
}

/** Remove a toast by id. Pure; no-op for unknown ids. */
export function dismissToast(state: ToastQueueState, id: number): ToastQueueState {
  return { ...state, toasts: state.toasts.filter((t) => t.id !== id) };
}
