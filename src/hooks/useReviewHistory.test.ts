// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

vi.mock("../lib/tauri", () => ({
  getHistory: vi.fn(),
  onHistorySnapshot: vi.fn(() => Promise.resolve(() => {})),
}));

// Imports below resolve against the mocked "../lib/tauri" module (vi.mock is
// hoisted above all imports by vitest).
import { useReviewHistory } from "./useReviewHistory";
import { getHistory, onHistorySnapshot } from "../lib/tauri";
import type { ReviewHistoryEntry } from "@pr-review/shared";

// Captured listener callback (registered synchronously inside the hook's
// useEffect, which renderHook flushes before returning).
let snapshotCb: ((reviews: ReviewHistoryEntry[]) => void) | null = null;

function makeReview(id: number): ReviewHistoryEntry {
  return {
    id,
    prId: id,
    prNumber: id,
    repo: "owner/repo",
    headSha: `sha${id}`,
    title: `PR ${id}`,
    author: "alice",
    reviewMode: "comment",
    findingsTotal: id,
    sevHigh: 0,
    sevMedium: 1,
    sevLow: 2,
    posted: id,
    degraded: 0,
    promptTokens: 100,
    completionTokens: 50,
    totalTokens: 150,
    costUsd: 0.01,
    status: "completed",
    reviewedAt: "2025-07-22T00:00:00Z",
    createdAt: "2025-07-22T00:00:00Z",
  };
}

beforeEach(() => {
  vi.clearAllMocks();

  vi.mocked(getHistory).mockResolvedValue(undefined);

  snapshotCb = null;
  vi.mocked(onHistorySnapshot).mockImplementation((cb) => {
    snapshotCb = cb;
    return Promise.resolve(() => {});
  });
});

describe("useReviewHistory", () => {
  it("calls getHistory() on mount with empty filters", () => {
    renderHook(() => useReviewHistory());

    expect(getHistory).toHaveBeenCalledTimes(1);
    expect(getHistory).toHaveBeenCalledWith({});
  });

  it("onHistorySnapshot updates reviews and clears loading", () => {
    const { result } = renderHook(() => useReviewHistory());

    expect(result.current.loading).toBe(true);
    expect(result.current.reviews).toHaveLength(0);

    act(() => {
      snapshotCb?.([makeReview(1), makeReview(2)]);
    });

    expect(result.current.reviews).toHaveLength(2);
    expect(result.current.reviews[0]?.id).toBe(1);
    expect(result.current.loading).toBe(false);
  });

  it("setFilters merges partial and debounces the getHistory call", () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useReviewHistory());
    // Discard the mount-time getHistory call for a clean slate.
    vi.mocked(getHistory).mockClear();

    act(() => {
      result.current.setFilters({ repo: "owner/repo" });
    });

    // State updates immediately, but the IPC call is deferred.
    expect(result.current.filters).toEqual({ repo: "owner/repo" });
    expect(getHistory).not.toHaveBeenCalled();

    act(() => {
      vi.advanceTimersByTime(300);
    });

    expect(getHistory).toHaveBeenCalledTimes(1);
    expect(getHistory).toHaveBeenCalledWith({ repo: "owner/repo" });

    // A second partial merges onto the existing filters.
    act(() => {
      result.current.setFilters({ severity: "high" });
    });
    expect(getHistory).toHaveBeenCalledTimes(1); // still debounced

    act(() => {
      vi.advanceTimersByTime(300);
    });
    expect(getHistory).toHaveBeenCalledWith({
      repo: "owner/repo",
      severity: "high",
    });

    vi.useRealTimers();
  });

  it("refresh calls getHistory immediately and cancels a pending debounce", () => {
    vi.useFakeTimers();
    const { result } = renderHook(() => useReviewHistory());

    // Stage a filter change with a pending debounce, then refresh.
    act(() => {
      result.current.setFilters({ repo: "owner/repo" });
    });
    vi.mocked(getHistory).mockClear();

    act(() => {
      result.current.refresh();
    });

    expect(getHistory).toHaveBeenCalledTimes(1);
    expect(getHistory).toHaveBeenCalledWith({ repo: "owner/repo" });

    // The pending debounce must have been cancelled — no extra call fires.
    act(() => {
      vi.advanceTimersByTime(300);
    });
    expect(getHistory).toHaveBeenCalledTimes(1);

    vi.useRealTimers();
  });

  it("unsubscribes on unmount and clears the pending debounce timer", async () => {
    const unlisten = vi.fn();
    vi.mocked(onHistorySnapshot).mockImplementation((cb) => {
      snapshotCb = cb;
      return Promise.resolve(unlisten);
    });

    const { result, unmount } = renderHook(() => useReviewHistory());

    // Let onHistorySnapshot's promise resolve so the unlisten fn is registered
    // before we unmount.
    await act(async () => {});

    // Schedule a debounce so we can assert it is cleared on unmount.
    vi.useFakeTimers();
    act(() => {
      result.current.setFilters({ repo: "owner/repo" });
    });

    unmount();

    // The snapshot listener is torn down.
    expect(unlisten).toHaveBeenCalled();

    // The cleared debounce timer must not fire a getHistory after unmount.
    vi.mocked(getHistory).mockClear();
    act(() => {
      vi.advanceTimersByTime(300);
    });
    expect(getHistory).not.toHaveBeenCalled();

    vi.useRealTimers();
  });
});
