-- 007: Remove the activities layer (remove-activities-layer D8 — one-shot
-- migration, pre-release, no backward compat). Entries become self-contained:
-- each entry owns its `activity_text` (trimmed, case-sensitive identity —
-- `Gym` ≠ `GYM`), its `notes`, and its ordered category tags via the new
-- `entry_categories(entry_id, category_id, position)` join. The `activities`
-- and `activity_categories` tables are dropped, together with every
-- entry→activity reference. Backfill takes each entry's activity's CURRENT
-- name, ordered category tags, and notes (retroactive inheritance ends with
-- this migration).
--
-- Idempotent (re-applied on every server start — RunPostgres has no tracking
-- table, and 003 recreates the activities layer empty): every ADD/DROP is
-- IF NOT EXISTS / IF EXISTS, and the re-added `activity_id` (nullable, no FK)
-- makes the backfill a no-op on re-application — the recreated `activities`
-- table is empty, so no row joins, then the column is dropped again.
ALTER TABLE entries ADD COLUMN IF NOT EXISTS activity_text TEXT NOT NULL DEFAULT '';
ALTER TABLE entries ADD COLUMN IF NOT EXISTS notes TEXT NOT NULL DEFAULT '';
ALTER TABLE entries ADD COLUMN IF NOT EXISTS activity_id UUID;

CREATE TABLE IF NOT EXISTS entry_categories (
    entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    PRIMARY KEY (entry_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_entry_categories_category
    ON entry_categories(category_id, entry_id);

CREATE INDEX IF NOT EXISTS idx_entry_categories_position
    ON entry_categories(entry_id, position);

-- Backfill: each entry takes its activity's current name and notes. Correlated
-- subqueries keep this portable and no-op once activity_id is NULL/absent.
UPDATE entries
SET activity_text = COALESCE((SELECT a.name FROM activities a WHERE a.id = entries.activity_id), ''),
    notes = COALESCE((SELECT a.notes FROM activities a WHERE a.id = entries.activity_id), '')
WHERE activity_id IS NOT NULL;

-- Ordered category tags: copy each entry's activity's ordered list.
INSERT INTO entry_categories (entry_id, category_id, position)
SELECT e.id, ac.category_id, ac.position
FROM entries e
JOIN activities a ON a.id = e.activity_id
JOIN activity_categories ac ON ac.activity_id = a.id
WHERE NOT EXISTS (
    SELECT 1 FROM entry_categories ec
    WHERE ec.entry_id = e.id AND ec.category_id = ac.category_id
);

-- Recents query (D5): GROUP BY exact activity_text, per group the newest
-- started_at wins, ordered by that max DESC. This index keeps it cheap.
CREATE INDEX IF NOT EXISTS idx_entries_user_text_started
    ON entries(user_id, activity_text, started_at DESC);

-- Drop the activities layer. The entries.activity_id column (and with it the
-- FK 003 created) goes FIRST — Postgres refuses to drop a table a foreign key
-- still depends on (SQLSTATE 2BP01), and SQLite cannot DROP COLUMN under an
-- index that references it. Entries keep their backfilled
-- text/categories/notes. The activity index on entries goes with the column;
-- (user_id, started_at DESC) and the recents index above cover entry reads.
DROP INDEX IF EXISTS idx_entries_user_activity;
ALTER TABLE entries DROP COLUMN IF EXISTS activity_id;
DROP TABLE IF EXISTS activity_categories;
DROP TABLE IF EXISTS activities;

-- Activity tombstones no longer exist (entries/categories only).
DELETE FROM tombstones WHERE resource = 'activity';