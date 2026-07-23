// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

vi.mock("../lib/tauri", () => ({
  getStats: vi.fn(),
  onStatsSnapshot: vi.fn(() => Promise.resolve(() => {})),
}));

// Imports below resolve against the mocked "../lib/tauri" module (vi.mock is
// hoisted above all imports by vitest).
import { useStats } from "./useStats";
import { getStats, onStatsSnapshot } from "../lib/tauri";
import type { StatsSummary, DailyStat } from "@pr-review/shared";

// Captured listener callback (registered synchronously inside the hook's
// useEffect, which renderHook flushes before returning).
let snapshotCb:
  | ((summary: StatsSummary, daily: DailyStat[]) => void)
  | null = null;

function makeSummary(over: Partial<StatsSummary> = {}): StatsSummary {
  return {
    totalReviews: 10,
    totalFindings: 25,
    totalPosted: 20,
    totalDegraded: 2,
    totalCostUsd: 0.42,
    totalPromptTokens: 1000,
    totalCompletionTokens: 500,
    totalTokens: 1500,
    ...over,
  };
}

function makeDaily(): DailyStat[] {
  return [
    { date: "2025-07-01", reviews: 1, findings: 2, costUsd: 0.05 },
    { date: "2025-07-02", reviews: 3, findings: 5, costUsd: 0.1 },
  ];
}

beforeEach(() => {
  vi.clearAllMocks();

  vi.mocked(getStats).mockResolvedValue(undefined);

  snapshotCb = null;
  vi.mocked(onStatsSnapshot).mockImplementation((cb) => {
    snapshotCb = cb;
    return Promise.resolve(() => {});
  });
});

describe("useStats", () => {
  it("calls getStats on mount with month-start ISO and 30 days", () => {
    renderHook(() => useStats());

    expect(getStats).toHaveBeenCalledTimes(1);
    const [since, days] = vi.mocked(getStats).mock.calls[0] as [
      string,
      number,
    ];
    expect(days).toBe(30);
    // Month start = first of the current UTC month at UTC midnight.
    expect(since).toMatch(/^\d{4}-\d{2}-01T00:00:00\.000Z$/);
    const parsed = new Date(since);
    const now = new Date();
    expect(parsed.getUTCFullYear()).toBe(now.getUTCFullYear());
    expect(parsed.getUTCMonth()).toBe(now.getUTCMonth());
  });

  it("onStatsSnapshot updates summary and daily", () => {
    const { result } = renderHook(() => useStats());

    expect(result.current.summary).toBeNull();
    expect(result.current.daily).toHaveLength(0);

    const summary = makeSummary({ totalReviews: 42 });
    const daily = makeDaily();
    act(() => {
      snapshotCb?.(summary, daily);
    });

    expect(result.current.summary).toEqual(summary);
    expect(result.current.summary?.totalReviews).toBe(42);
    expect(result.current.daily).toEqual(daily);
  });

  it("refresh calls getStats with the new params", () => {
    const { result } = renderHook(() => useStats());
    vi.mocked(getStats).mockClear();

    act(() => {
      result.current.refresh("2025-06-01T00:00:00.000Z", 7);
    });

    expect(getStats).toHaveBeenCalledTimes(1);
    expect(getStats).toHaveBeenCalledWith("2025-06-01T00:00:00.000Z", 7);
  });

  it("unsubscribes on unmount", async () => {
    const unlisten = vi.fn();
    vi.mocked(onStatsSnapshot).mockImplementation((cb) => {
      snapshotCb = cb;
      return Promise.resolve(unlisten);
    });

    const { unmount } = renderHook(() => useStats());
    // Let onStatsSnapshot's promise resolve so the unlisten fn is registered
    // before we unmount.
    await act(async () => {});

    unmount();

    expect(unlisten).toHaveBeenCalled();
  });
});
