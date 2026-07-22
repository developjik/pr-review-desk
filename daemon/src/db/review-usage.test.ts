/**
 * review-usage — token-usage persistence (H2 retry-dedup, totals, coercion).
 *
 * Mirrors pending-reviews.test.ts: fresh in-memory `node:sqlite` DB migrated to
 * the latest schema, exercising insert round-trip, INSERT OR IGNORE dedup, and
 * cross-PR SUM aggregation.
 */
import { describe, it, expect, beforeEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./migrations";
import {
  insertUsage,
  getUsageByPr,
  getUsageTotalSince,
  getUsageByModelSince,
  type InsertUsageParams,
} from "./review-usage";
import type { TokenUsage } from "../types/domain";

/** Fresh in-memory DB migrated to the latest schema. */
function freshDb(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  runMigrations(db);
  return db;
}

const U: TokenUsage = { promptTokens: 100, completionTokens: 20, totalTokens: 120 };

function params(overrides: Partial<InsertUsageParams> = {}): InsertUsageParams {
  return {
    prId: 1,
    prNumber: 42,
    repo: "owner/repo",
    headSha: "abc123",
    file: "src/a.ts",
    model: "test-model",
    usage: U,
    createdAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  };
}

let db: DatabaseSync;

beforeEach(() => {
  db = freshDb();
});

describe("review-usage — insert + getUsageByPr", () => {
  it("inserts 2 rows for different files of a PR and getUsageByPr returns both", () => {
    insertUsage(db, params({ file: "src/a.ts" }));
    insertUsage(db, params({ file: "src/b.ts", usage: { promptTokens: 50, completionTokens: 10, totalTokens: 60 } }));

    const rows = getUsageByPr(db, 1);
    expect(rows).toHaveLength(2);
    expect(rows.map((r) => r.file).sort()).toEqual(["src/a.ts", "src/b.ts"]);

    const a = rows.find((r) => r.file === "src/a.ts")!;
    expect(a.promptTokens).toBe(100);
    expect(a.completionTokens).toBe(20);
    expect(a.totalTokens).toBe(120);
  });

  it("maps rows back to FileUsage shape ({ file, promptTokens, completionTokens, totalTokens })", () => {
    insertUsage(db, params({ file: "lib/x.go", usage: { promptTokens: 7, completionTokens: 3, totalTokens: 10 } }));
    const [row] = getUsageByPr(db, 1);
    expect(row).toEqual({
      file: "lib/x.go",
      promptTokens: 7,
      completionTokens: 3,
      totalTokens: 10,
    });
  });

  it("returns [] for a PR with no usage rows", () => {
    expect(getUsageByPr(db, 999)).toEqual([]);
  });
});

describe("review-usage — INSERT OR IGNORE retry-dedup (H2)", () => {
  it("inserting the SAME (prId, headSha, file, model) twice yields only 1 row", () => {
    const first = insertUsage(db, params());
    insertUsage(db, params()); // identical key tuple — IGNORED by the unique index

    // The dedup guarantee: still exactly ONE row after the duplicate insert.
    expect(getUsageByPr(db, 1)).toHaveLength(1);
    // Original row untouched (not overwritten with a new id / new counts).
    expect(getUsageByPr(db, 1)[0].promptTokens).toBe(100);
    expect(first).toBeGreaterThan(0);
  });

  it("dedupes on the full (prId, headSha, file, model) tuple — different file is a NEW row", () => {
    insertUsage(db, params({ file: "src/a.ts" }));
    insertUsage(db, params({ file: "src/b.ts" })); // different file ⇒ distinct
    insertUsage(db, params({ file: "src/a.ts", model: "other-model" })); // different model ⇒ distinct
    expect(getUsageByPr(db, 1)).toHaveLength(3);
  });

  it("a re-run with a different headSha is a NEW row (new commit ⇒ re-review billed)", () => {
    insertUsage(db, params({ headSha: "aaa" }));
    insertUsage(db, params({ headSha: "bbb" }));
    expect(getUsageByPr(db, 1)).toHaveLength(2);
  });
});

describe("review-usage — getUsageTotalSince (cross-PR SUM)", () => {
  it("sums token counts across PRs whose created_at >= sinceIso", () => {
    insertUsage(db, params({ prId: 1, file: "a", createdAt: "2026-01-01T00:00:00.000Z", usage: { promptTokens: 100, completionTokens: 20, totalTokens: 120 } }));
    insertUsage(db, params({ prId: 2, file: "b", createdAt: "2026-02-01T00:00:00.000Z", usage: { promptTokens: 200, completionTokens: 30, totalTokens: 230 } }));
    insertUsage(db, params({ prId: 3, file: "c", createdAt: "2025-01-01T00:00:00.000Z", usage: { promptTokens: 999, completionTokens: 999, totalTokens: 999 } }));

    const total = getUsageTotalSince(db, "2026-01-01T00:00:00.000Z");
    // Only the two 2026 rows count (the 2025 row is before the cutoff).
    expect(total).toEqual({ promptTokens: 300, completionTokens: 50, totalTokens: 350 });
  });

  it("returns a zero-aggregate when no rows match the cutoff", () => {
    expect(getUsageTotalSince(db, "2030-01-01T00:00:00.000Z")).toEqual({
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
    });
  });

  it("returns a zero-aggregate on an empty table", () => {
    expect(getUsageTotalSince(db, "1970-01-01T00:00:00.000Z")).toEqual({
      promptTokens: 0,
      completionTokens: 0,
      totalTokens: 0,
    });
  });
});

describe("review-usage — missing/coerced usage fields", () => {
  it("stores explicit zero token counts without NaN", () => {
    insertUsage(db, params({ usage: { promptTokens: 0, completionTokens: 0, totalTokens: 0 } }));
    const [row] = getUsageByPr(db, 1);
    expect(row.promptTokens).toBe(0);
    expect(row.completionTokens).toBe(0);
    expect(row.totalTokens).toBe(0);
  });

  it("a NULL file (future aggregate row) round-trips as file: null", () => {
    insertUsage(db, params({ file: null }));
    const [row] = getUsageByPr(db, 1);
    expect(row.file).toBeNull();
    expect(row.promptTokens).toBe(100);
  });
});

describe("review-usage — getUsageByModelSince (AC4.6 per-model SUM)", () => {
  it("groups usage by model and sums tokens per model", () => {
    // Model A: two rows (same model, different files) that should be summed.
    insertUsage(db, params({
      file: "src/a.ts",
      model: "model-a",
      usage: { promptTokens: 100, completionTokens: 20, totalTokens: 120 },
      createdAt: "2026-01-15T00:00:00.000Z",
    }));
    insertUsage(db, params({
      file: "src/b.ts",
      model: "model-a",
      usage: { promptTokens: 50, completionTokens: 10, totalTokens: 60 },
      createdAt: "2026-01-16T00:00:00.000Z",
    }));
    // Model B: one row.
    insertUsage(db, params({
      file: "src/c.ts",
      model: "model-b",
      usage: { promptTokens: 200, completionTokens: 40, totalTokens: 240 },
      createdAt: "2026-01-17T00:00:00.000Z",
    }));

    const rows = getUsageByModelSince(db, "2026-01-01T00:00:00.000Z");
    expect(rows).toHaveLength(2);

    const a = rows.find((r) => r.model === "model-a")!;
    expect(a.promptTokens).toBe(150);
    expect(a.completionTokens).toBe(30);
    expect(a.totalTokens).toBe(180);

    const b = rows.find((r) => r.model === "model-b")!;
    expect(b.promptTokens).toBe(200);
    expect(b.completionTokens).toBe(40);
    expect(b.totalTokens).toBe(240);
  });

  it("returns [] for an empty table", () => {
    expect(getUsageByModelSince(db, "1970-01-01T00:00:00.000Z")).toEqual([]);
  });

  it("excludes rows before the cutoff", () => {
    insertUsage(db, params({
      model: "model-a",
      usage: { promptTokens: 100, completionTokens: 20, totalTokens: 120 },
      createdAt: "2025-01-01T00:00:00.000Z",
    }));
    insertUsage(db, params({
      model: "model-b",
      usage: { promptTokens: 50, completionTokens: 10, totalTokens: 60 },
      createdAt: "2026-07-01T00:00:00.000Z",
    }));

    const rows = getUsageByModelSince(db, "2026-01-01T00:00:00.000Z");
    expect(rows).toHaveLength(1);
    expect(rows[0].model).toBe("model-b");
  });
});
