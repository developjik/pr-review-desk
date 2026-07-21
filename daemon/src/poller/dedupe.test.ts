import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mkdtempSync, rmSync } from "node:fs";
import { createDedupe, recordReview } from "./dedupe";

const TABLE_DDL = `CREATE TABLE review_state (pr_id INTEGER PRIMARY KEY, commit_sha TEXT NOT NULL, reviewed_at TEXT NOT NULL)`;

describe("poller/dedupe", () => {
  let db: DatabaseSync;
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "pr-review-dedupe-"));
    db = new DatabaseSync(join(tmpDir, "test.db"));
    db.exec(TABLE_DDL);
  });

  afterEach(() => {
    db.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  // --------------------------------------------------------------------------
  // createDedupe — shouldReview
  // --------------------------------------------------------------------------

  describe("shouldReview", () => {
    it("returns true when the PR has never been reviewed", async () => {
      const dedupe = createDedupe(db);
      expect(await dedupe.shouldReview(42, "abc123")).toBe(true);
    });

    it("returns false when the PR was reviewed at the same commit", async () => {
      recordReview(db, 42, "abc123", "2026-01-01T00:00:00Z");
      const dedupe = createDedupe(db);
      expect(await dedupe.shouldReview(42, "abc123")).toBe(false);
    });

    it("returns true when the PR was reviewed at a different commit", async () => {
      recordReview(db, 42, "abc123", "2026-01-01T00:00:00Z");
      const dedupe = createDedupe(db);
      expect(await dedupe.shouldReview(42, "def456")).toBe(true);
    });

    it("does not match across different PR ids", async () => {
      recordReview(db, 42, "abc123", "2026-01-01T00:00:00Z");
      const dedupe = createDedupe(db);
      // PR 99 at the same commit sha is still unreviewed
      expect(await dedupe.shouldReview(99, "abc123")).toBe(true);
    });

    it("returns true again after the PR is re-reviewed at a new commit", async () => {
      const dedupe = createDedupe(db);

      // First commit — reviewed
      recordReview(db, 42, "commit-1", "2026-01-01T00:00:00Z");
      expect(await dedupe.shouldReview(42, "commit-1")).toBe(false);

      // New commit — should re-review
      recordReview(db, 42, "commit-2", "2026-01-02T00:00:00Z");
      expect(await dedupe.shouldReview(42, "commit-1")).toBe(true);
      expect(await dedupe.shouldReview(42, "commit-2")).toBe(false);
    });
  });

  // --------------------------------------------------------------------------
  // recordReview
  // --------------------------------------------------------------------------

  describe("recordReview", () => {
    it("inserts a new review state row", () => {
      recordReview(db, 42, "abc123", "2026-01-01T00:00:00Z");

      const row = db
        .prepare("SELECT pr_id, commit_sha, reviewed_at FROM review_state WHERE pr_id = 42")
        .get() as { pr_id: number; commit_sha: string; reviewed_at: string };

      expect(row).toEqual({
        pr_id: 42,
        commit_sha: "abc123",
        reviewed_at: "2026-01-01T00:00:00Z",
      });
    });

    it("upserts — updates commit_sha and reviewed_at on conflict, no duplicate rows", () => {
      recordReview(db, 42, "aaa", "2026-01-01T00:00:00Z");
      recordReview(db, 42, "bbb", "2026-01-02T00:00:00Z");

      const rows = db
        .prepare("SELECT commit_sha, reviewed_at FROM review_state WHERE pr_id = 42")
        .all() as Array<{ commit_sha: string; reviewed_at: string }>;

      expect(rows).toHaveLength(1);
      expect(rows[0].commit_sha).toBe("bbb");
      expect(rows[0].reviewed_at).toBe("2026-01-02T00:00:00Z");
    });

    it("defaults reviewedAt to the current ISO timestamp when omitted", () => {
      const before = new Date().toISOString();
      recordReview(db, 42, "abc123");
      const after = new Date().toISOString();

      const row = db
        .prepare("SELECT reviewed_at FROM review_state WHERE pr_id = 42")
        .get() as { reviewed_at: string };

      expect(row.reviewed_at >= before).toBe(true);
      expect(row.reviewed_at <= after).toBe(true);
    });

    it("keeps independent rows for different PR ids", () => {
      recordReview(db, 1, "sha-1", "2026-01-01T00:00:00Z");
      recordReview(db, 2, "sha-2", "2026-01-02T00:00:00Z");

      const count = db
        .prepare("SELECT COUNT(*) as n FROM review_state")
        .get() as { n: number };
      expect(count.n).toBe(2);
    });
  });

  // --------------------------------------------------------------------------
  // Integration: createDedupe + recordReview round-trip
  // --------------------------------------------------------------------------

  describe("round-trip", () => {
    it("recordReview flips shouldReview from true to false", async () => {
      const dedupe = createDedupe(db);

      expect(await dedupe.shouldReview(7, "sha-A")).toBe(true);
      recordReview(db, 7, "sha-A", "2026-01-01T00:00:00Z");
      expect(await dedupe.shouldReview(7, "sha-A")).toBe(false);
      expect(await dedupe.shouldReview(7, "sha-B")).toBe(true);
    });
  });
});
