/**
 * finding-feedback — per-finding human feedback persistence (upsert toggle,
 * per-PR rows, cross-PR aggregates).
 *
 * Mirrors review-usage.test.ts: fresh in-memory `node:sqlite` DB migrated to
 * the latest schema, exercising upsert round-trip, the (prId, findingKey)
 * toggle, per-PR selection, and cross-PR stats/pattern aggregation.
 */
import { describe, it, expect, beforeEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./migrations";
import {
  upsertFeedback,
  getFeedbackByPr,
  getFeedbackStats,
  getFalsePositivePatterns,
  type UpsertFeedbackParams,
} from "./finding-feedback";

/** Fresh in-memory DB migrated to the latest schema. */
function freshDb(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  runMigrations(db);
  return db;
}

function params(overrides: Partial<UpsertFeedbackParams> = {}): UpsertFeedbackParams {
  return {
    prId: 1,
    findingKey: "src/a.ts:10:unreachable",
    file: "src/a.ts",
    line: 10,
    comment: "Unreachable code after return",
    area: "logic",
    severity: "high",
    feedback: "useful",
    createdAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  };
}

let db: DatabaseSync;

beforeEach(() => {
  db = freshDb();
});

describe("finding-feedback — upsertFeedback", () => {
  it("inserts a new row", () => {
    upsertFeedback(db, params());

    const rows = getFeedbackByPr(db, 1);
    expect(rows).toHaveLength(1);

    const [row] = rows;
    expect(row.findingKey).toBe("src/a.ts:10:unreachable");
    expect(row.file).toBe("src/a.ts");
    expect(row.line).toBe(10);
    expect(row.comment).toBe("Unreachable code after return");
    expect(row.area).toBe("logic");
    expect(row.severity).toBe("high");
    expect(row.feedback).toBe("useful");
    expect(row.createdAt).toBe("2026-01-01T00:00:00.000Z");
  });

  it("on the same (prId, findingKey) updates the feedback value (toggles useful → false_positive)", () => {
    upsertFeedback(db, params({ feedback: "useful" }));
    // Same key tuple — the value flips rather than creating a duplicate.
    upsertFeedback(db, params({ feedback: "false_positive", comment: "Not actually unreachable" }));

    const rows = getFeedbackByPr(db, 1);
    expect(rows).toHaveLength(1);

    const [row] = rows;
    expect(row.feedback).toBe("false_positive");
    expect(row.comment).toBe("Not actually unreachable");
  });

  it("on a different findingKey for the same prId creates a second row", () => {
    upsertFeedback(db, params({ findingKey: "src/a.ts:10:unreachable", feedback: "useful" }));
    upsertFeedback(db, params({ findingKey: "src/b.ts:5:unused", file: "src/b.ts", line: 5, feedback: "false_positive" }));

    const rows = getFeedbackByPr(db, 1);
    expect(rows).toHaveLength(2);
    expect(rows.map((r) => r.findingKey).sort()).toEqual(["src/a.ts:10:unreachable", "src/b.ts:5:unused"]);
  });
});

describe("finding-feedback — getFeedbackByPr", () => {
  it("returns rows for that PR only", () => {
    upsertFeedback(db, params({ prId: 1, findingKey: "k1" }));
    upsertFeedback(db, params({ prId: 1, findingKey: "k2" }));
    upsertFeedback(db, params({ prId: 2, findingKey: "k1", feedback: "false_positive" }));

    const rows = getFeedbackByPr(db, 1);
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => r.prId === 1)).toBe(true);
  });

  it("returns [] for a PR with no feedback", () => {
    expect(getFeedbackByPr(db, 999)).toEqual([]);
  });
});

describe("finding-feedback — getFeedbackStats", () => {
  it("counts useful and false_positive correctly", () => {
    upsertFeedback(db, params({ prId: 1, findingKey: "k1", feedback: "useful" }));
    upsertFeedback(db, params({ prId: 1, findingKey: "k2", feedback: "useful" }));
    upsertFeedback(db, params({ prId: 2, findingKey: "k3", feedback: "false_positive" }));

    const stats = getFeedbackStats(db);
    expect(stats.useful).toBe(2);
    expect(stats.falsePositive).toBe(1);
  });

  it("byArea groups false_positive by area", () => {
    upsertFeedback(db, params({ prId: 1, findingKey: "k1", area: "logic", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 2, findingKey: "k2", area: "logic", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 3, findingKey: "k3", area: "style", feedback: "false_positive" }));
    // useful rows must NOT count toward byArea.
    upsertFeedback(db, params({ prId: 4, findingKey: "k4", area: "logic", feedback: "useful" }));

    const stats = getFeedbackStats(db);
    expect(stats.byArea).toEqual({ logic: 2, style: 1 });
  });

  it("returns zeros on an empty table", () => {
    const stats = getFeedbackStats(db);
    expect(stats).toEqual({ useful: 0, falsePositive: 0, byArea: {} });
  });
});

describe("finding-feedback — getFalsePositivePatterns", () => {
  it("groups by file+comment and counts", () => {
    // Same comment in the same file across two PRs → count 2.
    upsertFeedback(db, params({ prId: 1, findingKey: "k1", file: "src/a.ts", comment: "Unused import", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 2, findingKey: "k2", file: "src/a.ts", comment: "Unused import", feedback: "false_positive" }));
    // Different comment in the same file → distinct group.
    upsertFeedback(db, params({ prId: 3, findingKey: "k3", file: "src/a.ts", comment: "Unreachable", feedback: "false_positive" }));

    const patterns = getFalsePositivePatterns(db, 10);
    expect(patterns).toHaveLength(2);

    const top = patterns.find((p) => p.comment === "Unused import")!;
    expect(top.file).toBe("src/a.ts");
    expect(top.count).toBe(2);

    const other = patterns.find((p) => p.comment === "Unreachable")!;
    expect(other.count).toBe(1);
  });

  it("orders by count DESC and respects limit", () => {
    // Group A: count 3 (highest)
    upsertFeedback(db, params({ prId: 1, findingKey: "k1", file: "a.ts", comment: "c1", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 2, findingKey: "k2", file: "a.ts", comment: "c1", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 3, findingKey: "k3", file: "a.ts", comment: "c1", feedback: "false_positive" }));
    // Group B: count 2
    upsertFeedback(db, params({ prId: 4, findingKey: "k4", file: "b.ts", comment: "c2", feedback: "false_positive" }));
    upsertFeedback(db, params({ prId: 5, findingKey: "k5", file: "b.ts", comment: "c2", feedback: "false_positive" }));
    // Group C: count 1
    upsertFeedback(db, params({ prId: 6, findingKey: "k6", file: "c.ts", comment: "c3", feedback: "false_positive" }));

    const patterns = getFalsePositivePatterns(db, 2);
    expect(patterns).toHaveLength(2);
    expect(patterns[0].count).toBe(3);
    expect(patterns[1].count).toBe(2);
  });

  it("returns [] on an empty table", () => {
    expect(getFalsePositivePatterns(db, 10)).toEqual([]);
  });
});
