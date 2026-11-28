-- 012: Planner task categories (add-day-planner §14). Each task carries an
-- optional ordered set of category ids, stored as a JSON array TEXT column
-- (ordered, explicit; UUIDs never contain the delimiter). The set is edited
-- through the new `retag` field intent and used at Start; unknown ids are
-- kept on the relay and pruned at Stop (unlike entry `category_ids`, no
-- existence check — the set is loose by design).
--
-- ADD COLUMN with NOT NULL DEFAULT backfills existing rows with '[]', so
-- the additive deploy needs no data rewrite on either dialect
-- (migrations.adaptToSQLite converts this for the SQLite test store).

ALTER TABLE planner_tasks ADD COLUMN category_ids TEXT NOT NULL DEFAULT '[]';
