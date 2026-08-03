-- 004_categories_icon_drop_colors.sql
-- Pre-release: destructive schema change — no backward compat needed.
-- Activities lose color/icon; categories lose color, gain icon.
-- activity_categories gains position for ordered attachment.

ALTER TABLE activities DROP COLUMN color;
ALTER TABLE activities DROP COLUMN icon;
ALTER TABLE categories DROP COLUMN color;
ALTER TABLE categories ADD COLUMN icon TEXT NOT NULL DEFAULT 'tag';
ALTER TABLE activity_categories ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
