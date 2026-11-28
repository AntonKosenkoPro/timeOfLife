-- 011: Day-planner relay state (add-day-planner). Per-task mutations
-- converge through immutable client operation ids with commit-ordered
-- per-account revisions; the feed pages by revision; receipts make a lost
-- response safely retryable; deletion markers are terminal and retained.
--
-- Postgres dialect; migrations.adaptToSQLite converts this for the SQLite
-- test store (TIMESTAMPTZ->TEXT, UUID->TEXT, NOW()->(datetime('now')),
-- DEFAULT false->0). ON DELETE CASCADE on the account FKs is a production
-- rollback safety net: a pre-planner image purging an account (DELETE users)
-- still cascades planner rows it never knew about. The new image deletes
-- explicitly in its purge transaction (no reliance on cascades or the
-- SQLite pragma, matching 003).

CREATE TABLE IF NOT EXISTS planner_tasks (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id UUID NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    position_key TEXT NOT NULL DEFAULT '500000',
    completed_on DATE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (user_id, id)
);

-- Revision-ordered page query: WHERE user_id = $1 AND revision > $2 AND
-- revision <= $3 ORDER BY revision ASC LIMIT $4.
CREATE INDEX IF NOT EXISTS idx_planner_tasks_user_revision
    ON planner_tasks(user_id, revision);

-- Per-account revision allocator. The accepting transaction locks this row
-- (SELECT ... FOR UPDATE on Postgres; the single-connection SQLite pool
-- serializes the same critical section) so concurrent operations on one
-- account commit with distinct, gap-free revisions in acceptance order.
CREATE TABLE IF NOT EXISTS planner_seq (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    last_revision BIGINT NOT NULL DEFAULT 0
);

-- Deduplication receipts: one row per accepted operation id. Retained with
-- no expiry in v1 so offline retries never reapply; the task row itself
-- carries the latest state, so no per-mutation snapshot is stored here.
CREATE TABLE IF NOT EXISTS planner_receipts (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    task_id UUID NOT NULL,
    revision BIGINT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, operation_id)
);

CREATE INDEX IF NOT EXISTS idx_planner_receipts_user_task
    ON planner_receipts(user_id, task_id);
