package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// reviewRetryAfter computes the ceiling in seconds until both violated
// windows have capacity again: for each exhausted window the oldest retained
// admission plus the window length, minus now; the denial lifts only when
// every violated window drains, so the maximum applies. The floor is one
// second — a denial always backs the client off.
func reviewRetryAfter(now time.Time, shortOldest *time.Time, longOldest *time.Time) time.Duration {
	retry := time.Duration(0)
	if shortOldest != nil {
		if d := shortOldest.Add(ReviewAccessShortWindow).Sub(now); d > retry {
			retry = d
		}
	}
	if longOldest != nil {
		if d := longOldest.Add(ReviewAccessLongWindow).Sub(now); d > retry {
			retry = d
		}
	}
	ceiled := retry.Truncate(time.Second)
	if ceiled < retry {
		ceiled += time.Second
	}
	if ceiled < time.Second {
		ceiled = time.Second
	}
	return ceiled
}

// ReserveReviewAttempt atomically reserves one review-code evaluation. See
// the Store interface for the contract: account-row lock first (matching
// the purge/rotation lock order), authoritative store time, prune-then-count
// with strictly-newer window membership, reserve-before-compare, and no
// history mutation on denial.
func (s *PostgresStore) ReserveReviewAttempt(ctx context.Context, userID string) (ReviewAdmission, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Consistent lock order: the account row before family rows, matching
	// purge and rotation. A purge that removed the account races here as
	// ErrUserMissing — never a partial admission.
	var one int
	if err := tx.QueryRow(ctx, `
		SELECT 1 FROM users WHERE id = $1 FOR UPDATE
	`, userID).Scan(&one); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", ErrUserMissing)
		}
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	// Authoritative store time (NOW() is transaction-start time in Postgres,
	// so every statement below shares one clock).
	var now time.Time
	if err := tx.QueryRow(ctx, `SELECT NOW()`).Scan(&now); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	shortCutoff := now.Add(-ReviewAccessShortWindow)
	longCutoff := now.Add(-ReviewAccessLongWindow)

	// Opportunistic pruning: history at/below the long cutoff is expired
	// and reclaimed here, so idle accounts keep no rows. Committed with the
	// transaction whether the attempt is admitted or denied.
	if _, err := tx.Exec(ctx, `
		DELETE FROM review_auth_attempts WHERE user_id = $1 AND admitted_at <= $2
	`, userID, longCutoff); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	var shortCount, longCount int
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = $1 AND admitted_at > $2
	`, userID, shortCutoff).Scan(&shortCount); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	if err := tx.QueryRow(ctx, `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = $1 AND admitted_at > $2
	`, userID, longCutoff).Scan(&longCount); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	shortExhausted := shortCount >= ReviewAccessShortLimit
	longExhausted := longCount >= ReviewAccessLongLimit
	if !shortExhausted && !longExhausted {
		if _, err := tx.Exec(ctx, `
			INSERT INTO review_auth_attempts (id, user_id, admitted_at)
			VALUES (gen_random_uuid(), $1, $2)
		`, userID, now); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		if err := tx.Commit(ctx); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		return ReviewAdmission{Admitted: true}, nil
	}

	// Denied: compute Retry-After from the oldest retained admission in each
	// exhausted window. A denial appends nothing — it cannot extend the
	// window — but the prune above still commits.
	var shortOldest, longOldest *time.Time
	if shortExhausted {
		var oldest time.Time
		if err := tx.QueryRow(ctx, `
			SELECT MIN(admitted_at) FROM review_auth_attempts WHERE user_id = $1 AND admitted_at > $2
		`, userID, shortCutoff).Scan(&oldest); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		shortOldest = &oldest
	}
	if longExhausted {
		var oldest time.Time
		if err := tx.QueryRow(ctx, `
			SELECT MIN(admitted_at) FROM review_auth_attempts WHERE user_id = $1 AND admitted_at > $2
		`, userID, longCutoff).Scan(&oldest); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		longOldest = &oldest
	}
	if err := tx.Commit(ctx); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	return ReviewAdmission{Admitted: false, RetryAfter: reviewRetryAfter(now, shortOldest, longOldest)}, nil
}

// ReserveReviewAttempt atomically reserves one review-code evaluation on
// SQLite. Single-writer SQLite serializes writers, which provides the same
// exclusion the Postgres account-row lock gives; the statements otherwise
// mirror the Postgres twin (prune, strictly-newer counts, reserve on
// capacity, Retry-After from the oldest retained admission, prune committed
// on denial).
func (s *SQLiteStore) ReserveReviewAttempt(ctx context.Context, userID string) (ReviewAdmission, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	var one int
	if err := tx.QueryRowContext(ctx, `
		SELECT 1 FROM users WHERE id = ?
	`, userID).Scan(&one); err != nil {
		if err == sql.ErrNoRows {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", ErrUserMissing)
		}
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	// Authoritative store time: the database clock, not the request clock.
	var nowStr string
	if err := tx.QueryRowContext(ctx, `SELECT datetime('now')`).Scan(&nowStr); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	now := parseTime(nowStr)
	shortCutoff := fmtTime(now.Add(-ReviewAccessShortWindow))
	longCutoff := fmtTime(now.Add(-ReviewAccessLongWindow))

	if _, err := tx.ExecContext(ctx, `
		DELETE FROM review_auth_attempts WHERE user_id = ? AND admitted_at <= ?
	`, userID, longCutoff); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	var shortCount, longCount int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = ? AND admitted_at > ?
	`, userID, shortCutoff).Scan(&shortCount); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = ? AND admitted_at > ?
	`, userID, longCutoff).Scan(&longCount); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}

	shortExhausted := shortCount >= ReviewAccessShortLimit
	longExhausted := longCount >= ReviewAccessLongLimit
	if !shortExhausted && !longExhausted {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO review_auth_attempts (id, user_id, admitted_at)
			VALUES (?, ?, ?)
		`, uuidV7(), userID, fmtTime(now)); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		if err := tx.Commit(); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		return ReviewAdmission{Admitted: true}, nil
	}

	var shortOldest, longOldest *time.Time
	if shortExhausted {
		var oldestStr sql.NullString
		if err := tx.QueryRowContext(ctx, `
			SELECT MIN(admitted_at) FROM review_auth_attempts WHERE user_id = ? AND admitted_at > ?
		`, userID, shortCutoff).Scan(&oldestStr); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		if oldestStr.Valid {
			oldest := parseTime(oldestStr.String)
			shortOldest = &oldest
		}
	}
	if longExhausted {
		var oldestStr sql.NullString
		if err := tx.QueryRowContext(ctx, `
			SELECT MIN(admitted_at) FROM review_auth_attempts WHERE user_id = ? AND admitted_at > ?
		`, userID, longCutoff).Scan(&oldestStr); err != nil {
			return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
		}
		if oldestStr.Valid {
			oldest := parseTime(oldestStr.String)
			longOldest = &oldest
		}
	}
	if err := tx.Commit(); err != nil {
		return ReviewAdmission{}, fmt.Errorf("reserve review attempt: %w", err)
	}
	return ReviewAdmission{Admitted: false, RetryAfter: reviewRetryAfter(now, shortOldest, longOldest)}, nil
}
