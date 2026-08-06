-- 005: Entry provenance (local-first sync). Adds `source` (where the entry
-- came from: manual, widget, siri, control, screentime, garmin, ...) and
-- `source_ref` (the external identifier for that source, e.g. a Screen Time
-- callback uuid or Garmin activity id). A partial unique index on
-- (user_id, source, source_ref) for rows with a non-null source_ref prevents
-- duplicate imports (a source re-sending the same record).
--
-- IF NOT EXISTS: migrations are re-applied on every server start (RunPostgres
-- has no tracking table), so each statement must be idempotent. The SQLite
-- adapter strips IF NOT EXISTS; the fresh in-memory test DB needs no guard.
ALTER TABLE entries ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE entries ADD COLUMN IF NOT EXISTS source_ref TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_user_source_ref
    ON entries(user_id, source, source_ref)
    WHERE source_ref IS NOT NULL;
