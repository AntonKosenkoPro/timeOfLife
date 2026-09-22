package db

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ---------- Postgres catalog helpers ----------

type pgxScanner interface {
	Scan(dest ...any) error
}

// pgScanEntry scans one entry row (without user_id) into an Entry. Postgres
// scans nullable columns directly into pointers (NULL → nil).
func pgScanEntry(sc pgxScanner, userID string) (Entry, error) {
	var (
		e         Entry
		startedAt time.Time
		endedAt   *time.Time
		dur       *int
		sourceRef *string
		notes     *string
	)
	if err := sc.Scan(&e.ID, &e.ActivityText, &notes, &startedAt, &endedAt, &dur, &sourceRef, &e.Source, &e.CreatedAt, &e.UpdatedAt); err != nil {
		return Entry{}, err
	}
	e.UserID = userID
	if notes != nil {
		e.Notes = *notes
	}
	e.StartedAt = startedAt
	e.EndedAt = endedAt
	e.DurationSeconds = dur
	e.SourceRef = sourceRef
	return e, nil
}

const pgEntryColumns = `id, activity_text, notes, started_at, ended_at, duration_seconds, source_ref, source, created_at, updated_at`

// pgListEntryTagsBatch returns category tags keyed by entry_id, position
// order preserved (the entry's own snapshot — no query-time resolution).
func (s *PostgresStore) pgListEntryTagsBatch(ctx context.Context, userID string, entryIDs []string) (map[string][]CategoryTag, error) {
	out := map[string][]CategoryTag{}
	if len(entryIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT ec.entry_id, c.id, c.name, c.icon
		FROM entry_categories ec
		JOIN categories c ON c.id = ec.category_id
		WHERE c.user_id = $1 AND ec.entry_id = ANY($2)
		ORDER BY ec.position, c.name
	`, userID, entryIDs)
	if err != nil {
		return nil, fmt.Errorf("list entry tags: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var entryID string
		var t CategoryTag
		if err := rows.Scan(&entryID, &t.ID, &t.Name, &t.Icon); err != nil {
			return nil, fmt.Errorf("list entry tags scan: %w", err)
		}
		out[entryID] = append(out[entryID], t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list entry tags rows: %w", err)
	}
	return out, nil
}

// pgAttachEntryTags populates Categories (the entry's own ordered tags) on
// each entry via one batched lookup keyed by entry_id.
func (s *PostgresStore) pgAttachEntryTags(ctx context.Context, userID string, items []Entry) error {
	entryIDs := make([]string, 0, len(items))
	for _, e := range items {
		entryIDs = append(entryIDs, e.ID)
	}
	tagsByEntry, err := s.pgListEntryTagsBatch(ctx, userID, entryIDs)
	if err != nil {
		return err
	}
	for i := range items {
		items[i].Categories = ensureCategories(tagsByEntry[items[i].ID])
	}
	return nil
}

// ---------- Categories ----------

// ListCategories returns the user's categories ordered by name.
func (s *PostgresStore) ListCategories(ctx context.Context, userID string) ([]Category, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = $1
		ORDER BY lower(name)
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list categories: %w", err)
	}
	defer rows.Close()
	var out []Category
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.Name, &c.Icon, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, fmt.Errorf("list categories scan: %w", err)
		}
		c.UserID = userID
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list categories rows: %w", err)
	}
	return out, nil
}

// GetCategory returns one category by id.
func (s *PostgresStore) GetCategory(ctx context.Context, userID, id string) (Category, error) {
	return s.pgGetCategoryRow(ctx, userID, id)
}

// CreateCategory inserts a new category, idempotent on id.
func (s *PostgresStore) CreateCategory(ctx context.Context, c Category) (Category, bool, error) {
	if existing, err := s.pgGetCategoryRow(ctx, c.UserID, c.ID); err == nil {
		return existing, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Category{}, false, err
	}
	if clash, err := s.pgGetCategoryRowByName(ctx, c.UserID, c.Name); err == nil {
		return clash, false, ErrCategoryExists
	} else if !errors.Is(err, ErrNotFound) {
		return Category{}, false, err
	}

	now := time.Now().UTC()
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO categories (id, user_id, name, icon, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $5)
	`, c.ID, c.UserID, c.Name, c.Icon, now); err != nil {
		if pgIsUniqueViolation(err) {
			if clash, err2 := s.pgGetCategoryRowByName(ctx, c.UserID, c.Name); err2 == nil {
				return clash, false, fmt.Errorf("create category: %w", ErrCategoryExists)
			}
			return Category{}, false, fmt.Errorf("create category: %w", ErrCategoryExists)
		}
		return Category{}, false, fmt.Errorf("create category: %w", err)
	}
	// A recreation clears its stale tombstone (harmless when none exists).
	if err := pgClearTombstone(ctx, s.pool, c.UserID, "category", c.ID); err != nil {
		return Category{}, false, err
	}
	created, err := s.pgGetCategoryRow(ctx, c.UserID, c.ID)
	if err != nil {
		return Category{}, false, err
	}
	return created, true, nil
}

func (s *PostgresStore) pgGetCategoryRow(ctx context.Context, userID, id string) (Category, error) {
	var c Category
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = $1 AND id = $2
	`, userID, id).Scan(&c.ID, &c.Name, &c.Icon, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Category{}, fmt.Errorf("get category: %w", ErrNotFound)
		}
		return Category{}, fmt.Errorf("get category: %w", err)
	}
	c.UserID = userID
	return c, nil
}

func (s *PostgresStore) pgGetCategoryRowByName(ctx context.Context, userID, name string) (Category, error) {
	var c Category
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = $1 AND lower(name) = lower($2)
	`, userID, name).Scan(&c.ID, &c.Name, &c.Icon, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Category{}, fmt.Errorf("get category by name: %w", ErrNotFound)
		}
		return Category{}, fmt.Errorf("get category by name: %w", err)
	}
	c.UserID = userID
	return c, nil
}

// UpdateCategory applies a partial LWW update on name/icon.
func (s *PostgresStore) UpdateCategory(ctx context.Context, userID, id string, p CategoryPatch) (Category, error) {
	sets := []string{}
	args := []any{}
	n := 1
	add := func(col string, val any) {
		sets = append(sets, fmt.Sprintf("%s = $%d", col, n))
		args = append(args, val)
		n++
	}
	if p.Name != nil {
		add("name", *p.Name)
	}
	if p.Icon != nil {
		add("icon", *p.Icon)
	}
	add("updated_at", p.UpdatedAt)
	args = append(args, id, userID, p.UpdatedAt)
	query := `UPDATE categories SET ` + strings.Join(sets, ", ") +
		fmt.Sprintf(" WHERE id = $%d AND user_id = $%d AND updated_at < $%d", n, n+1, n+2)
	res, err := s.pool.Exec(ctx, query, args...)
	if err != nil {
		if p.Name != nil && pgIsUniqueViolation(err) {
			return Category{}, fmt.Errorf("update category: %w", ErrCategoryExists)
		}
		return Category{}, fmt.Errorf("update category: %w", err)
	}
	if res.RowsAffected() == 0 {
		if _, err := s.pgGetCategoryRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Category{}, fmt.Errorf("update category: %w", ErrNotFound)
		} else if err != nil {
			return Category{}, err
		}
		current, err := s.pgGetCategoryRow(ctx, userID, id)
		if err != nil {
			return Category{}, err
		}
		return current, fmt.Errorf("update category: %w", ErrConflict)
	}
	return s.pgGetCategoryRow(ctx, userID, id)
}

// DeleteCategory hard-deletes a category and its entry join rows (entries are
// unaffected — their text, notes, and timings stay intact).
func (s *PostgresStore) DeleteCategory(ctx context.Context, userID, id string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("delete category begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `DELETE FROM entry_categories WHERE category_id = $1`, id); err != nil {
		return fmt.Errorf("delete category joins: %w", err)
	}
	res, err := tx.Exec(ctx, `DELETE FROM categories WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return fmt.Errorf("delete category: %w", err)
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("delete category: %w", ErrNotFound)
	}
	if err := pgUpsertTombstone(ctx, tx, userID, "category", id); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("delete category commit: %w", err)
	}
	return nil
}

// ---------- Entries ----------

// ListEntries returns one page of entries ordered by started_at DESC.
func (s *PostgresStore) ListEntries(ctx context.Context, userID string, f EntryFilter) ([]Entry, string, error) {
	conds := []string{"user_id = $1"}
	args := []any{userID}
	n := 2
	addc := func(cond string, val any) {
		conds = append(conds, fmt.Sprintf(cond, n))
		args = append(args, val)
		n++
	}
	if f.From != nil {
		addc("started_at >= $%d", *f.From)
	}
	if f.To != nil {
		addc("started_at <= $%d", *f.To)
	}
	if f.CategoryID != "" {
		addc("id IN (SELECT entry_id FROM entry_categories WHERE category_id = $%d)", f.CategoryID)
	}
	if f.ModifiedSince != nil {
		addc("updated_at > $%d", *f.ModifiedSince)
	}
	if cur, curID, ok := decodeCursor(f.Cursor); ok {
		conds = append(conds, fmt.Sprintf("(started_at < $%d OR (started_at = $%d AND id < $%d))", n, n, n+1))
		args = append(args, cur, curID)
		n += 2
	}
	limit := clampLimit(f.Limit)
	args = append(args, limit+1)
	query := fmt.Sprintf(`SELECT %s FROM entries WHERE %s ORDER BY started_at DESC, id DESC LIMIT $%d`,
		pgEntryColumns, strings.Join(conds, " AND "), n)
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, "", fmt.Errorf("list entries: %w", err)
	}
	defer rows.Close()
	items := make([]Entry, 0, limit)
	for rows.Next() {
		e, err := pgScanEntry(rows, userID)
		if err != nil {
			return nil, "", fmt.Errorf("list entries scan: %w", err)
		}
		items = append(items, e)
	}
	if err := rows.Err(); err != nil {
		return nil, "", fmt.Errorf("list entries rows: %w", err)
	}
	nextCursor := ""
	if len(items) > limit {
		last := items[limit-1]
		nextCursor = encodeCursor(last.StartedAt, last.ID)
		items = items[:limit]
	}
	if err := s.pgAttachEntryTags(ctx, userID, items); err != nil {
		return nil, "", err
	}
	return items, nextCursor, nil
}

// ListRecents implements the recents experience (design D5): entries grouped
// by exact activity_text, per group the newest started_at wins (id DESC as a
// stable tiebreak), ordered by that newest started_at DESC, LIMIT n. The
// winning entry carries the group's categories.
func (s *PostgresStore) ListRecents(ctx context.Context, userID string, limit int) ([]Entry, error) {
	if limit <= 0 {
		limit = 6
	}
	rows, err := s.pool.Query(ctx, `
		SELECT `+pgEntryColumns+`
		FROM entries e
		WHERE e.user_id = $1 AND e.activity_text != ''
		  AND e.id = (
			SELECT e2.id FROM entries e2
			WHERE e2.user_id = e.user_id AND e2.activity_text = e.activity_text
			ORDER BY e2.started_at DESC, e2.id DESC
			LIMIT 1
		  )
		ORDER BY e.started_at DESC, e.id DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("list recents: %w", err)
	}
	defer rows.Close()
	items := []Entry{}
	for rows.Next() {
		e, err := pgScanEntry(rows, userID)
		if err != nil {
			return nil, fmt.Errorf("list recents scan: %w", err)
		}
		items = append(items, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list recents rows: %w", err)
	}
	if err := s.pgAttachEntryTags(ctx, userID, items); err != nil {
		return nil, err
	}
	return items, nil
}

// GetEntry returns one entry by id with its own ordered categories.
func (s *PostgresStore) GetEntry(ctx context.Context, userID, id string) (Entry, error) {
	e, err := pgScanEntry(s.pool.QueryRow(ctx, `
		SELECT `+pgEntryColumns+`
		FROM entries
		WHERE user_id = $1 AND id = $2
	`, userID, id), userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Entry{}, fmt.Errorf("get entry: %w", ErrNotFound)
		}
		return Entry{}, fmt.Errorf("get entry: %w", err)
	}
	items := []Entry{e}
	if err := s.pgAttachEntryTags(ctx, userID, items); err != nil {
		return Entry{}, err
	}
	return items[0], nil
}

func (s *PostgresStore) pgGetEntryRow(ctx context.Context, userID, id string) (Entry, error) {
	e, err := pgScanEntry(s.pool.QueryRow(ctx, `
		SELECT `+pgEntryColumns+`
		FROM entries
		WHERE user_id = $1 AND id = $2
	`, userID, id), userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Entry{}, fmt.Errorf("get entry: %w", ErrNotFound)
		}
		return Entry{}, fmt.Errorf("get entry: %w", err)
	}
	return e, nil
}

// CreateEntry inserts a new entry, idempotent on id.
func (s *PostgresStore) CreateEntry(ctx context.Context, e Entry) (Entry, bool, error) {
	if existing, err := s.pgGetEntryRow(ctx, e.UserID, e.ID); err == nil {
		items := []Entry{existing}
		if err := s.pgAttachEntryTags(ctx, e.UserID, items); err != nil {
			return Entry{}, false, err
		}
		return items[0], false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Entry{}, false, err
	}

	// Trim is part of the identity rule (D1): the stored value is the trimmed
	// text, byte-exact in case (`Gym` ≠ `GYM`). Empty after trim → rejected.
	e.ActivityText = strings.TrimSpace(e.ActivityText)
	if e.ActivityText == "" {
		return Entry{}, false, fmt.Errorf("create entry: %w", ErrInvalidEntryText)
	}
	// Reject ended_at <= started_at (the handler validates the both-present
	// case; this also guards direct store calls and a stray zero-time ended_at).
	if e.EndedAt != nil && !e.EndedAt.After(e.StartedAt) {
		return Entry{}, false, fmt.Errorf("create entry: %w", ErrEndBeforeStart)
	}

	var dur *int
	if e.EndedAt != nil {
		d := int(e.EndedAt.Sub(e.StartedAt).Seconds())
		dur = &d
	}
	// Back-compat: entries created without provenance default to manual/null.
	source := e.Source
	if source == "" {
		source = "manual"
	}

	now := time.Now().UTC()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Entry{}, false, fmt.Errorf("create entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `
		INSERT INTO entries (id, user_id, activity_text, notes, started_at, ended_at, duration_seconds, source, source_ref, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)
	`, e.ID, e.UserID, e.ActivityText, e.Notes, e.StartedAt, e.EndedAt, dur, source, e.SourceRef, now); err != nil {
		// A duplicate import (same user_id, source, source_ref) surfaces as a
		// UNIQUE-constraint failure on the partial index; map it to a clear
		// error rather than a raw 500.
		if pgIsUniqueViolation(err) {
			return Entry{}, false, fmt.Errorf("create entry: %w", ErrDuplicateImport)
		}
		return Entry{}, false, fmt.Errorf("create entry: %w", err)
	}
	if err := s.pgStrictEntryCategoriesTx(ctx, tx, e.UserID, e.Categories); err != nil {
		return Entry{}, false, err
	}
	if err := s.pgReplaceEntryCategoriesTx(ctx, tx, e.UserID, e.ID, e.Categories); err != nil {
		return Entry{}, false, err
	}
	// A recreation clears its stale tombstone (harmless when none exists).
	if _, err := tx.Exec(ctx, `
		DELETE FROM tombstones WHERE user_id = $1 AND resource = 'entry' AND record_id = $2
	`, e.UserID, e.ID); err != nil {
		return Entry{}, false, fmt.Errorf("clear entry tombstone: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return Entry{}, false, fmt.Errorf("create entry commit: %w", err)
	}
	created, err := s.GetEntry(ctx, e.UserID, e.ID)
	if err != nil {
		return Entry{}, false, err
	}
	return created, true, nil
}

// UpdateEntry applies a partial LWW update and recomputes duration_seconds.
// CategoryIDs non-nil replaces the entry's ordered tags; unknown or non-owned
// ids are pruned with the remainder kept (never fails the cycle — D7).
func (s *PostgresStore) UpdateEntry(ctx context.Context, userID, id string, p EntryPatch) (Entry, error) {
	current, err := s.pgGetEntryRow(ctx, userID, id)
	if err != nil {
		return Entry{}, err
	}
	startedAt := current.StartedAt
	if p.StartedAt != nil {
		startedAt = *p.StartedAt
	}
	var endedAt *time.Time
	if p.EndedAt.Set {
		if p.EndedAt.Valid {
			endedAt = &p.EndedAt.Value
		} else {
			endedAt = nil
		}
	} else {
		endedAt = current.EndedAt
	}
	// Reject a partial patch that makes ended_at <= started_at once merged
	// with the current row, rather than persisting a negative duration.
	if (p.StartedAt != nil || p.EndedAt.Set) && endedAt != nil && !endedAt.After(startedAt) {
		return Entry{}, fmt.Errorf("update entry: %w", ErrEndBeforeStart)
	}
	var dur *int
	if endedAt != nil {
		d := int(endedAt.Sub(startedAt).Seconds())
		dur = &d
	}

	sets := []string{}
	args := []any{}
	n := 1
	add := func(col string, val any) {
		sets = append(sets, fmt.Sprintf("%s = $%d", col, n))
		args = append(args, val)
		n++
	}
	add("duration_seconds", dur)
	add("updated_at", p.UpdatedAt)
	if p.ActivityText != nil {
		text := strings.TrimSpace(*p.ActivityText)
		if text == "" {
			return Entry{}, fmt.Errorf("update entry: %w", ErrInvalidEntryText)
		}
		add("activity_text", text)
	}
	if p.Notes != nil {
		add("notes", *p.Notes)
	}
	if p.StartedAt != nil {
		add("started_at", *p.StartedAt)
	}
	if p.EndedAt.Set {
		add("ended_at", endedAt)
	}
	args = append(args, id, userID, p.UpdatedAt)
	query := `UPDATE entries SET ` + strings.Join(sets, ", ") +
		fmt.Sprintf(" WHERE id = $%d AND user_id = $%d AND updated_at < $%d", n, n+1, n+2)

	// The field update and the join replacement share one transaction: a
	// failed join write rolls back the field changes too (no partial entry
	// state ever survives).
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Entry{}, fmt.Errorf("update entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	res, err := tx.Exec(ctx, query, args...)
	if err != nil {
		return Entry{}, fmt.Errorf("update entry: %w", err)
	}
	if res.RowsAffected() == 0 {
		// The row may have been deleted between the fetch above and this UPDATE;
		// re-check existence so a concurrent delete returns ErrNotFound (404),
		// not a stale ErrConflict (409), mirroring UpdateEntry on SQLite and
		// UpdateCategory on both engines.
		if _, err := s.pgGetEntryRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Entry{}, fmt.Errorf("update entry: %w", ErrNotFound)
		} else if err != nil {
			return Entry{}, err
		}
		// Stale write: roll back first so the pooled connection is released
		// before re-reading the current version.
		if err := tx.Rollback(ctx); err != nil {
			return Entry{}, fmt.Errorf("update entry rollback: %w", err)
		}
		fresh, err := s.GetEntry(ctx, userID, id)
		if err != nil {
			return Entry{}, err
		}
		return fresh, fmt.Errorf("update entry: %w", ErrConflict)
	}

	if p.CategoryIDs != nil {
		if err := s.pgReplaceEntryCategoriesTx(ctx, tx, userID, id, *p.CategoryIDs); err != nil {
			return Entry{}, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return Entry{}, fmt.Errorf("update entry commit: %w", err)
	}
	return s.GetEntry(ctx, userID, id)
}

// pgReplaceEntryCategoriesTx replaces an entry's ordered join rows within the
// caller's transaction. Unknown or non-owned category ids are pruned (the
// remainder keeps its relative order); empty strings and duplicates are
// skipped. A merge never fails the sync cycle (D7).
func (s *PostgresStore) pgReplaceEntryCategoriesTx(ctx context.Context, tx pgx.Tx, userID, entryID string, orderedTags []CategoryTag) error {
	if _, err := tx.Exec(ctx, `DELETE FROM entry_categories WHERE entry_id = $1`, entryID); err != nil {
		return fmt.Errorf("replace entry categories delete: %w", err)
	}
	seen := map[string]bool{}
	position := 0
	for _, tag := range orderedTags {
		cid := tag.ID
		if cid == "" || seen[cid] {
			continue
		}
		seen[cid] = true
		// A malformed uuid would abort the transaction on a plain typed
		// lookup (22P02 poisons the tx); cast through text so an unknown
		// (missing, malformed, or foreign) id reads as no-rows and is pruned
		// — the merge keeps the remainder and never fails the cycle (D7).
		var exists int
		if err := tx.QueryRow(ctx, `SELECT 1 FROM categories WHERE id::text = $1 AND user_id::text = $2`, cid, userID).Scan(&exists); err != nil {
			continue // prune unknown category id, keep the remainder
		}
		if _, err := tx.Exec(ctx, `INSERT INTO entry_categories (entry_id, category_id, position) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`, entryID, cid, position); err != nil {
			return fmt.Errorf("replace entry categories insert: %w", err)
		}
		position++
	}
	return nil
}

// pgStrictEntryCategoriesTx validates every category id exists and belongs to
// the user — a create fails loudly with ErrInvalidCategoryID rather than
// pruning (it is a first-party write, not a merge, D7).
func (s *PostgresStore) pgStrictEntryCategoriesTx(ctx context.Context, tx pgx.Tx, userID string, orderedTags []CategoryTag) error {
	seen := map[string]bool{}
	for _, tag := range orderedTags {
		if tag.ID == "" || seen[tag.ID] {
			continue
		}
		seen[tag.ID] = true
		// Cast through text: a malformed uuid must surface as ErrNoRows
		// (→ ErrInvalidCategoryID, 422), not as a tx-poisoning 22P02.
		var exists int
		if err := tx.QueryRow(ctx, `SELECT 1 FROM categories WHERE id::text = $1 AND user_id::text = $2`, tag.ID, userID).Scan(&exists); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return fmt.Errorf("create entry: %w", ErrInvalidCategoryID)
			}
			return fmt.Errorf("create entry categories check: %w", err)
		}
	}
	return nil
}

// DeleteEntry hard-deletes an entry.
func (s *PostgresStore) DeleteEntry(ctx context.Context, userID, id string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("delete entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	res, err := tx.Exec(ctx, `DELETE FROM entries WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return fmt.Errorf("delete entry: %w", err)
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("delete entry: %w", ErrNotFound)
	}
	if err := pgUpsertTombstone(ctx, tx, userID, "entry", id); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("delete entry commit: %w", err)
	}
	return nil
}

// pgUpsertTombstone records (or refreshes) a deletion tombstone for one hard
// delete, inside the caller's transaction. Cascade-deleted children get no
// tombstones — one row per user intent.
func pgUpsertTombstone(ctx context.Context, tx pgx.Tx, userID, resource, recordID string) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO tombstones (user_id, resource, record_id, deleted_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id, resource, record_id)
		DO UPDATE SET deleted_at = excluded.deleted_at
	`, userID, resource, recordID, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("upsert tombstone: %w", err)
	}
	return nil
}

// pgClearTombstone removes a record's tombstone so a recreation never meets
// its own stale tombstone. Harmless when no tombstone exists.
func pgClearTombstone(ctx context.Context, pool *pgxpool.Pool, userID, resource, recordID string) error {
	if _, err := pool.Exec(ctx, `
		DELETE FROM tombstones WHERE user_id = $1 AND resource = $2 AND record_id = $3
	`, userID, resource, recordID); err != nil {
		return fmt.Errorf("clear tombstone: %w", err)
	}
	return nil
}

// ListDeletions returns the user's tombstones with deleted_at > since
// (nil/zero = all), ordered by deleted_at ASC.
func (s *PostgresStore) ListDeletions(ctx context.Context, userID string, since *time.Time) ([]Tombstone, error) {
	if since != nil && since.IsZero() {
		since = nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT resource, record_id, deleted_at
		FROM tombstones
		WHERE user_id = $1 AND ($2::timestamptz IS NULL OR deleted_at > $2)
		ORDER BY deleted_at ASC
	`, userID, since)
	if err != nil {
		return nil, fmt.Errorf("list deletions: %w", err)
	}
	defer rows.Close()
	var out []Tombstone
	for rows.Next() {
		var t Tombstone
		if err := rows.Scan(&t.Resource, &t.ID, &t.DeletedAt); err != nil {
			return nil, fmt.Errorf("list deletions scan: %w", err)
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list deletions rows: %w", err)
	}
	return out, nil
}

// pgIsUniqueViolation reports whether err is a Postgres unique-constraint failure.
func pgIsUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}
