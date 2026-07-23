/**
 * useStats — subscribe to the aggregated review-stats snapshot for a time
 * window and expose a manual `refresh` over the G002 tauri.ts surface.
 *
 * - `summary`: rolled-up totals for the window, or null until the first
 *   `stats:snapshot` lands.
 * - `daily`: per-day activity rows (chart data).
 * - `refresh(since, days)`: re-request stats for an arbitrary window.
 *
 * On mount the hook requests stats for the current month (month-start ISO
 * through 30 days). Pattern mirrors useReviewQueue.ts: useEffect with a
 * collected unlistener and a cancelled-flag guard for late promise resolution.
 */
import { useState, useEffect, useCallback } from "react";
import { getStats, onStatsSnapshot } from "../lib/tauri";
import type { StatsSummary, DailyStat } from "@pr-review/shared";

export interface UseStats {
  summary: StatsSummary | null;
  daily: DailyStat[];
  refresh: (since: string, days: number) => void;
}

/** Default stats window length (days) requested on mount. */
const DEFAULT_DAYS = 30;

/**
 * Current UTC month start as an ISO string, e.g. "2025-07-01T00:00:00.000Z".
 * Mirrors the daemon orchestrator's `monthStartIso` helper.
 */
function monthStartIso(): string {
  const now = new Date();
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  ).toISOString();
}

export function useStats(): UseStats {
  const [summary, setSummary] = useState<StatsSummary | null>(null);
  const [daily, setDaily] = useState<DailyStat[]>([]);

  useEffect(() => {
    const unlisteners: Array<() => void> = [];
    let cancelled = false;

    onStatsSnapshot((s, d) => {
      setSummary(s);
      setDaily(d);
    }).then((fn) => {
      if (cancelled) fn();
      else unlisteners.push(fn);
    });

    // Request the initial window: current month start, DEFAULT_DAYS span.
    void getStats(monthStartIso(), DEFAULT_DAYS);

    return () => {
      cancelled = true;
      unlisteners.forEach((fn) => fn());
    };
  }, []);

  const refresh = useCallback((since: string, days: number) => {
    void getStats(since, days);
  }, []);

  return { summary, daily, refresh };
}
