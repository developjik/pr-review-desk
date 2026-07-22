/**
 * Versioned migration runner for the daemon SQLite database.
 *
 * Migrations are forward-only, numbered, and transactional.
 * PRAGMA user_version tracks which migrations have been applied.
 * Each migration runs inside BEGIN/COMMIT; user_version is bumped
 * only after successful COMMIT, making migrations restartable.
 */
import type { DatabaseSync } from "node:sqlite";

export interface Migration {
  version: number;
  sql: string;
}

/**
 * Ordered migrations. v1 = bootstrap schema (review_state + queue).
 * Note: review_run and review_finding are intentionally omitted from v1
 * (they will be dropped in Phase 4 if they exist from older DBs).
 */
export const MIGRATIONS: Migration[] = [
  {
    version: 1,
    sql: `
      CREATE TABLE IF NOT EXISTS review_state (
        pr_id       INTEGER PRIMARY KEY,
        commit_sha  TEXT NOT NULL,
        reviewed_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS queue (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        pr_id       INTEGER NOT NULL,
        repo        TEXT NOT NULL,
        head_sha    TEXT NOT NULL,
        number      INTEGER NOT NULL,
        enqueued_at TEXT NOT NULL,
        status      TEXT NOT NULL DEFAULT 'pending'
      );

      CREATE UNIQUE INDEX IF NOT EXISTS queue_pending_unique
        ON queue (pr_id, head_sha) WHERE status = 'pending';
    `,
  },
  {
    version: 2,
    sql: `
      ALTER TABLE queue ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE queue ADD COLUMN next_attempt_at TEXT;
      ALTER TABLE queue ADD COLUMN fail_reason TEXT;
      ALTER TABLE queue ADD COLUMN claimed_at TEXT;
      DROP TABLE IF EXISTS review_finding;
      DROP TABLE IF EXISTS review_run;
    `,
  },
  {
    version: 3,
    sql: `
      CREATE TABLE IF NOT EXISTS pending_reviews (
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
        resolved_at   TEXT
      );
      CREATE INDEX IF NOT EXISTS pending_reviews_status_idx ON pending_reviews (status);
      CREATE UNIQUE INDEX IF NOT EXISTS pending_reviews_active_unique
        ON pending_reviews (pr_id, head_sha) WHERE status = 'pending';
    `,
  },
  {
    version: 4,
    sql: `
      ALTER TABLE pending_reviews ADD COLUMN github_review_id INTEGER;
    `,
  },
  {
    version: 5,
    sql: `
      ALTER TABLE pending_reviews ADD COLUMN diff_json TEXT;
    `,
  },
  {
    version: 6,
    sql: `
      CREATE TABLE IF NOT EXISTS review_usage (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        pr_id             INTEGER NOT NULL,
        pr_number         INTEGER NOT NULL,
        repo              TEXT NOT NULL,
        head_sha          TEXT NOT NULL,
        file              TEXT,
        model             TEXT NOT NULL,
        prompt_tokens     INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens      INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS review_usage_pr_idx     ON review_usage (pr_id);
      CREATE INDEX IF NOT EXISTS review_usage_created_idx ON review_usage (created_at);
      -- H2 retry-dedup: per-file rows are the dedup unit. INSERT OR IGNORE in review-usage.ts.
      CREATE UNIQUE INDEX IF NOT EXISTS review_usage_pr_file_model_uniq
        ON review_usage (pr_id, head_sha, file, model);
    `,
  },
];

/**
 * Run all pending migrations in order.
 * Each migration: BEGIN -> exec(sql) -> COMMIT -> PRAGMA user_version=N.
 * user_version is bumped ONLY after successful COMMIT (restartable).
 */
export function runMigrations(db: DatabaseSync): void {
  const currentVersion = (
    db.prepare("PRAGMA user_version").get() as { user_version?: number }
  ).user_version ?? 0;

  for (const migration of MIGRATIONS) {
    if (migration.version <= currentVersion) continue;

    db.exec("BEGIN");
    try {
      db.exec(migration.sql);
      db.exec("COMMIT");
    } catch (err) {
      db.exec("ROLLBACK");
      throw new Error(
        `Migration v${migration.version} failed: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    // Bump user_version ONLY after successful COMMIT
    db.exec(`PRAGMA user_version = ${migration.version}`);
  }
}
