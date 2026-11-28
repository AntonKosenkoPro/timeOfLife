-- 013: Planner task notes (add-day-planner §15). Each task carries
-- optional free-text notes, stored as a TEXT column (untrimmed, like entry
-- `notes` — the relay trims only to gate the shared 2000-rune bound). The
-- notes are edited through the new `notes` field intent, copied into the
-- running draft at Start, and never feed History, Insights, or Recents.
--
-- ADD COLUMN with NOT NULL DEFAULT backfills existing rows with '', so the
-- additive deploy needs no data rewrite on either dialect
-- (migrations.adaptToSQLite converts this for the SQLite test store).

ALTER TABLE planner_tasks ADD COLUMN notes TEXT NOT NULL DEFAULT '';
