package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ---------- SQLite planner ----------

// scanPlannerTask scans one planner task row (without user_id) into a
// PlannerTask. completed_on arrives as a civil-date TEXT (or NULL when open);
// category_ids arrives as a JSON array TEXT (or NULL on pre-012 rows);
// notes arrives as TEXT (or NULL on pre-013 rows — defaulting to empty, like
// the iOS feed decode, so old rows never fail the read).
func scanPlannerTask(sc rowScanner, userID string) (PlannerTask, error) {
	var (
		t           PlannerTask
		completedOn sql.NullString
		categories  sql.NullString
		notes       sql.NullString
		createdAt   string
		updatedAt   string
		deleted     int64
	)
	if err := sc.Scan(&t.ID, &t.Name, &t.PositionKey, &completedOn, &categories, &t.Notes, &t.Revision, &createdAt, &updatedAt, &deleted); err != nil {
		return PlannerTask{}, err
	}
	t.UserID = userID
	if completedOn.Valid && completedOn.String != "" {
		// The SQLite driver may surface a DATE column as RFC3339; the
		// store is canonical civil YYYY-MM-DD either way.
		s := completedOn.String
		if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
			s = t.Format("2006-01-02")
		} else if t, err := time.Parse("2006-01-02", s); err == nil {
			s = t.Format("2006-01-02")
		}
		t.CompletedOn = &s
	}
	t.CategoryIDs = parsePlannerCategoryIDs(categories.String)
	if notes.Valid {
		t.Notes = notes.String
	}
	t.CreatedAt = parseTime(createdAt)
	t.UpdatedAt = parseTime(updatedAt)
	t.Deleted = deleted != 0
	return t, nil
}

type sqlitePlannerQuerier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// sqliteGetPlannerTask reads one planner task row inside or outside a tx.
func sqliteGetPlannerTask(ctx context.Context, q sqlitePlannerQuerier, userID, id string) (PlannerTask, error) {
	t, err := scanPlannerTask(q.QueryRowContext(ctx, `
		SELECT id, name, position_key, completed_on, category_ids, notes, revision, created_at, updated_at, deleted
		FROM planner_tasks
		WHERE user_id = ? AND id = ?
	`, userID, id), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return PlannerTask{}, fmt.Errorf("get planner task: %w", ErrNotFound)
		}
		return PlannerTask{}, fmt.Errorf("get planner task: %w", err)
	}
	return t, nil
}

// sqlitePlannerReceipt returns the stored revision for an accepted operation
// id, or ErrNotFound when the operation was never accepted.
func sqlitePlannerReceipt(ctx context.Context, q sqlitePlannerQuerier, userID, operationID string) (int64, error) {
	var revision int64
	err := q.QueryRowContext(ctx, `
		SELECT revision FROM planner_receipts WHERE user_id = ? AND operation_id = ?
	`, userID, operationID).Scan(&revision)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, fmt.Errorf("planner receipt: %w", ErrNotFound)
		}
		return 0, fmt.Errorf("planner receipt: %w", err)
	}
	return revision, nil
}

// ApplyPlannerOperation applies one field-specific planner mutation. The
// single-connection SQLite pool serializes the whole transaction, which is
// the SQLite counterpart of the Postgres per-account sequence lock: commit
// order equals revision-assignment order on both stores.
func (s *SQLiteStore) ApplyPlannerOperation(ctx context.Context, userID string, op PlannerOperation) (PlannerTask, bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	txQ := &sqliteTxQuerier{tx: tx}

	// Lost-response replay: an accepted operation id returns the stored
	// state without applying anything twice.
	if _, err := sqlitePlannerReceipt(ctx, txQ, userID, op.OperationID); err == nil {
		task, err := sqliteGetPlannerTask(ctx, txQ, userID, op.TaskID)
		if err != nil {
			return PlannerTask{}, false, err
		}
		if err := tx.Commit(); err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner replay commit: %w", err)
		}
		return task, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return PlannerTask{}, false, err
	}

	// Serialize revision assignment per account (single-conn pool: no other
	// writer can interleave while this tx holds the connection).
	if _, err := tx.ExecContext(ctx, `
		INSERT OR IGNORE INTO planner_seq (user_id, last_revision) VALUES (?, 0)
	`, userID); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq init: %w", err)
	}
	var last int64
	if err := tx.QueryRowContext(ctx, `
		SELECT last_revision FROM planner_seq WHERE user_id = ?
	`, userID).Scan(&last); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq lock: %w", err)
	}
	next := last + 1

	// Record the receipt before touching the task row: a concurrent
	// duplicate delivery of the same operation id fails here and rolls back
	// instead of applying twice.
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO planner_receipts (user_id, operation_id, task_id, revision)
		VALUES (?, ?, ?, ?)
	`, userID, op.OperationID, op.TaskID, next); err != nil {
		if isUniqueViolation(err) {
			// A concurrent duplicate won the race; return its stored result.
			if rbErr := tx.Rollback(); rbErr != nil && !errors.Is(rbErr, sql.ErrTxDone) {
				return PlannerTask{}, false, fmt.Errorf("planner race rollback: %w", rbErr)
			}
			task, err := sqliteGetPlannerTask(ctx, s.db, userID, op.TaskID)
			if err != nil {
				return PlannerTask{}, false, err
			}
			return task, false, nil
		}
		return PlannerTask{}, false, fmt.Errorf("planner receipt: %w", err)
	}

	existing, err := sqliteGetPlannerTask(ctx, txQ, userID, op.TaskID)
	known := err == nil
	if err != nil && !errors.Is(err, ErrNotFound) {
		return PlannerTask{}, false, err
	}

	now := fmtTime(time.Now().UTC())

	opNotes := ""
	if op.Notes != nil {
		opNotes = *op.Notes
	}
	switch op.Intent {
	case PlannerIntentCreate:
		if known {
			if existing.Deleted {
				return existing, false, fmt.Errorf("planner create: %w", ErrPlannerGone)
			}
			return existing, false, fmt.Errorf("planner create: %w", ErrPlannerConflict)
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO planner_tasks (user_id, id, name, position_key, completed_on, category_ids, notes, revision, created_at, updated_at, deleted)
			VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 0)
		`, userID, op.TaskID, *op.Name, *op.PositionKey, encodePlannerCategoryIDs(op.CategoryIDs), opNotes, next, now, now); err != nil {
			if isUniqueViolation(err) {
				// A concurrent create won the race after our receipt
				// succeeded: the winner carries a different operation id
				// (same id would have hit the receipt first).
				raced, rerr := sqliteGetPlannerTask(ctx, txQ, userID, op.TaskID)
				if rerr != nil {
					return PlannerTask{}, false, rerr
				}
				if raced.Deleted {
					return existing, false, fmt.Errorf("planner create: %w", ErrPlannerGone)
				}
				return raced, false, fmt.Errorf("planner create: %w", ErrPlannerConflict)
			}
			return PlannerTask{}, false, fmt.Errorf("planner create: %w", err)
		}
	case PlannerIntentRename, PlannerIntentMove, PlannerIntentComplete, PlannerIntentReopen, PlannerIntentRetag, PlannerIntentNotes:
		if !known {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", ErrNotFound)
		}
		if existing.Deleted {
			return existing, false, fmt.Errorf("planner update: %w", ErrPlannerGone)
		}
		var res sql.Result
		switch op.Intent {
		case PlannerIntentRename:
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET name = ?, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, *op.Name, next, now, userID, op.TaskID)
		case PlannerIntentMove:
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET position_key = ?, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, *op.PositionKey, next, now, userID, op.TaskID)
		case PlannerIntentComplete:
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET completed_on = ?, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, *op.CompletedOn, next, now, userID, op.TaskID)
		case PlannerIntentRetag:
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET category_ids = ?, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, encodePlannerCategoryIDs(op.CategoryIDs), next, now, userID, op.TaskID)
		case PlannerIntentNotes:
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET notes = ?, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, opNotes, next, now, userID, op.TaskID)
		default: // PlannerIntentReopen
			res, err = tx.ExecContext(ctx, `
				UPDATE planner_tasks SET completed_on = NULL, revision = ?, updated_at = ?
				WHERE user_id = ? AND id = ?
			`, next, now, userID, op.TaskID)
		}
		if err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", err)
		}
		affected, err := res.RowsAffected()
		if err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner update rows: %w", err)
		}
		if affected == 0 {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", ErrNotFound)
		}
	case PlannerIntentDelete:
		if !known {
			return PlannerTask{}, false, fmt.Errorf("planner delete: %w", ErrNotFound)
		}
		if existing.Deleted {
			// Replay-safe: an already-terminal task stays terminal with no
			// new revision; roll back the receipt probe and return state.
			if err := tx.Rollback(); err != nil && !errors.Is(err, sql.ErrTxDone) {
				return PlannerTask{}, false, fmt.Errorf("planner delete rollback: %w", err)
			}
			return existing, false, nil
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE planner_tasks SET deleted = 1, revision = ?, updated_at = ?
			WHERE user_id = ? AND id = ?
		`, next, now, userID, op.TaskID); err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner delete: %w", err)
		}
	default:
		return PlannerTask{}, false, fmt.Errorf("planner unknown intent %q", op.Intent)
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE planner_seq SET last_revision = ? WHERE user_id = ?
	`, next, userID); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq advance: %w", err)
	}
	result, err := sqliteGetPlannerTask(ctx, txQ, userID, op.TaskID)
	if err != nil {
		return PlannerTask{}, false, err
	}
	if err := tx.Commit(); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner commit: %w", err)
	}
	return result, true, nil
}

// sqliteTxQuerier adapts a *sql.Tx to the row-query shape used above.
type sqliteTxQuerier struct {
	tx *sql.Tx
}

func (q *sqliteTxQuerier) QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row {
	return q.tx.QueryRowContext(ctx, query, args...)
}

// ListPlannerFeed returns planner changes with revision in
// (afterRevision, watermark], ordered by revision ASC. The watermark is the
// committed per-account maximum fixed before the page read, so a pull that
// stops after a committed page resumes without skipping changes that commit
// behind the cursor — those belong to a later page by construction.
func (s *SQLiteStore) ListPlannerFeed(ctx context.Context, userID string, afterRevision int64, limit int) ([]PlannerTask, int64, bool, error) {
	if limit <= 0 {
		limit = 50
	}
	var watermark sql.NullInt64
	if err := s.db.QueryRowContext(ctx, `
		SELECT last_revision FROM planner_seq WHERE user_id = ?
	`, userID).Scan(&watermark); err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, 0, false, fmt.Errorf("planner watermark: %w", err)
		}
	}
	wm := int64(0)
	if watermark.Valid {
		wm = watermark.Int64
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, position_key, completed_on, category_ids, notes, revision, created_at, updated_at, deleted
		FROM planner_tasks
		WHERE user_id = ? AND revision > ? AND revision <= ?
		ORDER BY revision ASC
		LIMIT ?
	`, userID, afterRevision, wm, limit+1)
	if err != nil {
		return nil, 0, false, fmt.Errorf("planner feed: %w", err)
	}
	defer func() { _ = rows.Close() }()
	tasks := []PlannerTask{}
	for rows.Next() {
		t, err := scanPlannerTask(rows, userID)
		if err != nil {
			return nil, 0, false, fmt.Errorf("planner feed scan: %w", err)
		}
		tasks = append(tasks, t)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, false, fmt.Errorf("planner feed rows: %w", err)
	}
	hasMore := false
	if len(tasks) > limit {
		hasMore = true
		tasks = tasks[:limit]
	}
	return tasks, wm, hasMore, nil
}
