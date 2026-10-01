-- 007: upgrade pre-squash deployments (strict no-op on fresh DBs).
--
-- The squash replaced the old 003 (activities layer) + 004 (icon/colors) +
-- 007 (activities removal) chain with a clean 003 carrying the final shape
-- directly. Databases provisioned by the old set still have the legacy
-- shape: activities/activity_categories tables, entries.activity_id,
-- categories.color without icon, and possibly nullable entries.notes.
-- This file upgrades those deployments in place.
--
-- Structure: everything except the tombstone cleanup lives in one DO block.
-- Plain statements inside it are all IF-guarded (valid on both shapes —
-- they skip on fresh DBs); statements referencing legacy-only objects run as
-- deferred dynamic SQL behind catalog checks (parsed only when executed, so
-- fresh apply never touches them). The SQLite shim strips DO blocks wholesale — test
-- databases are always fresh, so the upgrade path is dead code there and
-- PL/pgSQL would not parse. Only the tombstone DELETE runs on both engines
-- (the tombstones table exists in both shapes; fresh DBs delete zero rows).

DO $$
BEGIN
    -- categories.icon for legacy rows (fresh 003 already has it).
    ALTER TABLE categories ADD COLUMN IF NOT EXISTS icon TEXT NOT NULL DEFAULT 'tag';
    ALTER TABLE categories DROP COLUMN IF EXISTS color;

    -- entries new-shape columns for legacy rows (fresh 003 already has them).
    ALTER TABLE entries ADD COLUMN IF NOT EXISTS activity_text TEXT NOT NULL DEFAULT '';
    ALTER TABLE entries ADD COLUMN IF NOT EXISTS notes TEXT NOT NULL DEFAULT '';

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

    CREATE INDEX IF NOT EXISTS idx_entries_user_text_started
        ON entries(user_id, activity_text, started_at DESC);

    -- Backfill entry text/notes from each entry's activity (legacy only).
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'activities')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'entries' AND column_name = 'activity_id')
       AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'entries' AND column_name = 'notes') THEN
        EXECUTE $backfill$
            UPDATE entries
            SET activity_text = COALESCE((SELECT a.name FROM activities a WHERE a.id = entries.activity_id), ''),
                notes = COALESCE((SELECT a.notes FROM activities a WHERE a.id = entries.activity_id), '')
            WHERE activity_id IS NOT NULL
        $backfill$;
    END IF;

    -- Ordered category tags: copy each entry's activity's list (legacy only).
    -- Deployments predating the old 004 lack activity_categories.position.
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'activity_categories') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'activity_categories' AND column_name = 'position') THEN
            EXECUTE $copytags$
                INSERT INTO entry_categories (entry_id, category_id, position)
                SELECT e.id, ac.category_id, ac.position
                FROM entries e
                JOIN activities a ON a.id = e.activity_id
                JOIN activity_categories ac ON ac.activity_id = a.id
                WHERE NOT EXISTS (
                    SELECT 1 FROM entry_categories ec
                    WHERE ec.entry_id = e.id AND ec.category_id = ac.category_id
                )
            $copytags$;
        ELSE
            EXECUTE $copytags_nopos$
                INSERT INTO entry_categories (entry_id, category_id, position)
                SELECT e.id, ac.category_id, 0
                FROM entries e
                JOIN activities a ON a.id = e.activity_id
                JOIN activity_categories ac ON ac.activity_id = a.id
                WHERE NOT EXISTS (
                    SELECT 1 FROM entry_categories ec
                    WHERE ec.entry_id = e.id AND ec.category_id = ac.category_id
                )
            $copytags_nopos$;
        END IF;
    END IF;

    -- Legacy nullable entries.notes (pre-old-004 databases): normalize NULLs
    -- and enforce NOT NULL to match the fresh shape.
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'entries' AND column_name = 'notes' AND is_nullable = 'YES') THEN
        EXECUTE $fixnotes$
            UPDATE entries SET notes = '' WHERE notes IS NULL
        $fixnotes$;
        EXECUTE $fixnotes_nn$
            ALTER TABLE entries ALTER COLUMN notes SET NOT NULL
        $fixnotes_nn$;
    END IF;

    -- Drop the activities layer (IF-guarded: no-ops on fresh DBs). The
    -- entries.activity_id column goes first — Postgres refuses to drop a
    -- table a foreign key still depends on. Entries keep their backfilled
    -- text/categories/notes.
    DROP INDEX IF EXISTS idx_entries_user_activity;
    ALTER TABLE entries DROP COLUMN IF EXISTS activity_id;
    DROP TABLE IF EXISTS activity_categories;
    DROP TABLE IF EXISTS activities;
END $$;

-- Activity tombstones no longer exist (entries/categories only). Valid on
-- both shapes; fresh DBs delete zero rows.
DELETE FROM tombstones WHERE resource = 'activity';
