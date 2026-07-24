/**
 * SQLite database connection (node:sqlite).
 *
 * Owns the process-wide {@link DatabaseSync} instance, opened against the
 * host-supplied `config.dbPath`. Opens in WAL mode (concurrent reads during a
 * write transaction) and idempotently creates the four domain tables.
 *
 * Tables (see migrations.ts):
 *   - review_state   one row per reviewed PR; keyed by `pr_id` so the latest
 *                    reviewed commit wins. Dedupe (R9) reads this.
 *   - review_run     one row per review execution (P4 writes; P5 rolls up).
 *   - review_finding one row per LLM finding belonging to a run.
 *   - queue          PRs awaiting review processing (R23; drained bounded-concurrently up to maxConcurrentReviews).
 *
 * `pr_id` is a stable surrogate derived from `repo#number` (see
 * `poller/util.ts` `prId`); it has no GitHub-global integer equivalent, so we
 * synthesize one rather than introduce a fifth lookup table.
 */
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { runMigrations } from "./migrations";
import { DatabaseSync } from "node:sqlite";

/** Lifecycle status of a queue row. */
export type QueueStatus = "pending" | "processing" | "done" | "failed" | "skipped";

let active: DatabaseSync | null = null;
let activePath: string | null = null;

/**
 * Open (or reuse) the daemon database. Idempotent: calling again with the same
 * path returns the existing handle; calling with a different path is a
 * programmer error (the daemon owns a single DB).
 */
export function openDatabase(dbPath: string): DatabaseSync {
  if (active) {
    if (dbPath !== activePath) {
      throw new Error(
        `database already open at "${activePath}"; refusing to reopen at "${dbPath}"`,
      );
    }
    return active;
  }
  mkdirSync(dirname(dbPath), { recursive: true });
  const db = new DatabaseSync(dbPath);
  // Per-connection PRAGMAs (run unconditionally every open)
  db.exec("PRAGMA journal_mode=WAL");
  db.exec("PRAGMA foreign_keys=ON");
  db.exec("PRAGMA busy_timeout=5000");

  // Version-gated DDL migrations.
  runMigrations(db);
  active = db;
  activePath = dbPath;
  return db;
}

/** The open database, or null before {@link openDatabase}. */
export function getDatabase(): DatabaseSync | null {
  return active;
}

/** Close + forget the handle. Safe to call before process exit. */
export function closeDatabase(): void {
  if (active) {
    active.close();
    active = null;
    activePath = null;
  }
}
