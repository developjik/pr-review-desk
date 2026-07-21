/**
 * usePendingReviews — manage pending review state.
 * Hydrates from daemon on mount + ready; live-updates from events.
 *
 * approve / reject are async and await the IPC: the card is removed ONLY on
 * success. Each submit tracks a per-review `submitting` flag so the UI can show
 * a spinner and disable the button. `pending://resolved` (daemon-driven) and
 * the success-path filter are both idempotent — a resolve that races the await
 * is a harmless no-op.
 */
import { useCallback, useEffect, useState } from "react";
import {
  approveReview,
  rejectReview,
  listPendingReviews,
  onReviewPending,
  onPendingSnapshot,
  onPendingResolved,
  onDaemonReady,
} from "../lib/tauri";
import type { FindingEdit, PendingReview } from "@pr-review/shared";

/** Per-review submit state: which action is in-flight, if any. */
export type SubmittingMap = Record<number, "approve" | "reject" | null>;

/** Result of an approve/reject submit. The card is removed only on `ok`. */
export interface SubmitResult {
  ok: boolean;
  error?: string;
}

/** Normalize an unknown rejection into a human-readable string for toasts. */
function toErrorMessage(e: unknown): string {
  if (typeof e === "string") return e;
  if (e instanceof Error) return e.message;
  if (
    e !== null &&
    typeof e === "object" &&
    "message" in e &&
    typeof (e as { message: unknown }).message === "string"
  ) {
    return (e as { message: string }).message;
  }
  return String(e);
}

export function usePendingReviews() {
  const [pending, setPending] = useState<PendingReview[]>([]);
  const [submitting, setSubmitting] = useState<SubmittingMap>({});

  useEffect(() => {
    const unlisteners: Array<() => void> = [];
    let cancelled = false;

    // Request initial snapshot
    listPendingReviews();

    onPendingSnapshot((reviews) => {
      setPending(reviews);
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    onReviewPending((review) => {
      setPending((prev) => {
        if (prev.some((r) => r.reviewId === review.reviewId)) return prev;
        return [review, ...prev];
      });
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    onPendingResolved((reviewId) => {
      setPending((prev) => prev.filter((r) => r.reviewId !== reviewId));
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    // Re-hydrate on daemon ready (restart). Also clears any stale submitting
    // flags so a restart mid-submit doesn't leave a card permanently loading.
    onDaemonReady(() => {
      listPendingReviews();
      setSubmitting({});
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    return () => {
      cancelled = true;
      unlisteners.forEach((fn) => fn());
    };
  }, []);

  const approve = useCallback(
    async (
      reviewId: number,
      findingIds?: string[],
      edits?: Record<string, FindingEdit>,
    ): Promise<SubmitResult> => {
      setSubmitting((prev) => ({ ...prev, [reviewId]: "approve" }));
      try {
        await approveReview(reviewId, findingIds, edits);
        setPending((prev) => prev.filter((r) => r.reviewId !== reviewId));
        return { ok: true };
      } catch (e) {
        return { ok: false, error: toErrorMessage(e) };
      } finally {
        setSubmitting((prev) => {
          const next = { ...prev };
          delete next[reviewId];
          return next;
        });
      }
    },
    [],
  );

  const reject = useCallback(
    async (reviewId: number): Promise<SubmitResult> => {
      setSubmitting((prev) => ({ ...prev, [reviewId]: "reject" }));
      try {
        await rejectReview(reviewId);
        setPending((prev) => prev.filter((r) => r.reviewId !== reviewId));
        return { ok: true };
      } catch (e) {
        return { ok: false, error: toErrorMessage(e) };
      } finally {
        setSubmitting((prev) => {
          const next = { ...prev };
          delete next[reviewId];
          return next;
        });
      }
    },
    [],
  );

  return { pending, approve, reject, submitting };
}
