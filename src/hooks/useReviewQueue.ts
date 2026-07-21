/**
 * useReviewQueue — accumulate the live review queue + published history.
 *
 * - `queue`: PRs that entered via `poll:found` but have not yet been published.
 * - `history`: completed reviews accumulated from `publish:review`.
 * - `inProgressPrId`: the PR currently being reviewed (tracked via
 *   `review:file`), or `null` when no review is in flight.
 * - `prLookup`: minimal PR metadata cache built from `poll:found`, used to
 *   enrich `history` entries with title / repo / number even though
 *   `publish:review` itself carries only numeric counts.
 * - `stats`: simple counts derived from history.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { onPollFound, onPollSkipped, onPublishReview, onReviewFile } from "../lib/tauri";
import type { PrSnapshot } from "@pr-review/shared";

/** Lightweight PR metadata cached for history enrichment. */
export interface PrLookupEntry {
  title: string;
  repo: string;
  number: number;
  author: string;
  url: string;
}

export interface QueueEntry {
  pr: PrSnapshot;
  addedAt: number;
}

export interface HistoryEntry {
  prId: number;
  posted: number;
  degraded: number;
  retried: number;
  completedAt: number;
  /** Populated from `prLookup` when the PR was seen via `poll:found`. */
  title?: string;
  repo?: string;
  number?: number;
}

export interface ReviewStats {
  totalReviews: number;
  totalComments: number;
  totalDegraded: number;
  totalRetried: number;
}

export interface ReviewQueue {
  queue: QueueEntry[];
  history: HistoryEntry[];
  inProgressPrId: number | null;
  prLookup: Map<number, PrLookupEntry>;
  stats: ReviewStats;
  clearHistory: () => void;
}

const MAX_HISTORY = 500;

export function useReviewQueue(): ReviewQueue {
  const [queue, setQueue] = useState<QueueEntry[]>([]);
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [inProgressPrId, setInProgressPrId] = useState<number | null>(null);
  const [prLookup, setPrLookup] = useState<Map<number, PrLookupEntry>>(
    new Map(),
  );
  // Ref mirror of `prLookup` so event handlers can read the latest cache
  // synchronously without depending on stale closure state.
  const prLookupRef = useRef<Map<number, PrLookupEntry>>(new Map());

  useEffect(() => {
    const unlisteners: Array<() => void> = [];
    let cancelled = false;

    onPollFound((pr) => {
      setQueue((prev) => {
        if (prev.some((e) => e.pr.id === pr.id)) return prev;
        return [...prev, { pr, addedAt: Date.now() }];
      });
      setPrLookup((prev) => {
        const next = new Map(prev);
        next.set(pr.id, {
          title: pr.title,
          repo: pr.repo,
          number: pr.number,
          author: pr.author,
          url: pr.url,
        });
        prLookupRef.current = next;
        return next;
      });
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    onPollSkipped((prId) => {
      setQueue((prev) => prev.filter((e) => e.pr.id !== prId));
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    onReviewFile((prId) => {
      setInProgressPrId(prId);
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    onPublishReview((review) => {
      const cached = prLookupRef.current.get(review.prId);
      setHistory((prev) =>
        [
          {
            prId: review.prId,
            posted: review.posted,
            degraded: review.degraded,
            retried: review.retried,
            completedAt: review.ts ?? Date.now(),
            title: cached?.title,
            repo: cached?.repo,
            number: cached?.number,
          },
          ...prev,
        ].slice(0, MAX_HISTORY),
      );
      // Remove the published PR from the active queue.
      setQueue((prev) => prev.filter((e) => e.pr.id !== review.prId));
      // Clear the in-progress marker once the review has been published.
      setInProgressPrId((cur) => (cur === review.prId ? null : cur));
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    return () => {
      cancelled = true;
      unlisteners.forEach((fn) => fn());
    };
  }, []);

  const clearHistory = useCallback(() => setHistory([]), []);

  const stats: ReviewStats = {
    totalReviews: history.length,
    totalComments: history.reduce((sum, h) => sum + h.posted, 0),
    totalDegraded: history.reduce((sum, h) => sum + h.degraded, 0),
    totalRetried: history.reduce((sum, h) => sum + h.retried, 0),
  };

  return { queue, history, inProgressPrId, prLookup, stats, clearHistory };
}
