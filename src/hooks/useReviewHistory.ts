/**
 * useReviewHistory — subscribe to the persisted review-history snapshot and
 * expose filterable, debounced reloading on top of the G002 tauri.ts surface.
 *
 * - `reviews`: the latest `review_history` rows pushed by `history:snapshot`.
 * - `filters`: the active filter object (repo / since / until / severity /
 *   author / limit). Mutated via `setFilters`, which debounces the reload by
 *   300ms so rapid typing in a filter field does not flood the daemon.
 * - `refresh`: force an immediate reload with the current filters.
 * - `loading`: true while a load is outstanding; cleared when a snapshot lands.
 *
 * Pattern mirrors useReviewQueue.ts: useEffect with collected unlisteners,
 * useRef mirrors so event callbacks and the debounced reload read the latest
 * values without stale closures, and a cleanup that tears down listeners and
 * cancels the pending debounce timer.
 */
import { useState, useEffect, useRef, useCallback } from "react";
import { getHistory, onHistorySnapshot } from "../lib/tauri";
import type { ReviewHistoryEntry } from "@pr-review/shared";

/** Filterable fields of the history view. All optional. */
export interface HistoryFilters {
  repo?: string;
  since?: string;
  until?: string;
  severity?: string;
  author?: string;
  limit?: number;
}

export interface UseReviewHistory {
  reviews: ReviewHistoryEntry[];
  filters: HistoryFilters;
  setFilters: (f: Partial<HistoryFilters>) => void;
  refresh: () => void;
  loading: boolean;
}

/** Debounce window (ms) for filter-driven reloads. */
const FILTER_DEBOUNCE_MS = 300;

export function useReviewHistory(): UseReviewHistory {
  const [reviews, setReviews] = useState<ReviewHistoryEntry[]>([]);
  const [filters, setFiltersState] = useState<HistoryFilters>({});
  const [loading, setLoading] = useState(true);

  // Ref mirror of `filters` so the debounced reload and `refresh` always read
  // the latest merged value instead of a stale closure.
  const filtersRef = useRef<HistoryFilters>({});
  // Debounce timer handle for filter-driven reloads; cleared on cleanup.
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const unlisteners: Array<() => void> = [];
    let cancelled = false;

    onHistorySnapshot((next) => {
      setReviews(next);
      setLoading(false);
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    // Request the initial load.
    void getHistory(filtersRef.current);

    return () => {
      cancelled = true;
      unlisteners.forEach((fn) => fn());
      if (debounceRef.current) {
        clearTimeout(debounceRef.current);
        debounceRef.current = null;
      }
    };
  }, []);

  const setFilters = useCallback((f: Partial<HistoryFilters>) => {
    const merged: HistoryFilters = { ...filtersRef.current, ...f };
    filtersRef.current = merged;
    setFiltersState(merged);
    // Reset any pending debounce so only the latest filter set reloads.
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      debounceRef.current = null;
      setLoading(true);
      void getHistory(merged);
    }, FILTER_DEBOUNCE_MS);
  }, []);

  const refresh = useCallback(() => {
    // A manual refresh supersedes any pending debounce.
    if (debounceRef.current) {
      clearTimeout(debounceRef.current);
      debounceRef.current = null;
    }
    setLoading(true);
    void getHistory(filtersRef.current);
  }, []);

  return { reviews, filters, setFilters, refresh, loading };
}
