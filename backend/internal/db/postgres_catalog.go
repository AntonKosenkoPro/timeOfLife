package db

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ---------- Postgres catalog helpers ----------

type pgxScanner interface {
	Scan(dest ...any) error
}

// pgStrPtr returns a *string for a string value, or nil for "" (so the column
// is stored as NULL, mirroring the SQLite nullStrArg convention).
func pgStrPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// pgScanEntry scans one entry row (without user_id) into an Entry. Postgres
// scans nullable columns directly into pointers (NULL → nil).
func pgScanEntry(sc pgxScanner, userID string) (Entry, error) {
	var (
		e          Entry
		activityID *string
		nameSnap   *string
		endedAt    *time.Time
		dur        *int
		notes      *string
	)
	if err := sc.Scan(&e.ID, &activityID, &nameSnap, &e.StartedAt, &endedAt, &dur, &notes, &e.CreatedAt, &e.UpdatedAt); err != nil {
		return Entry{}, err
	}
	e.UserID = userID
	e.ActivityID = activityID
	if nameSnap != nil {
		e.ActivityNameSnapshot = *nameSnap
	}
	e.EndedAt = endedAt
	e.DurationSeconds = dur
	if notes != nil {
		e.Notes = *notes
	}
	e.Linked = e.ActivityID != nil
	return e, nil
}

const pgEntryColumns = `id, activity_id, activity_name_snapshot, started_at, ended_at, duration_seconds, notes, created_at, updated_at`

// pgListActivityTagsBatch returns category tags keyed by activity_id.
func (s *PostgresStore) pgListActivityTagsBatch(ctx context.Context, userID string, activityIDs []string) (map[string][]CategoryTag, error) {
	out := map[string][]CategoryTag{}
	if len(activityIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT ac.activity_id, c.id, c.name, c.color
		FROM activity_categories ac
		JOIN categories c ON c.id = ac.category_id
		WHERE c.user_id = $1 AND ac.activity_id = ANY($2)
		ORDER BY c.name
	`, userID, activityIDs)
	if err != nil {
		return nil, fmt.Errorf("list activity tags: %w", err)
	}
	defer rows.Close()
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

// pgListEntrySnapshotsBatch returns frozen tag snapshots keyed by entry_id.
func (s *PostgresStore) pgListEntrySnapshotsBatch(ctx context.Context, entryIDs []string) (map[string][]CategoryTag, error) {
	out := map[string][]CategoryTag{}
	if len(entryIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT entry_id, category_id, category_name_snapshot, category_color_snapshot
		FROM entry_tag_snapshots
		WHERE entry_id = ANY($1)
		ORDER BY category_name_snapshot
	`, entryIDs)
	if err != nil {
		return nil, fmt.Errorf("list entry snapshots: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var entryID string
		var t CategoryTag
		if err := rows.Scan(&entryID, &t.ID, &t.Name, &t.Color); err != nil {
			return nil, fmt.Errorf("list entry snapshots scan: %w", err)
		}
		out[entryID] = append(out[entryID], t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list entry snapshots rows: %w", err)
	}
	return out, nil
}

// pgAttachEntryTags populates Categories on each entry (inferred while linked,
// snapshot after unlink).
func (s *PostgresStore) pgAttachEntryTags(ctx context.Context, userID string, items []Entry) error {
	activityIDs := make([]string, 0, len(items))
	unlinkedIDs := make([]string, 0, len(items))
	for _, e := range items {
		if e.ActivityID != nil {
			activityIDs = append(activityIDs, *e.ActivityID)
		} else {
			unlinkedIDs = append(unlinkedIDs, e.ID)
		}
	}
	tagsByActivity, err := s.pgListActivityTagsBatch(ctx, userID, activityIDs)
	if err != nil {
		return err
	}
	snapshots, err := s.pgListEntrySnapshotsBatch(ctx, unlinkedIDs)
	if err != nil {
		return err
	}
	for i := range items {
		if items[i].ActivityID != nil {
			items[i].Categories = ensureCategories(tagsByActivity[*items[i].ActivityID])
		} else {
			items[i].Categories = ensureCategories(snapshots[items[i].ID])
		}
	}
	return nil
}

// ---------- Activities ----------

// ListActivities returns the user's activities ordered by last_used_at DESC.
func (s *PostgresStore) ListActivities(ctx context.Context, userID, q string) ([]Activity, error) {
	var rows pgx.Rows
	var err error
	if q != "" {
		rows, err = s.pool.Query(ctx, `
			SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
			FROM activities
			WHERE user_id = $1 AND lower(name) LIKE $2
			ORDER BY (last_used_at IS NULL), last_used_at DESC, updated_at DESC
		`, userID, "%"+strings.ToLower(q)+"%")
	} else {
		rows, err = s.pool.Query(ctx, `
			SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
			FROM activities
			WHERE user_id = $1
			ORDER BY (last_used_at IS NULL), last_used_at DESC, updated_at DESC
		`, userID)
	}
	if err != nil {
		return nil, fmt.Errorf("list activities: %w", err)
	}
	defer rows.Close()
	var out []Activity
	ids := make([]string, 0)
	for rows.Next() {
		var a Activity
		var notes *string
		var lastUsed *time.Time
		if err := rows.Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, fmt.Errorf("list activities scan: %w", err)
		}
		a.UserID = userID
		if notes != nil {
			a.Notes = *notes
		}
		a.LastUsedAt = lastUsed
		out = append(out, a)
		ids = append(ids, a.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list activities rows: %w", err)
	}
	tags, err := s.pgListActivityTagsBatch(ctx, userID, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		out[i].Categories = ensureCategories(tags[out[i].ID])
	}
	return out, nil
}

// GetActivity returns one activity by id with its category tags.
func (s *PostgresStore) GetActivity(ctx context.Context, userID, id string) (Activity, error) {
	a, err := s.pgGetActivityRow(ctx, userID, id)
	if err != nil {
		return Activity{}, err
	}
	tags, err := s.pgListActivityTagsBatch(ctx, userID, []string{a.ID})
	if err != nil {
		return Activity{}, err
	}
	a.Categories = ensureCategories(tags[a.ID])
	return a, nil
}

func (s *PostgresStore) pgGetActivityRow(ctx context.Context, userID, id string) (Activity, error) {
	var a Activity
	var notes *string
	var lastUsed *time.Time
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
		FROM activities
		WHERE user_id = $1 AND id = $2
	`, userID, id).Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Activity{}, fmt.Errorf("get activity: %w", ErrNotFound)
		}
		return Activity{}, fmt.Errorf("get activity: %w", err)
	}
	a.UserID = userID
	if notes != nil {
		a.Notes = *notes
	}
	a.LastUsedAt = lastUsed
	return a, nil
}

func (s *PostgresStore) pgGetActivityRowByName(ctx context.Context, userID, name string) (Activity, error) {
	var a Activity
	var notes *string
	var lastUsed *time.Time
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, color, icon, notes, last_used_at, created_at, updated_at
		FROM activities
		WHERE user_id = $1 AND lower(name) = lower($2)
	`, userID, name).Scan(&a.ID, &a.Name, &a.Color, &a.Icon, &notes, &lastUsed, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Activity{}, fmt.Errorf("get activity by name: %w", ErrNotFound)
		}
		return Activity{}, fmt.Errorf("get activity by name: %w", err)
	}
	a.UserID = userID
	if notes != nil {
		a.Notes = *notes
	}
	a.LastUsedAt = lastUsed
	return a, nil
}

// CreateActivity inserts a new activity, idempotent on id.
func (s *PostgresStore) CreateActivity(ctx context.Context, a Activity, categoryIDs []string) (Activity, bool, error) {
	if existing, err := s.pgGetActivityRow(ctx, a.UserID, a.ID); err == nil {
		tags, err := s.pgListActivityTagsBatch(ctx, a.UserID, []string{existing.ID})
		if err != nil {
			return Activity{}, false, err
		}
		existing.Categories = ensureCategories(tags[existing.ID])
		return existing, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return Activity{}, false, err
	}
	if clash, err := s.pgGetActivityRowByName(ctx, a.UserID, a.Name); err == nil {
		tags, err := s.pgListActivityTagsBatch(ctx, a.UserID, []string{clash.ID})
		if err != nil {
			return Activity{}, false, err
		}
		clash.Categories = ensureCategories(tags[clash.ID])
		return clash, false, ErrActivityExists
	} else if !errors.Is(err, ErrNotFound) {
		return Activity{}, false, err
	}

	now := time.Now().UTC()
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO activities (id, user_id, name, color, icon, notes, last_used_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
	`, a.ID, a.UserID, a.Name, a.Color, a.Icon, pgStrPtr(a.Notes), a.LastUsedAt, now); err != nil {
		if pgIsUniqueViolation(err) {
			if clash, err2 := s.pgGetActivityRowByName(ctx, a.UserID, a.Name); err2 == nil {
				return clash, false, fmt.Errorf("create activity: %w", ErrActivityExists)
			}
			return Activity{}, false, fmt.Errorf("create activity: %w", ErrActivityExists)
		}
		return Activity{}, false, fmt.Errorf("create activity: %w", err)
	}
	if err := s.pgReplaceActivityCategories(ctx, a.UserID, a.ID, categoryIDs); err != nil {
		return Activity{}, false, err
	}
	created, err := s.GetActivity(ctx, a.UserID, a.ID)
	if err != nil {
		return Activity{}, false, err
	}
	return created, true, nil
}

// UpdateActivity applies a partial LWW update and optional tag replacement.
func (s *PostgresStore) UpdateActivity(ctx context.Context, userID, id string, p ActivityPatch) (Activity, error) {
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
	if p.Color != nil {
		add("color", *p.Color)
	}
	if p.Icon != nil {
		add("icon", *p.Icon)
	}
	if p.Notes != nil {
		add("notes", pgStrPtr(*p.Notes))
	}
	add("updated_at", p.UpdatedAt)
	args = append(args, id, userID, p.UpdatedAt)
	query := `UPDATE activities SET ` + strings.Join(sets, ", ") +
		fmt.Sprintf(" WHERE id = $%d AND user_id = $%d AND updated_at < $%d", n, n+1, n+2)
	res, err := s.pool.Exec(ctx, query, args...)
	if err != nil {
		if p.Name != nil && pgIsUniqueViolation(err) {
			return Activity{}, fmt.Errorf("update activity: %w", ErrActivityExists)
		}
		return Activity{}, fmt.Errorf("update activity: %w", err)
	}
	if res.RowsAffected() == 0 {
		if _, err := s.pgGetActivityRow(ctx, userID, id); errors.Is(err, ErrNotFound) {
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
		if err := s.pgReplaceActivityCategories(ctx, userID, id, *p.CategoryIDs); err != nil {
			return Activity{}, err
		}
	}
	return s.GetActivity(ctx, userID, id)
}

func (s *PostgresStore) pgReplaceActivityCategories(ctx context.Context, userID, activityID string, categoryIDs []string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("replace activity categories begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `DELETE FROM activity_categories WHERE activity_id = $1`, activityID); err != nil {
		return fmt.Errorf("replace activity categories delete: %w", err)
	}
	seen := map[string]bool{}
	for _, cid := range categoryIDs {
		if cid == "" || seen[cid] {
			continue
		}
		seen[cid] = true
		var exists int
		if err := tx.QueryRow(ctx, `SELECT 1 FROM categories WHERE id = $1 AND user_id = $2`, cid, userID).Scan(&exists); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return fmt.Errorf("replace activity categories: %w", ErrInvalidCategoryID)
			}
			return fmt.Errorf("replace activity categories check: %w", err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO activity_categories (activity_id, category_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, activityID, cid); err != nil {
			return fmt.Errorf("replace activity categories insert: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("replace activity categories commit: %w", err)
	}
	return nil
}

// DeleteActivity hard-deletes an activity and its child rows.
func (s *PostgresStore) DeleteActivity(ctx context.Context, userID, id string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("delete activity begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `
		DELETE FROM entry_tag_snapshots WHERE entry_id IN (
			SELECT id FROM entries WHERE activity_id = $1 AND user_id = $2
		)
	`, id, userID); err != nil {
		return fmt.Errorf("delete activity snapshots: %w", err)
	}
	if _, err := tx.Exec(ctx, `DELETE FROM entries WHERE activity_id = $1 AND user_id = $2`, id, userID); err != nil {
		return fmt.Errorf("delete activity entries: %w", err)
	}
	if _, err := tx.Exec(ctx, `DELETE FROM activity_categories WHERE activity_id = $1`, id); err != nil {
		return fmt.Errorf("delete activity tags: %w", err)
	}
	res, err := tx.Exec(ctx, `DELETE FROM activities WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return fmt.Errorf("delete activity: %w", err)
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("delete activity: %w", ErrNotFound)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("delete activity commit: %w", err)
	}
	return nil
}

// ---------- Categories ----------

// ListCategories returns the user's categories ordered by name.
func (s *PostgresStore) ListCategories(ctx context.Context, userID string) ([]Category, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, name, color, created_at, updated_at
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
		if err := rows.Scan(&c.ID, &c.Name, &c.Color, &c.CreatedAt, &c.UpdatedAt); err != nil {
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
		INSERT INTO categories (id, user_id, name, color, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $5)
	`, c.ID, c.UserID, c.Name, c.Color, now); err != nil {
		if pgIsUniqueViolation(err) {
			return Category{}, false, fmt.Errorf("create category: %w", ErrCategoryExists)
		}
		return Category{}, false, fmt.Errorf("create category: %w", err)
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
		SELECT id, name, color, created_at, updated_at
		FROM categories
		WHERE user_id = $1 AND id = $2
	`, userID, id).Scan(&c.ID, &c.Name, &c.Color, &c.CreatedAt, &c.UpdatedAt)
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
		SELECT id, name, color, created_at, updated_at
		FROM categories
		WHERE user_id = $1 AND lower(name) = lower($2)
	`, userID, name).Scan(&c.ID, &c.Name, &c.Color, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Category{}, fmt.Errorf("get category by name: %w", ErrNotFound)
		}
		return Category{}, fmt.Errorf("get category by name: %w", err)
	}
	c.UserID = userID
	return c, nil
}

// UpdateCategory applies a partial LWW update on name/color.
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
	if p.Color != nil {
		add("color", *p.Color)
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

// DeleteCategory hard-deletes a category and its join rows (entries unaffected).
func (s *PostgresStore) DeleteCategory(ctx context.Context, userID, id string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("delete category begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `DELETE FROM activity_categories WHERE category_id = $1`, id); err != nil {
		return fmt.Errorf("delete category tags: %w", err)
	}
	res, err := tx.Exec(ctx, `DELETE FROM categories WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return fmt.Errorf("delete category: %w", err)
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("delete category: %w", ErrNotFound)
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
		addc("started_at < $%d", *f.To)
	}
	if f.ActivityID != "" {
		addc("activity_id = $%d", f.ActivityID)
	}
	if f.CategoryID != "" {
		addc("activity_id IN (SELECT activity_id FROM activity_categories WHERE category_id = $%d)", f.CategoryID)
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

// GetEntry returns one entry by id with its categories.
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

	nameSnap := e.ActivityNameSnapshot
	if e.ActivityID != nil {
		a, err := s.pgGetActivityRow(ctx, e.UserID, *e.ActivityID)
		if err != nil {
			if errors.Is(err, ErrNotFound) {
				return Entry{}, false, fmt.Errorf("create entry: %w", ErrActivityNotFound)
			}
			return Entry{}, false, err
		}
		nameSnap = a.Name
	}

	var dur *int
	if e.EndedAt != nil {
		d := int(e.EndedAt.Sub(e.StartedAt).Seconds())
		dur = &d
	}

	now := time.Now().UTC()
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO entries (id, user_id, activity_id, activity_name_snapshot, started_at, ended_at, duration_seconds, notes, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
	`, e.ID, e.UserID, e.ActivityID, pgStrPtr(nameSnap), e.StartedAt, e.EndedAt, dur, pgStrPtr(e.Notes), now); err != nil {
		return Entry{}, false, fmt.Errorf("create entry: %w", err)
	}
	created, err := s.GetEntry(ctx, e.UserID, e.ID)
	if err != nil {
		return Entry{}, false, err
	}
	return created, true, nil
}

// UpdateEntry applies a partial LWW update and recomputes duration_seconds.
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
	var dur *int
	if endedAt != nil {
		d := int(endedAt.Sub(startedAt).Seconds())
		dur = &d
	}

	sets := []string{"duration_seconds = $1", "updated_at = $2"}
	args := []any{dur, p.UpdatedAt}
	n := 3
	if p.StartedAt != nil {
		sets = append([]string{fmt.Sprintf("started_at = $%d", n)}, sets...)
		args = append([]any{*p.StartedAt}, args...)
		n++
	}
	if p.EndedAt.Set {
		sets = append([]string{fmt.Sprintf("ended_at = $%d", n)}, sets...)
		args = append([]any{endedAt}, args...)
		n++
	}
	args = append(args, id, userID, p.UpdatedAt)
	query := `UPDATE entries SET ` + strings.Join(sets, ", ") +
		fmt.Sprintf(" WHERE id = $%d AND user_id = $%d AND updated_at < $%d", n, n+1, n+2)
	res, err := s.pool.Exec(ctx, query, args...)
	if err != nil {
		return Entry{}, fmt.Errorf("update entry: %w", err)
	}
	if res.RowsAffected() == 0 {
		return current, fmt.Errorf("update entry: %w", ErrConflict)
	}
	return s.GetEntry(ctx, userID, id)
}

// DeleteEntry hard-deletes an entry.
func (s *PostgresStore) DeleteEntry(ctx context.Context, userID, id string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("delete entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `DELETE FROM entry_tag_snapshots WHERE entry_id = $1`, id); err != nil {
		return fmt.Errorf("delete entry snapshots: %w", err)
	}
	res, err := tx.Exec(ctx, `DELETE FROM entries WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return fmt.Errorf("delete entry: %w", err)
	}
	if res.RowsAffected() == 0 {
		return fmt.Errorf("delete entry: %w", ErrNotFound)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("delete entry commit: %w", err)
	}
	return nil
}

// UnlinkEntry detaches an entry from its activity, freezing its tags.
func (s *PostgresStore) UnlinkEntry(ctx context.Context, userID, id string) (Entry, error) {
	current, err := s.pgGetEntryRow(ctx, userID, id)
	if err != nil {
		return Entry{}, err
	}
	if !current.Linked {
		return current, fmt.Errorf("unlink entry: %w", ErrConflict)
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Entry{}, fmt.Errorf("unlink entry begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	now := time.Now().UTC()
	res, err := tx.Exec(ctx, `
		UPDATE entries SET activity_id = NULL, updated_at = $1
		WHERE id = $2 AND user_id = $3 AND activity_id IS NOT NULL
	`, now, id, userID)
	if err != nil {
		return Entry{}, fmt.Errorf("unlink entry update: %w", err)
	}
	if res.RowsAffected() == 0 {
		return current, fmt.Errorf("unlink entry: %w", ErrConflict)
	}

	// Freeze the activity's current tags into the snapshot table. Read all
	// tags first (closing the cursor) before inserting.
	rows, err := tx.Query(ctx, `
		SELECT c.id, c.name, c.color
		FROM activity_categories ac
		JOIN categories c ON c.id = ac.category_id
		WHERE ac.activity_id = $1 AND c.user_id = $2
	`, *current.ActivityID, userID)
	if err != nil {
		return Entry{}, fmt.Errorf("unlink entry snapshot select: %w", err)
	}
	var tags []CategoryTag
	for rows.Next() {
		var t CategoryTag
		if err := rows.Scan(&t.ID, &t.Name, &t.Color); err != nil {
			return Entry{}, fmt.Errorf("unlink entry snapshot scan: %w", err)
		}
		tags = append(tags, t)
	}
	if err := rows.Err(); err != nil {
		return Entry{}, fmt.Errorf("unlink entry snapshot rows: %w", err)
	}
	rows.Close()
	for _, t := range tags {
		if _, err := tx.Exec(ctx, `
			INSERT INTO entry_tag_snapshots (entry_id, category_id, category_name_snapshot, category_color_snapshot)
			VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING
		`, id, t.ID, t.Name, t.Color); err != nil {
			return Entry{}, fmt.Errorf("unlink entry snapshot insert: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return Entry{}, fmt.Errorf("unlink entry commit: %w", err)
	}
	return s.GetEntry(ctx, userID, id)
}

// pgIsUniqueViolation reports whether err is a Postgres unique-constraint failure.
func pgIsUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}
