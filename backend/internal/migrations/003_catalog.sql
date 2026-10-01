-- 003: Categories and self-contained entries. Each entry owns its
-- `activity_text` (trimmed, case-sensitive identity — `Gym` ≠ `GYM`), its
-- `notes`, and its ordered category tags via the `entry_categories`
-- (entry_id, category_id, position) join. All ids are client-generated
-- UUID v7.
--
-- Postgres dialect; migrations.adaptToSQLite converts this for the SQLite
-- test store (TIMESTAMPTZ->TEXT, UUID->TEXT, NOW()->(datetime('now')),
-- DEFAULT false/true->0/1, IF NOT EXISTS stripped on CREATE). ON DELETE
-- CASCADE is honored natively by Postgres; the SQLite test store performs
-- explicit child-row deletes inside the store methods (foreign_keys pragma
-- is off there), so the declarations are a production safety net rather
-- than a test dependency.

CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'tag',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_user_name
    ON categories(user_id, lower(name));

CREATE TABLE IF NOT EXISTS entries (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    activity_text TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entries_user_started
    ON entries(user_id, started_at DESC);

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

-- Recents query (D5): GROUP BY exact activity_text, per group the newest
-- started_at wins, ordered by that max DESC. This index keeps it cheap.
CREATE INDEX IF NOT EXISTS idx_entries_user_text_started
    ON entries(user_id, activity_text, started_at DESC);
