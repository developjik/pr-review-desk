/**
 * review-history — review-ledger persistence (insert, filters, status update,
 * totals, per-day rollup).
 *
 * Mirrors review-usage.test.ts: fresh in-memory `node:sqlite` DB migrated to
 * the latest schema, exercising insert round-trip + field mapping, dynamic
 * WHERE filters, status update, cross-row SUM aggregation, and per-day
 * grouping with zero-activity gap filling.
 */
import { describe, it, expect, beforeEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./migrations";
import {
  insertReviewHistory,
  updateReviewHistoryStatus,
  getHistory,
  getStatsSince,
  getStatsByDay,
  type InsertReviewHistoryParams,
} from "./review-history";

/** Fresh in-memory DB migrated to the latest schema. */
function freshDb(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  runMigrations(db);
  return db;
}

function params(overrides: Partial<InsertReviewHistoryParams> = {}): InsertReviewHistoryParams {
  return {
    prId: 1,
    prNumber: 42,
    repo: "owner/repo",
    headSha: "abc123",
    title: "Fix bug",
    author: "alice",
    reviewMode: "auto",
    findingsTotal: 3,
    sevHigh: 1,
    sevMedium: 1,
    sevLow: 1,
    posted: 1,
    degraded: 0,
    promptTokens: 100,
    completionTokens: 20,
    totalTokens: 120,
    costUsd: 0.05,
    status: "published",
    reviewedAt: "2026-07-01T10:00:00.000Z",
    createdAt: "2026-07-01T10:00:00.000Z",
    ...overrides,
  };
}

let db: DatabaseSync;

beforeEach(() => {
  db = freshDb();
});

describe("review-history — insert + getHistory", () => {
  it("inserts and getHistory returns the row with correct field mapping", () => {
    const id = insertReviewHistory(db, params());
    const [row] = getHistory(db, {});
    expect(row).toEqual({
      id,
      prId: 1,
      prNumber: 42,
      repo: "owner/repo",
      headSha: "abc123",
      title: "Fix bug",
      author: "alice",
      reviewMode: "auto",
      findingsTotal: 3,
      sevHigh: 1,
      sevMedium: 1,
      sevLow: 1,
      posted: 1,
      degraded: 0,
      promptTokens: 100,
      completionTokens: 20,
      totalTokens: 120,
      costUsd: 0.05,
      status: "published",
      reviewedAt: "2026-07-01T10:00:00.000Z",
      createdAt: "2026-07-01T10:00:00.000Z",
    });
  });

  it("defaults title/author to null when omitted and review_mode/status to their defaults", () => {
    const id = insertReviewHistory(
      db,
      params({ title: undefined, author: undefined, reviewMode: undefined, status: undefined }),
    );
    const [row] = getHistory(db, {});
    expect(row.id).toBe(id);
    expect(row.title).toBeNull();
    expect(row.author).toBeNull();
    expect(row.reviewMode).toBe("auto");
    expect(row.status).toBe("published");
  });
});

describe("review-history — getHistory filters", () => {
  it("filters by exact repo match", () => {
    insertReviewHistory(db, params({ repo: "owner/repo" }));
    insertReviewHistory(db, params({ repo: "other/repo" }));
    const rows = getHistory(db, { repo: "owner/repo" });
    expect(rows).toHaveLength(1);
    expect(rows[0].repo).toBe("owner/repo");
  });

  it("filters by since/until date range on reviewed_at (inclusive)", () => {
    insertReviewHistory(db, params({ reviewedAt: "2026-07-01T00:00:00.000Z" }));
    insertReviewHistory(db, params({ reviewedAt: "2026-07-15T00:00:00.000Z" }));
    insertReviewHistory(db, params({ reviewedAt: "2026-07-31T00:00:00.000Z" }));

    const rows = getHistory(db, {
      since: "2026-07-10T00:00:00.000Z",
      until: "2026-07-20T00:00:00.000Z",
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].reviewedAt).toBe("2026-07-15T00:00:00.000Z");
  });

  it("severity filter returns only rows with sev_high > 0", () => {
    insertReviewHistory(db, params({ sevHigh: 0, sevMedium: 2, sevLow: 0 }));
    insertReviewHistory(db, params({ sevHigh: 3, sevMedium: 0, sevLow: 0 }));
    const rows = getHistory(db, { severity: "high" });
    expect(rows).toHaveLength(1);
    expect(rows[0].sevHigh).toBe(3);
  });

  it("filters by exact author match", () => {
    insertReviewHistory(db, params({ author: "alice" }));
    insertReviewHistory(db, params({ author: "bob" }));
    const rows = getHistory(db, { author: "alice" });
    expect(rows).toHaveLength(1);
    expect(rows[0].author).toBe("alice");
  });

  it("respects the limit filter (default 200, clamped at 1000)", () => {
    for (let i = 0; i < 5; i++) {
      insertReviewHistory(db, params({ reviewedAt: `2026-07-0${i + 1}T00:00:00.000Z` }));
    }
    const rows = getHistory(db, { limit: 3 });
    expect(rows).toHaveLength(3);
  });

  it("orders newest-first by reviewed_at by default", () => {
    insertReviewHistory(db, params({ reviewedAt: "2026-07-01T00:00:00.000Z" }));
    insertReviewHistory(db, params({ reviewedAt: "2026-07-10T00:00:00.000Z" }));
    insertReviewHistory(db, params({ reviewedAt: "2026-07-05T00:00:00.000Z" }));
    const rows = getHistory(db, {});
    expect(rows.map((r) => r.reviewedAt)).toEqual([
      "2026-07-10T00:00:00.000Z",
      "2026-07-05T00:00:00.000Z",
      "2026-07-01T00:00:00.000Z",
    ]);
  });

  it("returns [] when no rows match", () => {
    expect(getHistory(db, { repo: "nobody/nothing" })).toEqual([]);
  });
});

describe("review-history — updateReviewHistoryStatus", () => {
  it("updates the status column for a matching (prId, headSha) row", () => {
    insertReviewHistory(db, params({ prId: 1, headSha: "abc123", status: "published" }));
    updateReviewHistoryStatus(db, 1, "abc123", "rejected");
    const [row] = getHistory(db, {});
    expect(row.status).toBe("rejected");
  });

  it("leaves rows for a different (prId, headSha) untouched", () => {
    insertReviewHistory(db, params({ prId: 1, headSha: "abc123", status: "published" }));
    insertReviewHistory(db, params({ prId: 2, headSha: "xyz789", status: "published" }));
    updateReviewHistoryStatus(db, 1, "abc123", "rejected");
    const rows = getHistory(db, {});
    const rejected = rows.find((r) => r.prId === 1);
    const untouched = rows.find((r) => r.prId === 2);
    expect(rejected!.status).toBe("rejected");
    expect(untouched!.status).toBe("published");
  });
});

describe("review-history — getStatsSince", () => {
  it("sums reviews/findings/cost/tokens since a cutoff", () => {
    insertReviewHistory(
      db,
      params({
        reviewedAt: "2026-07-10T00:00:00.000Z",
        findingsTotal: 5,
        posted: 2,
        degraded: 1,
        promptTokens: 100,
        completionTokens: 20,
        totalTokens: 120,
        costUsd: 0.5,
      }),
    );
    insertReviewHistory(
      db,
      params({
        reviewedAt: "2026-07-20T00:00:00.000Z",
        findingsTotal: 3,
        posted: 1,
        degraded: 0,
        promptTokens: 200,
        completionTokens: 40,
        totalTokens: 240,
        costUsd: 0.25,
      }),
    );
    // Before the cutoff — must be excluded.
    insertReviewHistory(
      db,
      params({
        reviewedAt: "2025-01-01T00:00:00.000Z",
        findingsTotal: 999,
        posted: 999,
        degraded: 999,
        promptTokens: 999,
        completionTokens: 999,
        totalTokens: 999,
        costUsd: 999,
      }),
    );

    const stats = getStatsSince(db, "2026-07-01T00:00:00.000Z");
    expect(stats).toEqual({
      totalReviews: 2,
      totalFindings: 8,
      totalPosted: 3,
      totalDegraded: 1,
      totalCostUsd: 0.75,
      totalPromptTokens: 300,
      totalCompletionTokens: 60,
      totalTokens: 360,
    });
  });

  it("returns a zero-aggregate on an empty table", () => {
    expect(getStatsSince(db, "1970-01-01T00:00:00.000Z")).toEqual({
      totalReviews: 0,
      totalFindings: 0,
      totalPosted: 0,
      totalDegraded: 0,
      totalCostUsd: 0,
      totalPromptTokens: 0,
      totalCompletionTokens: 0,
      totalTokens: 0,
    });
  });
});

describe("review-history — getStatsByDay", () => {
  it("groups by date and includes zero-activity days", () => {
    // Window: 2026-07-01 .. 2026-07-03 (3 days), sinceIso = 2026-07-03.
    insertReviewHistory(
      db,
      params({ reviewedAt: "2026-07-01T10:00:00.000Z", findingsTotal: 5, costUsd: 1.5 }),
    );
    insertReviewHistory(
      db,
      params({ reviewedAt: "2026-07-03T10:00:00.000Z", findingsTotal: 3, costUsd: 0.5 }),
    );
    // 2026-07-02 has no activity.

    const rows = getStatsByDay(db, "2026-07-03T23:59:59.999Z", 3);
    expect(rows).toHaveLength(3);
    expect(rows.map((r) => r.date)).toEqual(["2026-07-01", "2026-07-02", "2026-07-03"]);
    expect(rows[0]).toEqual({ date: "2026-07-01", reviews: 1, findings: 5, costUsd: 1.5 });
    expect(rows[1]).toEqual({ date: "2026-07-02", reviews: 0, findings: 0, costUsd: 0 });
    expect(rows[2]).toEqual({ date: "2026-07-03", reviews: 1, findings: 3, costUsd: 0.5 });
  });

  it("sums multiple reviews on the same day into one bucket", () => {
    insertReviewHistory(
      db,
      params({ reviewedAt: "2026-07-10T01:00:00.000Z", findingsTotal: 2, costUsd: 0.1 }),
    );
    insertReviewHistory(
      db,
      params({ reviewedAt: "2026-07-10T23:00:00.000Z", findingsTotal: 4, costUsd: 0.2 }),
    );
    const [row] = getStatsByDay(db, "2026-07-10T12:00:00.000Z", 1);
    expect(row.date).toBe("2026-07-10");
    expect(row.reviews).toBe(2);
    expect(row.findings).toBe(6);
    // 0.1 + 0.2 is not exactly representable — assert with tolerance.
    expect(row.costUsd).toBeCloseTo(0.3, 10);
  });

  it("returns empty array for an empty table", () => {
    expect(getStatsByDay(db, "2026-07-03T00:00:00.000Z", 7)).toEqual([]);
  });
});
