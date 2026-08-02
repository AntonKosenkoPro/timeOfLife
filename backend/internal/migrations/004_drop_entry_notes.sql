-- 004: Drop notes from entries (notes belong on activities, not entries).
-- IF EXISTS: migrations are re-applied on every server start (RunPostgres has
-- no tracking table), so each statement must be idempotent.
ALTER TABLE entries DROP COLUMN IF EXISTS notes;