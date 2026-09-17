-- 006: Deletion tombstones (cross-device delete propagation). Every hard
-- DELETE of an activity, category, or entry upserts one row; recreating an id
-- clears it. No GC yet (rows are tiny; deleted_at enables future GC).
-- Idempotent (re-applied on every start): IF NOT EXISTS throughout.
CREATE TABLE IF NOT EXISTS tombstones (
    user_id UUID NOT NULL REFERENCES users(id),
    resource TEXT NOT NULL,
    record_id UUID NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, resource, record_id)
);

CREATE INDEX IF NOT EXISTS idx_tombstones_user_deleted
    ON tombstones(user_id, deleted_at);