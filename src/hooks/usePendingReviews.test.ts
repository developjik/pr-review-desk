// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

vi.mock("../lib/tauri", () => ({
  approveReview: vi.fn(),
  rejectReview: vi.fn(),
  listPendingReviews: vi.fn(),
  onPendingSnapshot: vi.fn(() => Promise.resolve(() => {})),
  onReviewPending: vi.fn(() => Promise.resolve(() => {})),
  onPendingResolved: vi.fn(() => Promise.resolve(() => {})),
  onDaemonReady: vi.fn(() => Promise.resolve(() => {})),
}));

// Imports below resolve against the mocked "../lib/tauri" module (vi.mock is
// hoisted above all imports by vitest).
import { usePendingReviews, type SubmitResult } from "./usePendingReviews";
import {
  approveReview,
  rejectReview,
  listPendingReviews,
  onReviewPending,
  onPendingSnapshot,
  onPendingResolved,
  onDaemonReady,
} from "../lib/tauri";
import type { PendingReview } from "@pr-review/shared";

// Captured listener callbacks (registered synchronously inside the hook's
// useEffect, which renderHook flushes before returning).
let snapshotCb: ((reviews: PendingReview[]) => void) | null = null;
let reviewPendingCb: ((r: PendingReview) => void) | null = null;
let resolvedCb:
  | ((reviewId: number, prId: number, status: string) => void)
  | null = null;
let readyCb: (() => void) | null = null;

function makeReview(id: number): PendingReview {
  return {
    reviewId: id,
    prId: id,
    prNumber: id,
    repo: "owner/repo",
    title: `PR ${id}`,
    headSha: "abc123",
    summary: "summary",
    findings: [],
    createdAt: "2025-01-01T00:00:00Z",
  };
}

function isSubmittingFor(
  map: Record<number, "approve" | "reject" | null> | undefined,
  id: number,
): boolean {
  return Boolean(map && map[id]);
}

beforeEach(() => {
  vi.clearAllMocks();

  // Default IPC implementations.
  vi.mocked(listPendingReviews).mockResolvedValue(undefined);
  vi.mocked(approveReview).mockResolvedValue(undefined);
  vi.mocked(rejectReview).mockResolvedValue(undefined);

  // Reset captured callbacks, then re-wire listeners to capture them.
  snapshotCb = null;
  reviewPendingCb = null;
  resolvedCb = null;
  readyCb = null;

  vi.mocked(onPendingSnapshot).mockImplementation((cb) => {
    snapshotCb = cb;
    return Promise.resolve(() => {});
  });
  vi.mocked(onReviewPending).mockImplementation((cb) => {
    reviewPendingCb = cb;
    return Promise.resolve(() => {});
  });
  vi.mocked(onPendingResolved).mockImplementation((cb) => {
    resolvedCb = cb;
    return Promise.resolve(() => {});
  });
  vi.mocked(onDaemonReady).mockImplementation((cb) => {
    readyCb = cb;
    return Promise.resolve(() => {});
  });
});

describe("usePendingReviews — approve", () => {
  it("(a) removes the card and clears submitting when approve resolves", async () => {
    const { result } = renderHook(() => usePendingReviews());

    // Seed a pending review via the snapshot callback.
    act(() => {
      snapshotCb?.([makeReview(1)]);
    });
    expect(result.current.pending).toHaveLength(1);

    let res: SubmitResult | undefined;
    await act(async () => {
      res = await result.current.approve(1, ["f1"]);
    });

    expect(res).toEqual({ ok: true });
    expect(result.current.pending).toHaveLength(0);
    expect(isSubmittingFor(result.current.submitting, 1)).toBe(false);
    expect(vi.mocked(approveReview)).toHaveBeenCalledWith(1, ["f1"], undefined);
  });

  it("(b) keeps the card and returns {ok:false} when approve rejects", async () => {
    vi.mocked(approveReview).mockRejectedValue(new Error("boom"));

    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      snapshotCb?.([makeReview(2)]);
    });

    let res: SubmitResult | undefined;
    await act(async () => {
      res = await result.current.approve(2);
    });

    expect(res).toEqual({ ok: false, error: "boom" });
    expect(result.current.pending).toHaveLength(1);
    expect(isSubmittingFor(result.current.submitting, 2)).toBe(false);
  });
});

describe("usePendingReviews — resolve race (idempotency)", () => {
  it("(c) stays idempotent when pending:resolved fires during the approve await", async () => {
    // Hold approveReview open until we release it, so we can interleave the
    // daemon-driven pending:resolved event mid-await.
    let releaseApprove!: () => void;
    vi.mocked(approveReview).mockReturnValue(
      new Promise<void>((resolve) => {
        releaseApprove = resolve;
      }),
    );

    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      snapshotCb?.([makeReview(3)]);
    });
    expect(result.current.pending).toHaveLength(1);

    // Kick off approve (in-flight, awaiting the deferred IPC).
    let approvePromise!: Promise<SubmitResult>;
    act(() => {
      approvePromise = result.current.approve(3);
    });
    await waitFor(() => {
      expect(result.current.submitting[3]).toBe("approve");
    });

    // Daemon fires pending:resolved for the same review while we are still
    // awaiting approve. The event removes the card.
    act(() => {
      resolvedCb?.(3, 3, "approved");
    });
    expect(result.current.pending).toHaveLength(0);

    // Now let approve resolve. The success-path filter is idempotent: the card
    // is already gone, so this is a no-op (no crash, no double-remove, no
    // phantom re-add).
    let res: SubmitResult | undefined;
    await act(async () => {
      releaseApprove();
      res = await approvePromise;
    });

    expect(res).toEqual({ ok: true });
    expect(result.current.pending).toHaveLength(0);
    expect(isSubmittingFor(result.current.submitting, 3)).toBe(false);
  });
});

describe("usePendingReviews — daemon ready (M9)", () => {
  it("(d) clears submitting when daemon becomes ready", () => {
    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      snapshotCb?.([makeReview(4)]);
    });

    // Park an approve in-flight so submitting[4] === "approve".
    let releaseApprove!: () => void;
    vi.mocked(approveReview).mockReturnValue(
      new Promise<void>((resolve) => {
        releaseApprove = resolve;
      }),
    );
    act(() => {
      void result.current.approve(4);
    });
    expect(result.current.submitting[4]).toBe("approve");

    // Daemon restarts → onDaemonReady fires → submitting cleared (M9).
    const callsBefore = vi.mocked(listPendingReviews).mock.calls.length;
    act(() => {
      readyCb?.();
    });
    expect(isSubmittingFor(result.current.submitting, 4)).toBe(false);
    // M9 also re-requests the snapshot on ready.
    expect(vi.mocked(listPendingReviews).mock.calls.length).toBeGreaterThan(
      callsBefore,
    );

    // Release the deferred approve so the test tears down cleanly (its finally
    // re-deletes an already-absent key — harmless).
    releaseApprove();
  });
});

describe("usePendingReviews — reject", () => {
  it("removes the card and clears submitting when reject resolves", async () => {
    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      snapshotCb?.([makeReview(5)]);
    });

    let res: SubmitResult | undefined;
    await act(async () => {
      res = await result.current.reject(5);
    });

    expect(res).toEqual({ ok: true });
    expect(result.current.pending).toHaveLength(0);
    expect(isSubmittingFor(result.current.submitting, 5)).toBe(false);
    expect(vi.mocked(rejectReview)).toHaveBeenCalledWith(5);
  });

  it("keeps the card and returns {ok:false} when reject rejects", async () => {
    vi.mocked(rejectReview).mockRejectedValue(new Error("nope"));

    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      snapshotCb?.([makeReview(6)]);
    });

    let res: SubmitResult | undefined;
    await act(async () => {
      res = await result.current.reject(6);
    });

    expect(res).toEqual({ ok: false, error: "nope" });
    expect(result.current.pending).toHaveLength(1);
    expect(isSubmittingFor(result.current.submitting, 6)).toBe(false);
  });
});

describe("usePendingReviews — live updates", () => {
  it("onReviewPending prepends a new review without duplicating", () => {
    const { result } = renderHook(() => usePendingReviews());
    act(() => {
      reviewPendingCb?.(makeReview(7));
    });
    expect(result.current.pending).toHaveLength(1);
    expect(result.current.pending[0]?.reviewId).toBe(7);

    // Re-delivering the same review is a no-op.
    act(() => {
      reviewPendingCb?.(makeReview(7));
    });
    expect(result.current.pending).toHaveLength(1);
  });
});
