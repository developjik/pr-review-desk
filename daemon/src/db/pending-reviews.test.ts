import { describe, it, expect } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { runMigrations } from "./migrations";
import {
  insertPendingReview,
  getPendingReview,
  listPendingReviews,
  hasPendingReview,
  resolvePendingReview,
  type InsertPendingParams,
} from "./pending-reviews";
import type { Finding } from "../types/domain";

/** Shared minimal insert params; callers override `diff`. */
function baseParams(overrides: Partial<InsertPendingParams> = {}): InsertPendingParams {
  return {
    prId: 100,
    prNumber: 7,
    repo: "acme/widget",
    headSha: "deadbeef",
    title: "Add feature",
    summary: "Looks reasonable overall.",
    inline: [{ file: "src/a.ts", line: 12, severity: "low", area: "style", comment: "nit" }] satisfies Finding[],
    degraded: [{ file: "src/b.ts", line: null, severity: "info", area: "structure", comment: "n/a" }] satisfies Finding[],
    githubReviewId: 0,
    ...overrides,
  };
}

/** Fresh in-memory DB migrated to the latest schema (v6). */
function freshDb(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  runMigrations(db);
  return db;
}

describe("pending-reviews — diff storage (v6)", () => {
  it("insert WITH diff round-trips through getPendingReview and listPendingReviews", () => {
    const db = freshDb();
    const diff: Record<string, string> = {
      "src/a.ts": "@@ -10,3 +10,4 @@\n context\n-removed\n+added\n+more\n",
    };
    const id = insertPendingReview(db, baseParams({ diff }));

    const byId = getPendingReview(db, id);
    expect(byId).not.toBeNull();
    expect(byId!.diff).toEqual(diff);
    // JSON round-trip integrity: a specific file's hunk matches the input.
    expect(byId!.diff!["src/a.ts"]).toBe(diff["src/a.ts"]);

    const listed = listPendingReviews(db);
    expect(listed).toHaveLength(1);
    expect(listed[0].reviewId).toBe(id);
    expect(listed[0].diff).toEqual(diff);
  });

  it("insert with diff: null returns diff === undefined", () => {
    const db = freshDb();
    const id = insertPendingReview(db, baseParams({ diff: null }));

    const review = getPendingReview(db, id);
    expect(review).not.toBeNull();
    expect(review!.diff).toBeUndefined();
  });

  it("insert with diff omitted returns diff === undefined", () => {
    const db = freshDb();
    insertPendingReview(db, baseParams());

    const listed = listPendingReviews(db);
    expect(listed[0].diff).toBeUndefined();
  });

  it("findings parsing is unchanged when diff is present", () => {
    const db = freshDb();
    const id = insertPendingReview(db, baseParams({ diff: { "src/a.ts": "@@ hunk" } }));

    const review = getPendingReview(db, id);
    // Two findings (1 inline + 1 degraded), ids stamped i0/d0.
    expect(review!.findings.map((f) => f.id)).toEqual(["i0", "d0"]);
    expect(review!.findings[0].file).toBe("src/a.ts");
  });

  describe("real v4 → v5 upgrade (AC1.4)", () => {
    /** pending_reviews schema exactly as it existed at end of v4 (no diff_json). */
    const V4_DDL = `
      CREATE TABLE pending_reviews (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        pr_id         INTEGER NOT NULL,
        pr_number     INTEGER NOT NULL,
        repo          TEXT NOT NULL,
        head_sha      TEXT NOT NULL,
        title         TEXT,
        summary       TEXT NOT NULL,
        findings_json TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'pending',
        created_at    TEXT NOT NULL,
        resolved_at   TEXT,
        github_review_id INTEGER
      );
      CREATE INDEX pending_reviews_status_idx ON pending_reviews (status);
      CREATE UNIQUE INDEX pending_reviews_active_unique
        ON pending_reviews (pr_id, head_sha) WHERE status = 'pending';
    `;

    function seedV4(): DatabaseSync {
      const db = new DatabaseSync(":memory:");
      db.exec(V4_DDL);
      db.exec("PRAGMA user_version = 4");
      // A fully-populated v4 row (no diff_json column).
      db.prepare(
        `INSERT INTO pending_reviews
          (pr_id, pr_number, repo, head_sha, title, summary, findings_json, status, created_at, github_review_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`,
      ).run(
        555,
        9,
        "acme/legacy",
        "cafef00d",
        "Old PR",
        "legacy summary",
        JSON.stringify({
          inline: [{ id: "i0", file: "src/x.ts", line: 1, severity: "low", area: "style", comment: "old" }],
          degraded: [],
          summary: "legacy summary",
        }),
        new Date("2024-01-01T00:00:00.000Z").toISOString(),
        42,
      );
      return db;
    }

    it("upgrades user_version to the latest and adds a nullable diff_json column", () => {
      const db = seedV4();
      runMigrations(db);

      const version = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
      expect(version).toBe(6);

      // The column now exists and is nullable.
      const cols = db
        .prepare("PRAGMA table_info(pending_reviews)")
        .all() as Array<{ name: string; notnull: number }>;
      const col = cols.find((c) => c.name === "diff_json");
      expect(col).toBeDefined();
      expect(col!.notnull).toBe(0); // nullable
    });

    it("loads a pre-existing v4 row via rowToPendingReview with diff === undefined (no crash)", () => {
      const db = seedV4();
      runMigrations(db);

      const listed = listPendingReviews(db);
      expect(listed).toHaveLength(1);
      const review = listed[0];
      expect(review.repo).toBe("acme/legacy");
      expect(review.findings.map((f) => f.id)).toEqual(["i0"]);
      expect(review.diff).toBeUndefined(); // NULL → undefined (AC1.4)

      // getPendingReview (any status) behaves identically.
      const byId = getPendingReview(db, review.reviewId);
      expect(byId).not.toBeNull();
      expect(byId!.diff).toBeUndefined();
    });

    it("after upgrade, new inserts can write diff_json", () => {
      const db = seedV4();
      runMigrations(db);

      const id = insertPendingReview(db, baseParams({ diff: { "src/a.ts": "@@ hunk" } }));
      const review = getPendingReview(db, id);
      expect(review!.diff).toEqual({ "src/a.ts": "@@ hunk" });
    });
  });

  describe("migration idempotency (AC1.5)", () => {
    it("running runMigrations twice on a fresh DB keeps user_version at the latest with no error", () => {
      const db = new DatabaseSync(":memory:");
      runMigrations(db);
      expect(() => runMigrations(db)).not.toThrow();

      const version = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
      expect(version).toBe(6);
    });

    it("running runMigrations again on an upgraded v6 DB is a no-op", () => {
      const db = new DatabaseSync(":memory:");
      runMigrations(db);
      runMigrations(db);

      insertPendingReview(db, baseParams({ diff: { "src/a.ts": "@@ hunk" } }));
      expect(() => runMigrations(db)).not.toThrow();
      expect(listPendingReviews(db)).toHaveLength(1);
    });
  });

  describe("hasPendingReview / resolvePendingReview still behave", () => {
    it("detects pending rows and resolves them (findingsJson + githubReviewId preserved)", () => {
      const db = freshDb();
      const id = insertPendingReview(db, baseParams({ diff: { "src/a.ts": "@@ hunk" }, githubReviewId: 7 }));

      expect(hasPendingReview(db, baseParams().prId, baseParams().headSha)).toBe(true);

      const resolved = resolvePendingReview(db, id, "approved");
      expect(resolved).not.toBeNull();
      expect(resolved!.githubReviewId).toBe(7);
      expect(resolved!.findingsJson).toContain("i0");
      expect(resolved!.summary).toBe("Looks reasonable overall.");

      // Resolving again is a no-op.
      expect(resolvePendingReview(db, id, "approved")).toBeNull();
      // No longer pending.
      expect(hasPendingReview(db, baseParams().prId, baseParams().headSha)).toBe(false);
    });
  });
});
