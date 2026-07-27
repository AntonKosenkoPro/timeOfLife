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

// nullStrArg turns an empty string into a NULL placeholder.
func nullStrArg(s string) any {
	if s == "" {
		return nil
	}
	return s
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
		e          Entry
		activityID sql.NullString
		startedAt  string
		endedAt    sql.NullString
		dur        sql.NullInt64
		notes      sql.NullString
		createdAt  string
		updatedAt  string
	)
	if err := sc.Scan(&e.ID, &activityID, &startedAt, &endedAt, &dur, &notes, &createdAt, &updatedAt); err != nil {
		return Entry{}, err
	}
	e.UserID = userID
	if activityID.Valid && activityID.String != "" {
		e.ActivityID = &activityID.String
	}
	e.StartedAt = parseTime(startedAt)
	e.EndedAt = nullTimePtr(endedAt)
	e.DurationSeconds = nullIntPtr(dur)
	e.Notes = notes.String
	e.CreatedAt = parseTime(createdAt)
	e.UpdatedAt = parseTime(updatedAt)
	return e, nil
}

const entryColumns = `id, activity_id, started_at, ended_at, duration_seconds, notes, created_at, updated_at`

// listActivityTagsBatch returns category tags keyed by activity_id for the
// given activities (entries reuse this by their activity_id).
func (s *SQLiteStore) listActivityTagsBatch(ctx context.Context, userID string, activityIDs []string) (map[string][]CategoryTag, error) {
	out := map[string][]CategoryTag{}
	if len(activityIDs) == 0 {
		return out, nil
	}
	placeholders := strings.Repeat("?,", len(activityIDs))
	placeholders = placeholders[:len(placeholders)-1]
	args := make([]any, 0, len(activityIDs)+1)
	args = append(args, userID)
	for _, id := range activityIDs {
		args = append(args, id)
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT ac.activity_id, c.id, c.name, c.color
		FROM activity_categories ac
		JOIN categories c ON c.id = ac.category_id
		WHERE c.user_id = ? AND ac.activity_id IN (`+placeholders+`)
		ORDER BY c.name
	`, args...)
	if err != nil {
		return nil, fmt.Errorf("list activity tags: %w", err)
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var activityID string
		var t CategoryTag
		if err := rows.Scan(&activityID, &t.ID, &t.Name, &t.Color); err != nil {
			return nil, fmt.Errorf("list activity tags scan: %w", err)
		}
		out[activityID] = append(out[activityID], t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list activity tags rows: %w", err)
	}
	return out, nil
}

// attachEntryActivity populates Categories (inferred from each entry's
// activity's tags) and ActivityName (the activity's current name) on each entry
// via two batched queries keyed by activity_id.
func (s *SQLiteStore) attachEntryActivity(ctx context.Context, userID string, items []Entry) error {
	activityIDs := make([]string, 0, len(items))
	for _, e := range items {
		if e.ActivityID != nil {
			activityIDs = append(activityIDs, *e.ActivityID)
		}
	}
	tagsByActivity, err := s.listActivityTagsBatch(ctx, userID, activityIDs)
	if err != nil {
		return err
	}
	namesByActivity, err := s.listActivityNamesBatch(ctx, activityIDs)
	if err != nil {
		return err
	}
	for i := range items {
		if items[i].ActivityID != nil {
			items[i].Categories = ensureCategories(tagsByActivity[*items[i].ActivityID])
			items[i].ActivityName = namesByActivity[*items[i].ActivityID]
		}
	}
	return nil
}

// listActivityNamesBatch returns activity names keyed by activity_id.
func (s *SQLiteStore) listActivityNamesBatch(ctx context.Context, activityIDs []string) (map[string]string, error) {
	out := map[string]string{}
	if len(activityIDs) == 0 {
		return out, nil
	}
	placeholders := strings.Repeat("?,", len(activityIDs))
	placeholders = placeholders[:len(placeholders)-1]
	args := make([]any, 0, len(activityIDs))
	for _, id := range activityIDs {
		args = append(args, id)
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name
		FROM activities
		WHERE id IN (`+placeholders+`)
	`, args...)
	if err != nil {
		return nil, fmt.Errorf("list activity names: %w", err)
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, fmt.Errorf("list activity names scan: %w", err)
		}
		out[id] = name
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list activity names rows: %w", err)
	}
	return out, nil
}

// ---------- Activities ----------

// ListActivities returns the user's activities ordered by last_used_at DESC.
func (s *SQLiteStore) ListActivities(ctx context.Context, userID, q string) ([]Activity, error) {
	var rows *sql.Rows
	var err error
	if q != "" {
		rows, err = s.db.QueryContext(ctx, `
			SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
			FROM activities
			WHERE user_id = ? AND lower(name) LIKE ?
			ORDER BY (last_used_at IS NULL), last_used_at DESC, updated_at DESC
		`, userID, "%"+strings.ToLower(q)+"%")
	} else {
		rows, err = s.db.QueryContext(ctx, `
			SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
			FROM activities
			WHERE user_id = ?
			ORDER BY (last_used_at IS NULL), last_used_at DESC, updated_at DESC
		`, userID)
	}
	if err != nil {
		return nil, fmt.Errorf("list activities: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var out []Activity
	ids := make([]string, 0)
	for rows.Next() {
		var a Activity
		var notes sql.NullString
		var lastUsed sql.NullString
		var createdAt, updatedAt string
		if err := rows.Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &createdAt, &updatedAt); err != nil {
			return nil, fmt.Errorf("list activities scan: %w", err)
		}
		a.UserID = userID
		a.Notes = notes.String
		a.LastUsedAt = nullTimePtr(lastUsed)
		a.CreatedAt = parseTime(createdAt)
		a.UpdatedAt = parseTime(updatedAt)
		out = append(out, a)
		ids = append(ids, a.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list activities rows: %w", err)
	}
	tags, err := s.listActivityTagsBatch(ctx, userID, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		out[i].Categories = ensureCategories(tags[out[i].ID])
	}
	return out, nil
}

// GetActivity returns one activity by id with its category tags.
func (s *SQLiteStore) GetActivity(ctx context.Context, userID, id string) (Activity, error) {
	a, err := s.getActivityRow(ctx, userID, id)
	if err != nil {
		return Activity{}, err
	}
	tags, err := s.listActivityTagsBatch(ctx, userID, []string{a.ID})
	if err != nil {
		return Activity{}, err
	}
	a.Categories = ensureCategories(tags[a.ID])
	return a, nil
}

// getActivityRow returns one activity row (no tags).
func (s *SQLiteStore) getActivityRow(ctx context.Context, userID, id string) (Activity, error) {
	var a Activity
	var notes sql.NullString
	var lastUsed sql.NullString
	var createdAt, updatedAt string
	err := s.db.QueryRowContext(ctx, `
		SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
		FROM activities
		WHERE user_id = ? AND id = ?
	`, userID, id).Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &createdAt, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return Activity{}, fmt.Errorf("get activity: %w", ErrNotFound)
		}
		return Activity{}, fmt.Errorf("get activity: %w", err)
	}
	a.UserID = userID
	a.Notes = notes.String
	a.LastUsedAt = nullTimePtr(lastUsed)
	a.CreatedAt = parseTime(createdAt)
	a.UpdatedAt = parseTime(updatedAt)
	return a, nil
}

// getActivityRowByName returns one activity row (no tags) by case-insensitive name.
func (s *SQLiteStore) getActivityRowByName(ctx context.Context, userID, name string) (Activity, error) {
	var a Activity
	var notes sql.NullString
	var lastUsed sql.NullString
	var createdAt, updatedAt string
	err := s.db.QueryRowContext(ctx, `
		SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
		FROM activities
		WHERE user_id = ? AND lower(name) = lower(?)
	`, userID, name).Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &createdAt, &updatedAt)
	if err != nil {
		if err == sql.ErrNoRows {
			return Activity{}, fmt.Errorf("get activity by name: %w", ErrNotFound)
		}
		return Activity{}, fmt.Errorf("get activity by name: %w", err)
	}
	a.UserID = userID
	a.Notes = notes.String
	a.LastUsedAt = nullTimePtr(lastUsed)
	a.CreatedAt = parseTime(createdAt)
	a.UpdatedAt = parseTime(updatedAt)
	return a, nil
}

// CreateActivity inserts a new activity, idempotent on id.
func (s *SQLiteStore) CreateActivity(ctx context.Context, a Activity, categoryIDs []string) (Activity, bool, error) {
	// Idempotent replay on id.
	if existing, err := s.getActivityRow(ctx, a.UserID, a.ID); err == nil {
		tags, err := s.listActivityTagsBatch(ctx, a.UserID, []string{existing.ID})
		if err != nil {
			return Activity{}, false, err
		}
		existing.Categories = ensureCategories(tags[existing.ID])
		return existing, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Activity{}, false, err
	}
	// Case-insensitive name collision.
	if clash, err := s.getActivityRowByName(ctx, a.UserID, a.Name); err == nil {
		tags, err := s.listActivityTagsBatch(ctx, a.UserID, []string{clash.ID})
		if err != nil {
			return Activity{}, false, err
		}
		clash.Categories = ensureCategories(tags[clash.ID])
		return clash, false, ErrActivityExists
	} else if !errors.Is(err, ErrNotFound) {
		return Activity{}, false, err
	}

	now := time.Now().UTC()
	if _, err := s.db.ExecContext(ctx, `
		INSERT INTO activities (id, user_id, name, color, icon, notes, last_used_at, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, a.ID, a.UserID, a.Name, a.Color, a.Icon, nullStrArg(a.Notes), fmtTimeArg(a.LastUsedAt), fmtTime(now), fmtTime(now)); err != nil {
		// A concurrent create that raced past the name pre-check surfaces as a
		// UNIQUE-constraint failure on the INSERT; map it to ErrActivityExists
		// (409) like the Postgres path, not a raw 500.
		if isUniqueViolation(err) {
			if clash, err2 := s.getActivityRowByName(ctx, a.UserID, a.Name); err2 == nil {
				return clash, false, fmt.Errorf("create activity: %w", ErrActivityExists)
			}
			return Activity{}, false, fmt.Errorf("create activity: %w", ErrActivityExists)
		}
		return Activity{}, false, fmt.Errorf("create activity: %w", err)
	}
	if err := s.replaceActivityCategories(ctx, a.UserID, a.ID, categoryIDs); err != nil {
		return Activity{}, false, err
	}
	created, err := s.GetActivity(ctx, a.UserID, a.ID)
	if err != nil {
		return Activity{}, false, err
	}
	return created, true, nil
}

// UpdateActivity applies a partial LWW update and optional tag replacement.
func (s *SQLiteStore) UpdateActivity(ctx context.Context, userID, id string, p ActivityPatch) (Activity, error) {
	sets := []string{}
	args := []any{}
	if p.Name != nil {
		sets = append(sets, "name = ?")
		args = append(args, *p.Name)
	}
	if p.Color != nil {
		sets = append(sets, "color = ?")
		args = append(args, *p.Color)
	}
	if p.Icon != nil {
		sets = append(sets, "icon = ?")
		args = append(args, *p.Icon)
	}
	if p.Notes != nil {
		sets = append(sets, "notes = ?")
		args = append(args, nullStrArg(*p.Notes))
	}
	sets = append(sets, "updated_at = ?")
	args = append(args, fmtTime(p.UpdatedAt))

	args = append(args, id, userID, fmtTime(p.UpdatedAt))
	query := `
		UPDATE activities SET ` + strings.Join(sets, ", ") + `
		WHERE id = ? AND user_id = ? AND updated_at < ?
	`
	res, err := s.db.ExecContext(ctx, query, args...)
	if err != nil {
		// Unique (user_id, lower(name)) collision → ErrActivityExists.
		if p.Name != nil && isUniqueViolation(err) {
			if clash, err2 := s.getActivityRowByName(ctx, userID, *p.Name); err2 == nil {
				return clash, fmt.Errorf("update activity: %w", ErrActivityExists)
			}
			return Activity{}, fmt.Errorf("update activity: %w", ErrActivityExists)
		}
		return Activity{}, fmt.Errorf("update activity: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return Activity{}, fmt.Errorf("update activity rows: %w", err)
	}
	if affected == 0 {
		// Not found or stale; distinguish.
		if _, err := s.getActivityRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Activity{}, fmt.Errorf("update activity: %w", ErrNotFound)
		} else if err != nil {
			return Activity{}, err
		}
		current, err := s.GetActivity(ctx, userID, id)
		if err != nil {
			return Activity{}, err
		}
		return current, fmt.Errorf("update activity: %w", ErrConflict)
	}

	if p.CategoryIDs != nil {
		if err := s.replaceActivityCategories(ctx, userID, id, *p.CategoryIDs); err != nil {
			return Activity{}, err
		}
	}
	return s.GetActivity(ctx, userID, id)
}

// replaceActivityCategories validates ownership, then atomically replaces an
// activity's join rows.
func (s *SQLiteStore) replaceActivityCategories(ctx context.Context, userID, activityID string, categoryIDs []string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("replace activity categories begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `DELETE FROM activity_categories WHERE activity_id = ?`, activityID); err != nil {
		return fmt.Errorf("replace activity categories delete: %w", err)
	}
	seen := map[string]bool{}
	for _, cid := range categoryIDs {
		if cid == "" || seen[cid] {
			continue
		}
		seen[cid] = true
		var exists int
		if err := tx.QueryRowContext(ctx, `SELECT 1 FROM categories WHERE id = ? AND user_id = ?`, cid, userID).Scan(&exists); err != nil {
			if err == sql.ErrNoRows {
				return fmt.Errorf("replace activity categories: %w", ErrInvalidCategoryID)
			}
			return fmt.Errorf("replace activity categories check: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO activity_categories (activity_id, category_id) VALUES (?, ?)`, activityID, cid); err != nil {
			return fmt.Errorf("replace activity categories insert: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("replace activity categories commit: %w", err)
	}
	return nil
}

// DeleteActivity hard-deletes an activity and its child rows.
func (s *SQLiteStore) DeleteActivity(ctx context.Context, userID, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("delete activity begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `DELETE FROM entries WHERE activity_id = ? AND user_id = ?`, id, userID); err != nil {
		return fmt.Errorf("delete activity entries: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM activity_categories WHERE activity_id = ?`, id); err != nil {
		return fmt.Errorf("delete activity tags: %w", err)
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM activities WHERE id = ? AND user_id = ?`, id, userID)
	if err != nil {
		return fmt.Errorf("delete activity: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete activity rows: %w", err)
	}
	if affected == 0 {
		return fmt.Errorf("delete activity: %w", ErrNotFound)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("delete activity commit: %w", err)
	}
	return nil
}

// ---------- Categories ----------

// ListCategories returns the user's categories ordered by name.
func (s *SQLiteStore) ListCategories(ctx context.Context, userID string) ([]Category, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, color, created_at, updated_at
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
		if err := rows.Scan(&c.ID, &c.Name, &c.Color, &createdAt, &updatedAt); err != nil {
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
		INSERT INTO categories (id, user_id, name, color, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
	`, c.ID, c.UserID, c.Name, c.Color, fmtTime(now), fmtTime(now)); err != nil {
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
		SELECT id, name, color, created_at, updated_at
		FROM categories
		WHERE user_id = ? AND id = ?
	`, userID, id).Scan(&c.ID, &c.Name, &c.Color, &createdAt, &updatedAt)
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
		SELECT id, name, color, created_at, updated_at
		FROM categories
		WHERE user_id = ? AND lower(name) = lower(?)
	`, userID, name).Scan(&c.ID, &c.Name, &c.Color, &createdAt, &updatedAt)
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

// UpdateCategory applies a partial LWW update on name/color.
func (s *SQLiteStore) UpdateCategory(ctx context.Context, userID, id string, c CategoryPatch) (Category, error) {
	sets := []string{}
	args := []any{}
	if c.Name != nil {
		sets = append(sets, "name = ?")
		args = append(args, *c.Name)
	}
	if c.Color != nil {
		sets = append(sets, "color = ?")
		args = append(args, *c.Color)
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

// DeleteCategory hard-deletes a category and its join rows (entries unaffected).
func (s *SQLiteStore) DeleteCategory(ctx context.Context, userID, id string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("delete category begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `DELETE FROM activity_categories WHERE category_id = ?`, id); err != nil {
		return fmt.Errorf("delete category tags: %w", err)
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
	if f.ActivityID != "" {
		conds = append(conds, "activity_id = ?")
		args = append(args, f.ActivityID)
	}
	if f.CategoryID != "" {
		conds = append(conds, "activity_id IN (SELECT activity_id FROM activity_categories WHERE category_id = ?)")
		args = append(args, f.CategoryID)
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
	if err := s.attachEntryActivity(ctx, userID, items); err != nil {
		return nil, "", err
	}
	return items, nextCursor, nil
}

// GetEntry returns one entry by id with its categories.
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
	if err := s.attachEntryActivity(ctx, userID, items); err != nil {
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
		if err := s.attachEntryActivity(ctx, e.UserID, items); err != nil {
			return Entry{}, false, err
		}
		return items[0], false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Entry{}, false, err
	}

	// An entry must reference one of the user's activities. The handler
	// enforces a non-nil activity_id; this also guards direct store calls.
	if e.ActivityID == nil {
		return Entry{}, false, fmt.Errorf("create entry: %w", ErrActivityNotFound)
	}
	if _, err := s.getActivityRow(ctx, e.UserID, *e.ActivityID); err != nil {
		if errors.Is(err, ErrNotFound) {
			return Entry{}, false, fmt.Errorf("create entry: %w", ErrActivityNotFound)
		}
		return Entry{}, false, err
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

	now := time.Now().UTC()
	if _, err := s.db.ExecContext(ctx, `
		INSERT INTO entries (id, user_id, activity_id, started_at, ended_at, duration_seconds, notes, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, e.ID, e.UserID, strPtrArg(e.ActivityID), fmtTime(e.StartedAt), fmtTimeArg(e.EndedAt), nullIntArg(dur), nullStrArg(e.Notes), fmtTime(now), fmtTime(now)); err != nil {
		return Entry{}, false, fmt.Errorf("create entry: %w", err)
	}
	// Bump the activity's last_used_at to the entry's started_at (recency for
	// suggestions, F5). Only advance it forward so a historical entry does not
	// regress recency. Skipped on idempotent replay (which returns above).
	if _, err := s.db.ExecContext(ctx, `
		UPDATE activities SET last_used_at = ?
		WHERE id = ? AND user_id = ? AND (last_used_at IS NULL OR ? > last_used_at)
	`, fmtTime(e.StartedAt), *e.ActivityID, e.UserID, fmtTime(e.StartedAt)); err != nil {
		return Entry{}, false, fmt.Errorf("bump activity last_used_at: %w", err)
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
	if p.StartedAt != nil {
		sets = append([]string{"started_at = ?"}, sets...)
		args = append([]any{fmtTime(*p.StartedAt)}, args...)
	}
	if p.EndedAt.Set {
		sets = append([]string{"ended_at = ?"}, sets...)
		args = append([]any{fmtTimeArg(endedAt)}, args...)
	}
	if p.Notes != nil {
		sets = append([]string{"notes = ?"}, sets...)
		args = append([]any{nullStrArg(*p.Notes)}, args...)
	}
	args = append(args, id, userID, fmtTime(p.UpdatedAt))
	res, err := s.db.ExecContext(ctx, `
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
		// The row may have been deleted between the fetch above and this UPDATE;
		// re-check existence so a concurrent delete returns ErrNotFound (404),
		// not a stale ErrConflict (409), mirroring UpdateActivity/UpdateCategory.
		if _, err := s.getEntryRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
			return Entry{}, fmt.Errorf("update entry: %w", ErrNotFound)
		} else if err != nil {
			return Entry{}, err
		}
		return current, fmt.Errorf("update entry: %w", ErrConflict)
	}
	return s.GetEntry(ctx, userID, id)
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
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("delete entry commit: %w", err)
	}
	return nil
}

// isUniqueViolation reports whether err is a SQLite UNIQUE constraint failure.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "UNIQUE constraint failed")
}
