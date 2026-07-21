import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { DatabaseSync } from "node:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { reapStaleQueue, type ReapPRMeta, type SkipReason } from "./reaper";

/** Minimal queue DDL matching the daemon schema (only the columns the reaper reads). */
const QUEUE_DDL = `
  CREATE TABLE queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pr_id       INTEGER NOT NULL,
    repo        TEXT NOT NULL,
    head_sha    TEXT NOT NULL,
    number      INTEGER NOT NULL,
    enqueued_at TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'pending'
  )
`;

/** Insert a pending queue row for the given PR. */
function insertPending(
  db: DatabaseSync,
  prId: number,
  repo: string,
  number: number,
  sha = "deadbeef",
): void {
  db.prepare(
    `INSERT INTO queue (pr_id, repo, head_sha, number, enqueued_at, status)
     VALUES (?, ?, ?, ?, ?, 'pending')`,
  ).run(prId, repo, sha, number, new Date().toISOString());
}

function pendingCount(db: DatabaseSync): number {
  const row = db
    .prepare("SELECT COUNT(*) AS n FROM queue WHERE status = 'pending'")
    .get() as { n: number };
  return row.n;
}

describe("poller/reaper", () => {
  let db: DatabaseSync;
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "pr-review-reaper-"));
    db = new DatabaseSync(join(tmpDir, "test.db"));
    db.exec(QUEUE_DDL);
  });

  afterEach(() => {
    db.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  // --------------------------------------------------------------------------
  // reapStaleQueue
  // --------------------------------------------------------------------------

  describe("reapStaleQueue", () => {
    it("skips a pending PR whose GitHub state is merged", async () => {
      insertPending(db, 101, "acme/widget", 7);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async () => ({ merged: true, state: "closed" }),
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toEqual([{ prId: 101, reason: "merged" }]);
      expect(pendingCount(db)).toBe(0);
    });

    it("skips a pending PR whose GitHub state is closed (not merged)", async () => {
      insertPending(db, 101, "acme/widget", 7);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async () => ({ merged: false, state: "closed" }),
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toEqual([{ prId: 101, reason: "closed" }]);
      expect(pendingCount(db)).toBe(0);
    });

    it("leaves open PRs untouched", async () => {
      insertPending(db, 101, "acme/widget", 7);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async () => ({ merged: false, state: "open" }),
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toEqual([]);
      expect(pendingCount(db)).toBe(1);
    });

    it("does nothing when the queue has no pending rows", async () => {
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];
      await reapStaleQueue({
        db,
        fetchMeta: async () => ({ merged: true, state: "closed" }),
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });
      expect(skipped).toEqual([]);
    });

    it("leaves a row whose meta fetch fails for the next cycle", async () => {
      insertPending(db, 101, "acme/widget", 7);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async () => null,
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toEqual([]);
      expect(pendingCount(db)).toBe(1);
    });

    it("handles multiple pending PRs — skips stale ones, keeps open ones", async () => {
      insertPending(db, 1, "acme/a", 10);
      insertPending(db, 2, "acme/b", 20);
      insertPending(db, 3, "acme/c", 30);

      const metas = new Map<number, ReapPRMeta>([
        [10, { merged: true, state: "closed" }],
        [20, { merged: false, state: "open" }],
        [30, { merged: false, state: "closed" }],
      ]);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async (_o, _r, number) => metas.get(number) ?? null,
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toHaveLength(2);
      expect(skipped).toContainEqual({ prId: 1, reason: "merged" });
      expect(skipped).toContainEqual({ prId: 3, reason: "closed" });
      expect(pendingCount(db)).toBe(1);
    });

    it("skips rows with an unparseable repo string without throwing", async () => {
      insertPending(db, 999, "garbage-no-slash", 1);
      const skipped: Array<{ prId: number; reason: SkipReason }> = [];

      await reapStaleQueue({
        db,
        fetchMeta: async () => ({ merged: true, state: "closed" }),
        onSkip: (prId, reason) => skipped.push({ prId, reason }),
      });

      expect(skipped).toEqual([]);
      // The bad-repo row stays pending — it's not reaped but not crashed either.
      expect(pendingCount(db)).toBe(1);
    });
  });
});
