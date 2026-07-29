-- 004: Drop notes from entries (notes belong on activities, not entries).
ALTER TABLE entries DROP COLUMN notes;