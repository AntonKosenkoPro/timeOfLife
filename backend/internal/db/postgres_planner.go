package db

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ---------- Postgres planner ----------

// pgScanPlannerTask scans one planner task row (without user_id) into a
// PlannerTask. completed_on arrives as a civil date (or NULL when open);
// category_ids arrives as a JSON array TEXT (or NULL on pre-012 rows).
func pgScanPlannerTask(sc pgxScanner, userID string) (PlannerTask, error) {
	var (
		t           PlannerTask
		completedOn *time.Time
		categories  *string
	)
	if err := sc.Scan(&t.ID, &t.Name, &t.PositionKey, &completedOn, &categories, &t.Revision, &t.CreatedAt, &t.UpdatedAt, &t.Deleted); err != nil {
		return PlannerTask{}, err
	}
	t.UserID = userID
	if completedOn != nil {
		s := completedOn.Format("2006-01-02")
		t.CompletedOn = &s
	}
	raw := ""
	if categories != nil {
		raw = *categories
	}
	t.CategoryIDs = parsePlannerCategoryIDs(raw)
	return t, nil
}

func (s *PostgresStore) pgGetPlannerTask(ctx context.Context, q interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}, userID, id string) (PlannerTask, error) {
	task, err := pgScanPlannerTask(q.QueryRow(ctx, `
		SELECT id, name, position_key, completed_on, category_ids, revision, created_at, updated_at, deleted
		FROM planner_tasks
		WHERE user_id = $1 AND id = $2
	`, userID, id), userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return PlannerTask{}, fmt.Errorf("get planner task: %w", ErrNotFound)
		}
		return PlannerTask{}, fmt.Errorf("get planner task: %w", err)
	}
	return task, nil
}

// pgPlannerReceipt returns the stored revision for an accepted operation id,
// or ErrNotFound when the operation was never accepted.
func pgPlannerReceipt(ctx context.Context, q interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}, userID, operationID string) (int64, error) {
	var revision int64
	err := q.QueryRow(ctx, `
		SELECT revision FROM planner_receipts WHERE user_id = $1 AND operation_id = $2
	`, userID, operationID).Scan(&revision)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, fmt.Errorf("planner receipt: %w", ErrNotFound)
		}
		return 0, fmt.Errorf("planner receipt: %w", err)
	}
	return revision, nil
}

// ApplyPlannerOperation applies one field-specific planner mutation. The
// whole acceptance runs inside one transaction holding the account's
// sequence row (SELECT ... FOR UPDATE), so concurrent operations on one
// account commit with distinct revisions in acceptance order: commit order
// equals assignment order and no lower revision can appear behind an
// advanced feed watermark.
func (s *PostgresStore) ApplyPlannerOperation(ctx context.Context, userID string, op PlannerOperation) (PlannerTask, bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Lost-response replay: an accepted operation id returns the stored
	// state without applying anything twice.
	if _, err := pgPlannerReceipt(ctx, tx, userID, op.OperationID); err == nil {
		task, err := s.pgGetPlannerTask(ctx, tx, userID, op.TaskID)
		if err != nil {
			return PlannerTask{}, false, err
		}
		if err := tx.Commit(ctx); err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner replay commit: %w", err)
		}
		return task, false, nil
	} else if !errors.Is(err, ErrNotFound) {
		return PlannerTask{}, false, err
	}

	// Serialize revision assignment per account.
	if _, err := tx.Exec(ctx, `
		INSERT INTO planner_seq (user_id, last_revision) VALUES ($1, 0)
		ON CONFLICT (user_id) DO NOTHING
	`, userID); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq init: %w", err)
	}
	var last int64
	if err := tx.QueryRow(ctx, `
		SELECT last_revision FROM planner_seq WHERE user_id = $1 FOR UPDATE
	`, userID).Scan(&last); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq lock: %w", err)
	}
	next := last + 1

	// Record the receipt before touching the task row: a concurrent duplicate
	// delivery of the same operation id fails here and rolls back instead of
	// applying twice.
	if _, err := tx.Exec(ctx, `
		INSERT INTO planner_receipts (user_id, operation_id, task_id, revision)
		VALUES ($1, $2, $3, $4)
	`, userID, op.OperationID, op.TaskID, next); err != nil {
		if pgIsUniqueViolation(err) {
			// A concurrent duplicate won the race; return its stored result.
			if rbErr := tx.Rollback(ctx); rbErr != nil {
				return PlannerTask{}, false, fmt.Errorf("planner race rollback: %w", rbErr)
			}
			task, err := s.pgGetPlannerTask(ctx, s.pool, userID, op.TaskID)
			if err != nil {
				return PlannerTask{}, false, err
			}
			return task, false, nil
		}
		return PlannerTask{}, false, fmt.Errorf("planner receipt: %w", err)
	}

	existing, err := s.pgGetPlannerTask(ctx, tx, userID, op.TaskID)
	known := err == nil
	if err != nil && !errors.Is(err, ErrNotFound) {
		return PlannerTask{}, false, err
	}

	now := time.Now().UTC()
	var result PlannerTask
	switch op.Intent {
	case PlannerIntentCreate:
		if known {
			if existing.Deleted {
				return existing, false, fmt.Errorf("planner create: %w", ErrPlannerGone)
			}
			return existing, false, fmt.Errorf("planner create: %w", ErrPlannerConflict)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO planner_tasks (user_id, id, name, position_key, completed_on, category_ids, revision, created_at, updated_at, deleted)
			VALUES ($1, $2, $3, $4, NULL, $5, $6, $7, $7, false)
		`, userID, op.TaskID, *op.Name, *op.PositionKey, encodePlannerCategoryIDs(op.CategoryIDs), next, now); err != nil {
			if pgIsUniqueViolation(err) {
				// A concurrent create won the race after our receipt
				// succeeded: the winner carries a different operation id
				// (same id would have hit the receipt first).
				raced, rerr := s.pgGetPlannerTask(ctx, tx, userID, op.TaskID)
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
	case PlannerIntentRename, PlannerIntentMove, PlannerIntentComplete, PlannerIntentReopen, PlannerIntentRetag:
		if !known {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", ErrNotFound)
		}
		if existing.Deleted {
			return existing, false, fmt.Errorf("planner update: %w", ErrPlannerGone)
		}
		set, arg := "", any(nil)
		switch op.Intent {
		case PlannerIntentRename:
			set, arg = "name = $3", *op.Name
		case PlannerIntentMove:
			set, arg = "position_key = $3", *op.PositionKey
		case PlannerIntentComplete:
			set, arg = "completed_on = $3", *op.CompletedOn
		case PlannerIntentReopen:
			set, arg = "completed_on = NULL", nil
		case PlannerIntentRetag:
			set, arg = "category_ids = $3", encodePlannerCategoryIDs(op.CategoryIDs)
		}
		var tag pgconn.CommandTag
		if op.Intent == PlannerIntentReopen {
			tag, err = tx.Exec(ctx, `
				UPDATE planner_tasks SET completed_on = NULL, revision = $3, updated_at = $4
				WHERE user_id = $1 AND id = $2
			`, userID, op.TaskID, next, now)
		} else {
			tag, err = tx.Exec(ctx, `
				UPDATE planner_tasks SET `+set+`, revision = $4, updated_at = $5
				WHERE user_id = $1 AND id = $2
			`, userID, op.TaskID, arg, next, now)
		}
		if err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", err)
		}
		if tag.RowsAffected() == 0 {
			return PlannerTask{}, false, fmt.Errorf("planner update: %w", ErrNotFound)
		}
	case PlannerIntentDelete:
		if !known {
			return PlannerTask{}, false, fmt.Errorf("planner delete: %w", ErrNotFound)
		}
		if existing.Deleted {
			// Replay-safe: an already-terminal task stays terminal with no
			// new revision; roll back the receipt probe and return state.
			if err := tx.Rollback(ctx); err != nil {
				return PlannerTask{}, false, fmt.Errorf("planner delete rollback: %w", err)
			}
			return existing, false, nil
		}
		if _, err := tx.Exec(ctx, `
			UPDATE planner_tasks SET deleted = true, revision = $3, updated_at = $4
			WHERE user_id = $1 AND id = $2
		`, userID, op.TaskID, next, now); err != nil {
			return PlannerTask{}, false, fmt.Errorf("planner delete: %w", err)
		}
	default:
		return PlannerTask{}, false, fmt.Errorf("planner unknown intent %q", op.Intent)
	}

	if _, err := tx.Exec(ctx, `
		UPDATE planner_seq SET last_revision = $2 WHERE user_id = $1
	`, userID, next); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner seq advance: %w", err)
	}
	result, err = s.pgGetPlannerTask(ctx, tx, userID, op.TaskID)
	if err != nil {
		return PlannerTask{}, false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return PlannerTask{}, false, fmt.Errorf("planner commit: %w", err)
	}
	return result, true, nil
}

// ListPlannerFeed returns planner changes with revision in
// (afterRevision, watermark], ordered by revision ASC. The watermark is the
// committed per-account maximum fixed before the page read, so a pull that
// stops after a committed page resumes without skipping changes that commit
// behind the cursor — those belong to a later page by construction.
func (s *PostgresStore) ListPlannerFeed(ctx context.Context, userID string, afterRevision int64, limit int) ([]PlannerTask, int64, bool, error) {
	if limit <= 0 {
		limit = 50
	}
	var watermark int64
	if err := s.pool.QueryRow(ctx, `
		SELECT COALESCE((SELECT last_revision FROM planner_seq WHERE user_id = $1), 0)
	`, userID).Scan(&watermark); err != nil {
		return nil, 0, false, fmt.Errorf("planner watermark: %w", err)
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, name, position_key, completed_on, category_ids, revision, created_at, updated_at, deleted
		FROM planner_tasks
		WHERE user_id = $1 AND revision > $2 AND revision <= $3
		ORDER BY revision ASC
		LIMIT $4
	`, userID, afterRevision, watermark, limit+1)
	if err != nil {
		return nil, 0, false, fmt.Errorf("planner feed: %w", err)
	}
	defer rows.Close()
	tasks := []PlannerTask{}
	for rows.Next() {
		t, err := pgScanPlannerTask(rows, userID)
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
	return tasks, watermark, hasMore, nil
}
