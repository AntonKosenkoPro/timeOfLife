package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

// ---------- SQLite catalog helpers ----------

type rowScanner interface {
	Scan(dest ...any) error
}

// parseTime parses a SQLite TEXT timestamp into time.Time (zero on failure).
func parseTime(s string) time.Time {
	t, _ := time.Parse("2006-01-02 15:04:05", s)
	return t
}

// nullTimePtr converts a nullable SQLite TEXT timestamp into a *time.Time.
func nullTimePtr(ns sql.NullString) *time.Time {
	if !ns.Valid || ns.String == "" {
		return nil
	}
	t, _ := time.Parse("2006-01-02 15:04:05", ns.String)
	return &t
}

// nullIntPtr converts a nullable SQLite int into a *int.
func nullIntPtr(n sql.NullInt64) *int {
	if !n.Valid {
		return nil
	}
	v := int(n.Int64)
	return &v
}

// fmtTime formats a time.Time for SQLite storage.
func fmtTime(t time.Time) string {
	return t.UTC().Format("2006-01-02 15:04:05")
}

// fmtTimeArg formats a nullable time for a SQLite placeholder (nil → NULL).
func fmtTimeArg(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.UTC().Format("2006-01-02 15:04:05")
}

// nullIntArg turns a nil *int into a NULL placeholder.
func nullIntArg(n *int) any {
	if n == nil {
		return nil
	}
	return *n
}

// scanEntry scans one entry row (without user_id) into an Entry.
func scanEntry(sc rowScanner, userID string) (Entry, error) {
	var (
		e         Entry
		startedAt string
		endedAt   sql.NullString
		dur       sql.NullInt64
		sourceRef sql.NullString
		notes     sql.NullString
		createdAt string
		updatedAt string
	)
	if err := sc.Scan(&e.ID, &e.ActivityText, &notes, &startedAt, &endedAt, &dur, &sourceRef, &e.Source, &createdAt, &updatedAt); err != nil {
		return Entry{}, err
	}
	e.UserID = userID
	e.Notes = notes.String
	e.StartedAt = parseTime(startedAt)
	e.EndedAt = nullTimePtr(endedAt)
	e.DurationSeconds = nullIntPtr(dur)
	if sourceRef.Valid {
		e.SourceRef = &sourceRef.String
	}
	e.CreatedAt = parseTime(createdAt)
	e.UpdatedAt = parseTime(updatedAt)
	return e, nil
}

const entryColumns = `id, activity_text, notes, started_at, ended_at, duration_seconds, source_ref, source, created_at, updated_at`

// listEntryTagsBatch returns category tags keyed by entry_id, position order
// preserved (the entry's own snapshot — no query-time resolution).
func (s *SQLiteStore) listEntryTagsBatch(ctx context.Context, userID string, entryIDs []string) (map[string][]CategoryTag, error) {
	out := map[string][]CategoryTag{}
	if len(entryIDs) == 0 {
		return out, nil
	}
	placeholders := strings.Repeat("?,", len(entryIDs))
	placeholders = placeholders[:len(placeholders)-1]
	args := make([]any, 0, len(entryIDs)+1)
	args = append(args, userID)
	for _, id := range entryIDs {
		args = append(args, id)
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT ec.entry_id, c.id, c.name, c.icon
		FROM entry_categories ec
		JOIN categories c ON c.id = ec.category_id
		WHERE c.user_id = ? AND ec.entry_id IN (`+placeholders+`)
		ORDER BY ec.position, c.name
	`, args...)
	if err != nil {
		return nil, fmt.Errorf("list entry tags: %w", err)
	}
	defer func() { _ = rows.Close() }()
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

// attachEntryTags populates Categories (the entry's own ordered tags) on each
// entry via one batched query keyed by entry_id.
func (s *SQLiteStore) attachEntryTags(ctx context.Context, userID string, items []Entry) error {
	entryIDs := make([]string, 0, len(items))
	for _, e := range items {
		entryIDs = append(entryIDs, e.ID)
	}
	tagsByEntry, err := s.listEntryTagsBatch(ctx, userID, entryIDs)
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
func (s *SQLiteStore) ListCategories(ctx context.Context, userID string) ([]Category, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = ?
		ORDER BY lower(name)
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list categories: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []Category
	for rows.Next() {
		var c Category
		var createdAt, updatedAt string
		if err := rows.Scan(&c.ID, &c.Name, &c.Icon, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("list categories scan: %w", err)
		}
		c.UserID = userID
		c.CreatedAt = parseTime(createdAt)
		c.UpdatedAt = parseTime(updatedAt)
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list categories rows: %w", err)
	}
	return out, nil
}

// GetCategory returns one category by id.
func (s *SQLiteStore) GetCategory(ctx context.Context, userID, id string) (Category, error) {
	return s.getCategoryRow(ctx, userID, id)
}

// CreateCategory inserts a new category, idempotent on id.
func (s *SQLiteStore) CreateCategory(ctx context.Context, c Category) (Category, bool, error) {
	// Idempotent replay on id.
	if existing, err := s.getCategoryRow(ctx, c.UserID, c.ID); err == nil {
		return existing, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Category{}, false, err
	}
	// Case-insensitive name collision.
	if clash, err := s.getCategoryRowByName(ctx, c.UserID, c.Name); err == nil {
		return clash, false, ErrCategoryExists
	} else if !errors.Is(err, ErrNotFound) {
		return Category{}, false, err
	}

	now := time.Now().UTC()
	if _, err := s.db.ExecContext(ctx, `
		INSERT INTO categories (id, user_id, name, icon, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
	`, c.ID, c.UserID, c.Name, c.Icon, fmtTime(now), fmtTime(now)); err != nil {
		// A concurrent create that raced past the name pre-check surfaces as a
		// UNIQUE-constraint failure on the INSERT; map it to ErrCategoryExists
		// (409) like the Postgres path, not a raw 500.
		if isUniqueViolation(err) {
			if clash, err2 := s.getCategoryRowByName(ctx, c.UserID, c.Name); err2 == nil {
				return clash, false, fmt.Errorf("create category: %w", ErrCategoryExists)
			}
			return Category{}, false, fmt.Errorf("create category: %w", ErrCategoryExists)
		}
		return Category{}, false, fmt.Errorf("create category: %w", err)
	}
	// A recreation clears its stale tombstone (harmless when none exists).
	if err := clearTombstone(ctx, s.db, c.UserID, "category", c.ID); err != nil {
		return Category{}, false, err
	}
	created, err := s.getCategoryRow(ctx, c.UserID, c.ID)
	if err != nil {
		return Category{}, false, err
	}
	return created, true, nil
}

func (s *SQLiteStore) getCategoryRow(ctx context.Context, userID, id string) (Category, error) {
	var c Category
	var createdAt, updatedAt string
	err := s.db.QueryRowContext(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = ? AND id = ?
	`, userID, id).Scan(&c.ID, &c.Name, &c.Icon, &createdAt, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return Category{}, fmt.Errorf("get category: %w", ErrNotFound)
		}
		return Category{}, fmt.Errorf("get category: %w", err)
	}
	c.UserID = userID
	c.CreatedAt = parseTime(createdAt)
	c.UpdatedAt = parseTime(updatedAt)
	return c, nil
}

func (s *SQLiteStore) getCategoryRowByName(ctx context.Context, userID, name string) (Category, error) {
	var c Category
	var createdAt, updatedAt string
	err := s.db.QueryRowContext(ctx, `
		SELECT id, name, icon, created_at, updated_at
		FROM categories
		WHERE user_id = ? AND lower(name) = lower(?)
	`, userID, name).Scan(&c.ID, &c.Name, &c.Icon, &createdAt, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return Category{}, fmt.Errorf("get category by name: %w", ErrNotFound)
		}
		return Category{}, fmt.Errorf("get category by name: %w", err)
	}
	c.UserID = userID
	c.CreatedAt = parseTime(createdAt)
	c.UpdatedAt = parseTime(updatedAt)
	return c, nil
}

// UpdateCategory applies a partial LWW update on name/icon.
func (s *SQLiteStore) UpdateCategory(ctx context.Context, userID, id string, c CategoryPatch) (Category, error) {
	sets := []string{}
	args := []any{}
	if c.Name != nil {
		sets = append(sets, "name = ?")
		args = append(args, *c.Name)
	}
	if c.Icon != nil {
		sets = append(sets, "icon = ?")
		args = append(args, *c.Icon)
	}
	sets = append(sets, "updated_at = ?")
	args = append(args, fmtTime(c.UpdatedAt))
	args = append(args, id, userID, fmtTime(c.UpdatedAt))
	res, err := s.db.ExecContext(ctx, `
		UPDATE categories SET `+strings.Join(sets, ", ")+`
		WHERE id = ? AND user_id = ? AND updated_at < ?
	`, args...)
	if err != nil {
		if c.Name != nil && isUniqueViolation(err) {
			return Category{}, fmt.Errorf("update category: %w", ErrCategoryExists)
		}
		return Category{}, fmt.Errorf("update category: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return Category{}, fmt.Errorf("update category rows: %w", err)
	}
	if affected == 0 {
		if _, err := s.getCategoryRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Category{}, fmt.Errorf("update category: %w", ErrNotFound)
		} else if err != nil {
			return Category{}, err
		}
		current, err := s.getCategoryRow(ctx, userID, id)
		if err != nil {
			return Category{}, err
		}
		return current, fmt.Errorf("update category: %w", ErrConflict)
	}
	return s.getCategoryRow(ctx, userID, id)
}

// DeleteCategory hard-deletes a category and its entry join rows (entries are
// unaffected — their text, notes, and timings stay intact).
func (s *SQLiteStore) DeleteCategory(ctx context.Context, userID, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("delete category begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `DELETE FROM entry_categories WHERE category_id = ?`, id); err != nil {
		return fmt.Errorf("delete category joins: %w", err)
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM categories WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return fmt.Errorf("delete category: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete category rows: %w", err)
	}
	if affected == 0 {
		return fmt.Errorf("delete category: %w", ErrNotFound)
	}
	if err := upsertTombstone(ctx, tx, userID, "category", id); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("delete category commit: %w", err)
	}
	return nil
}

// ---------- Entries ----------

// ListEntries returns one page of entries ordered by started_at DESC.
func (s *SQLiteStore) ListEntries(ctx context.Context, userID string, f EntryFilter) ([]Entry, string, error) {
	conds := []string{"user_id = ?"}
	args := []any{userID}
	if f.From != nil {
		conds = append(conds, "started_at >= ?")
		args = append(args, fmtTime(*f.From))
	}
	if f.To != nil {
		conds = append(conds, "started_at <= ?")
		args = append(args, fmtTime(*f.To))
	}
	if f.CategoryID != "" {
		conds = append(conds, "id IN (SELECT entry_id FROM entry_categories WHERE category_id = ?)")
		args = append(args, f.CategoryID)
	}
	if f.ModifiedSince != nil {
		conds = append(conds, "updated_at > ?")
		args = append(args, fmtTime(*f.ModifiedSince))
	}
	if cur, curID, ok := decodeCursor(f.Cursor); ok {
		conds = append(conds, "(started_at < ? OR (started_at = ? AND id < ?))")
		args = append(args, fmtTime(cur), fmtTime(cur), curID)
	}
	limit := clampLimit(f.Limit)
	args = append(args, limit+1)
	query := `
		SELECT ` + entryColumns + `
		FROM entries
		WHERE ` + strings.Join(conds, " AND ") + `
		ORDER BY started_at DESC, id DESC
		LIMIT ?
	`
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, "", fmt.Errorf("list entries: %w", err)
	}
	defer func() { _ = rows.Close() }()
	items := make([]Entry, 0, limit)
	for rows.Next() {
		e, err := scanEntry(rows, userID)
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
	if err := s.attachEntryTags(ctx, userID, items); err != nil {
		return nil, "", err
	}
	return items, nextCursor, nil
}

// ListRecents implements the recents experience (design D5): entries grouped
// by exact activity_text, per group the newest started_at wins (id DESC as a
// stable tiebreak), ordered by that newest started_at DESC, LIMIT n. The
// winning entry carries the group's categories.
func (s *SQLiteStore) ListRecents(ctx context.Context, userID string, limit int) ([]Entry, error) {
	if limit <= 0 {
		limit = 6
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT `+entryColumns+`
		FROM entries e
		WHERE e.user_id = ? AND e.activity_text != ''
		  AND e.id = (
			SELECT e2.id FROM entries e2
			WHERE e2.user_id = e.user_id AND e2.activity_text = e.activity_text
			ORDER BY e2.started_at DESC, e2.id DESC
			LIMIT 1
		  )
		ORDER BY e.started_at DESC, e.id DESC
		LIMIT ?
	`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("list recents: %w", err)
	}
	defer func() { _ = rows.Close() }()
	items := []Entry{}
	for rows.Next() {
		e, err := scanEntry(rows, userID)
		if err != nil {
			return nil, fmt.Errorf("list recents scan: %w", err)
		}
		items = append(items, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list recents rows: %w", err)
	}
	if err := s.attachEntryTags(ctx, userID, items); err != nil {
		return nil, err
	}
	return items, nil
}

// GetEntry returns one entry by id with its own ordered categories.
func (s *SQLiteStore) GetEntry(ctx context.Context, userID, id string) (Entry, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT `+entryColumns+`
		FROM entries
		WHERE user_id = ? AND id = ?
	`, userID, id)
	e, err := scanEntry(row, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return Entry{}, fmt.Errorf("get entry: %w", ErrNotFound)
		}
		return Entry{}, fmt.Errorf("get entry: %w", err)
	}
	items := []Entry{e}
	if err := s.attachEntryTags(ctx, userID, items); err != nil {
		return Entry{}, err
	}
	return items[0], nil
}

// getEntryRow returns one entry row without tags.
func (s *SQLiteStore) getEntryRow(ctx context.Context, userID, id string) (Entry, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT `+entryColumns+`
		FROM entries
		WHERE user_id = ? AND id = ?
	`, userID, id)
	e, err := scanEntry(row, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return Entry{}, fmt.Errorf("get entry: %w", ErrNotFound)
		}
		return Entry{}, fmt.Errorf("get entry: %w", err)
	}
	return e, nil
}

// CreateEntry inserts a new entry, idempotent on id.
func (s *SQLiteStore) CreateEntry(ctx context.Context, e Entry) (Entry, bool, error) {
	// Idempotent replay on id.
	if existing, err := s.getEntryRow(ctx, e.UserID, e.ID); err == nil {
		items := []Entry{existing}
		if err := s.attachEntryTags(ctx, e.UserID, items); err != nil {
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
	// Compute duration when ended.
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
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Entry{}, false, fmt.Errorf("create entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO entries (id, user_id, activity_text, notes, started_at, ended_at, duration_seconds, source, source_ref, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, e.ID, e.UserID, e.ActivityText, e.Notes, fmtTime(e.StartedAt), fmtTimeArg(e.EndedAt), nullIntArg(dur), source, strPtrArg(e.SourceRef), fmtTime(now), fmtTime(now)); err != nil {
		// A duplicate import (same user_id, source, source_ref) surfaces as a
		// UNIQUE-constraint failure on the partial index; map it to a clear
		// error rather than a raw 500.
		if isUniqueViolation(err) {
			return Entry{}, false, fmt.Errorf("create entry: %w", ErrDuplicateImport)
		}
		return Entry{}, false, fmt.Errorf("create entry: %w", err)
	}
	if err := s.strictEntryCategoriesTx(ctx, tx, e.UserID, e.Categories); err != nil {
		return Entry{}, false, err
	}
	if err := s.replaceEntryCategoriesTx(ctx, tx, e.UserID, e.ID, e.Categories); err != nil {
		return Entry{}, false, err
	}
	// A recreation clears its stale tombstone (harmless when none exists).
	if _, err := tx.ExecContext(ctx, `
		DELETE FROM tombstones WHERE user_id = ? AND resource = 'entry' AND record_id = ?
	`, e.UserID, e.ID); err != nil {
		return Entry{}, false, fmt.Errorf("clear entry tombstone: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Entry{}, false, fmt.Errorf("create entry commit: %w", err)
	}
	created, err := s.GetEntry(ctx, e.UserID, e.ID)
	if err != nil {
		return Entry{}, false, err
	}
	return created, true, nil
}

// strPtrArg dereferences a *string for a placeholder (nil → NULL).
func strPtrArg(s *string) any {
	if s == nil {
		return nil
	}
	return *s
}

// UpdateEntry applies a partial LWW update and recomputes duration_seconds.
// CategoryIDs non-nil replaces the entry's ordered tags; unknown or non-owned
// ids are pruned with the remainder kept (never fails the cycle — D7).
func (s *SQLiteStore) UpdateEntry(ctx context.Context, userID, id string, p EntryPatch) (Entry, error) {
	// Fetch current to recompute duration when only one of started_at/ended_at changed.
	current, err := s.getEntryRow(ctx, userID, id)
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

	sets := []string{"duration_seconds = ?", "updated_at = ?"}
	args := []any{nullIntArg(dur), fmtTime(p.UpdatedAt)}
	if p.ActivityText != nil {
		text := strings.TrimSpace(*p.ActivityText)
		if text == "" {
			return Entry{}, fmt.Errorf("update entry: %w", ErrInvalidEntryText)
		}
		sets = append([]string{"activity_text = ?"}, sets...)
		args = append([]any{text}, args...)
	}
	if p.Notes != nil {
		sets = append([]string{"notes = ?"}, sets...)
		args = append([]any{*p.Notes}, args...)
	}
	if p.StartedAt != nil {
		sets = append([]string{"started_at = ?"}, sets...)
		args = append([]any{fmtTime(*p.StartedAt)}, args...)
	}
	if p.EndedAt.Set {
		sets = append([]string{"ended_at = ?"}, sets...)
		args = append([]any{fmtTimeArg(endedAt)}, args...)
	}
	args = append(args, id, userID, fmtTime(p.UpdatedAt))

	// The field update and the join replacement share one transaction: a
	// failed join write rolls back the field changes too (no partial entry
	// state ever survives).
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Entry{}, fmt.Errorf("update entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.ExecContext(ctx, `
		UPDATE entries SET `+strings.Join(sets, ", ")+`
		WHERE id = ? AND user_id = ? AND updated_at < ?
	`, args...)
	if err != nil {
		return Entry{}, fmt.Errorf("update entry: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return Entry{}, fmt.Errorf("update entry rows: %w", err)
	}
	if affected == 0 {
		// Not found, or the row was deleted between the fetch above and this
		// UPDATE — distinguish so a concurrent delete returns ErrNotFound.
		if _, err := s.getEntryRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Entry{}, fmt.Errorf("update entry: %w", ErrNotFound)
		} else if err != nil {
			return Entry{}, err
		}
		// Stale write: roll back first so the single pool connection is
		// released before re-reading the current version.
		if err := tx.Rollback(); err != nil {
			return Entry{}, fmt.Errorf("update entry rollback: %w", err)
		}
		fresh, err := s.GetEntry(ctx, userID, id)
		if err != nil {
			return Entry{}, err
		}
		return fresh, fmt.Errorf("update entry: %w", ErrConflict)
	}

	if p.CategoryIDs != nil {
		if err := s.replaceEntryCategoriesTx(ctx, tx, userID, id, *p.CategoryIDs); err != nil {
			return Entry{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return Entry{}, fmt.Errorf("update entry commit: %w", err)
	}
	return s.GetEntry(ctx, userID, id)
}

// replaceEntryCategoriesTx replaces an entry's ordered join rows within the
// caller's transaction. Unknown or non-owned category ids are pruned (the
// remainder keeps its relative order); empty strings and duplicates are
// skipped. A merge never fails the sync cycle (D7).
func (s *SQLiteStore) replaceEntryCategoriesTx(ctx context.Context, tx *sql.Tx, userID, entryID string, orderedTags []CategoryTag) error {
	if _, err := tx.ExecContext(ctx, `DELETE FROM entry_categories WHERE entry_id = ?`, entryID); err != nil {
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
		var exists int
		if err := tx.QueryRowContext(ctx, `SELECT 1 FROM categories WHERE id = ? AND user_id = ?`, cid, userID).Scan(&exists); err != nil {
			if err == sql.ErrNoRows {
				continue // prune unknown category id, keep the remainder
			}
			return fmt.Errorf("replace entry categories check: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO entry_categories (entry_id, category_id, position) VALUES (?, ?, ?)`, entryID, cid, position); err != nil {
			return fmt.Errorf("replace entry categories insert: %w", err)
		}
		position++
	}
	return nil
}

// strictEntryCategoriesTx validates every category id exists and belongs to
// the user (a create is a first-party write, not a merge — it fails loudly
// with ErrInvalidCategoryID rather than pruning, D7).
func (s *SQLiteStore) strictEntryCategoriesTx(ctx context.Context, tx *sql.Tx, userID string, orderedTags []CategoryTag) error {
	seen := map[string]bool{}
	for _, tag := range orderedTags {
		if tag.ID == "" || seen[tag.ID] {
			continue
		}
		seen[tag.ID] = true
		var exists int
		if err := tx.QueryRowContext(ctx, `SELECT 1 FROM categories WHERE id = ? AND user_id = ?`, tag.ID, userID).Scan(&exists); err != nil {
			if err == sql.ErrNoRows {
				return fmt.Errorf("create entry: %w", ErrInvalidCategoryID)
			}
			return fmt.Errorf("create entry categories check: %w", err)
		}
	}
	return nil
}

// DeleteEntry hard-deletes an entry.
func (s *SQLiteStore) DeleteEntry(ctx context.Context, userID, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("delete entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	res, err := tx.ExecContext(ctx, `DELETE FROM entries WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return fmt.Errorf("delete entry: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete entry rows: %w", err)
	}
	if affected == 0 {
		return fmt.Errorf("delete entry: %w", ErrNotFound)
	}
	if err := upsertTombstone(ctx, tx, userID, "entry", id); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("delete entry commit: %w", err)
	}
	return nil
}

// upsertTombstone records (or refreshes) a deletion tombstone for one hard
// delete, inside the caller's transaction. Cascade-deleted children get no
// tombstones — one row per user intent.
func upsertTombstone(ctx context.Context, tx *sql.Tx, userID, resource, recordID string) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO tombstones (user_id, resource, record_id, deleted_at)
		VALUES (?, ?, ?, ?)
		ON CONFLICT (user_id, resource, record_id)
		DO UPDATE SET deleted_at = excluded.deleted_at
	`, userID, resource, recordID, fmtTime(time.Now().UTC()))
	if err != nil {
		return fmt.Errorf("upsert tombstone: %w", err)
	}
	return nil
}

// clearTombstone removes a record's tombstone so a recreation never meets its
// own stale tombstone. Harmless when no tombstone exists.
func clearTombstone(ctx context.Context, db *sql.DB, userID, resource, recordID string) error {
	if _, err := db.ExecContext(ctx, `
		DELETE FROM tombstones WHERE user_id = ? AND resource = ? AND record_id = ?
	`, userID, resource, recordID); err != nil {
		return fmt.Errorf("clear tombstone: %w", err)
	}
	return nil
}

// ListDeletions returns the user's tombstones with deleted_at > since
// (nil/zero = all), ordered by deleted_at ASC.
func (s *SQLiteStore) ListDeletions(ctx context.Context, userID string, since *time.Time) ([]Tombstone, error) {
	if since != nil && since.IsZero() {
		since = nil
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT resource, record_id, deleted_at
		FROM tombstones
		WHERE user_id = ? AND (? IS NULL OR deleted_at > ?)
		ORDER BY deleted_at ASC
	`, userID, fmtTimeArg(since), fmtTimeArg(since))
	if err != nil {
		return nil, fmt.Errorf("list deletions: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []Tombstone
	for rows.Next() {
		var t Tombstone
		var deletedAt string
		if err := rows.Scan(&t.Resource, &t.ID, &deletedAt); err != nil {
			return nil, fmt.Errorf("list deletions scan: %w", err)
		}
		t.DeletedAt = parseTime(deletedAt)
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list deletions rows: %w", err)
	}
	return out, nil
}

// isUniqueViolation reports whether err is a SQLite UNIQUE constraint failure.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "UNIQUE constraint failed")
}
