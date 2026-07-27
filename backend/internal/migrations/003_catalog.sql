-- Epic 1: Activity Catalog & Categories. Introduces activities, categories,
-- the many-to-many activity_categories tag join, entries (with a nullable
-- activity_id so an entry can be unlinked from its activity), and
-- entry_tag_snapshots (frozen tags captured at unlink time so an unlinked
-- entry's history still reads correctly). All ids are client-generated UUID v7.
--
-- Postgres dialect; migrations.adaptToSQLite converts this for the SQLite
-- test store (TIMESTAMPTZ->TEXT, UUID->TEXT, NOW()->(datetime('now')), IF NOT
-- EXISTS stripped). The lower(name) expression indexes survive adaptation
-- unchanged and work on both engines. ON DELETE CASCADE is honored natively
-- by Postgres; the SQLite test store performs explicit child-row deletes
-- inside the store methods (foreign_keys pragma is off there), so the
-- declarations are a production safety net rather than a test dependency.

CREATE TABLE IF NOT EXISTS activities (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT NOT NULL,
    notes TEXT,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_activities_user_name
    ON activities(user_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_activities_user_lastused
    ON activities(user_id, last_used_at DESC);

CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_user_name
    ON categories(user_id, lower(name));

CREATE TABLE IF NOT EXISTS activity_categories (
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (activity_id, category_id)
);

CREATE TABLE IF NOT EXISTS entries (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    activity_id UUID REFERENCES activities(id) ON DELETE CASCADE,
    activity_name_snapshot TEXT,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_entries_user_started
    ON entries(user_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_entries_user_activity
    ON entries(user_id, activity_id);

CREATE TABLE IF NOT EXISTS entry_tag_snapshots (
    entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    category_id UUID NOT NULL,
    category_name_snapshot TEXT NOT NULL,
    category_color_snapshot TEXT NOT NULL,
    PRIMARY KEY (entry_id, category_id)
);