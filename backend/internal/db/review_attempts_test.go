package db

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
)

// insertReviewAttemptAt plants one admitted attempt at an explicit timestamp
// (boundary control the production path cannot produce — it uses store time).
func insertReviewAttemptAt(t *testing.T, store *SQLiteStore, userID string, at time.Time) {
	t.Helper()
	if _, err := store.db.ExecContext(context.Background(), `
		INSERT INTO review_auth_attempts (id, user_id, admitted_at)
		VALUES (?, ?, ?)
	`, uuidV7(), userID, fmtTime(at.UTC())); err != nil {
		t.Fatalf("insert review attempt: %v", err)
	}
}

func reviewAttemptCount(t *testing.T, store *SQLiteStore, userID string) int {
	t.Helper()
	var n int
	if err := store.db.QueryRowContext(context.Background(), `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = ?
	`, userID).Scan(&n); err != nil {
		t.Fatalf("count review attempts: %v", err)
	}
	return n
}

func newReviewUser(t *testing.T, store *SQLiteStore, email string) User {
	t.Helper()
	user, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	if err := store.SetUserVerified(context.Background(), user.ID); err != nil {
		t.Fatalf("SetUserVerified: %v", err)
	}
	return user
}

// TestReviewAdmission_FirstAttemptAdmitted pins the base case: one evaluated
// submission consumes exactly one unit of budget.
func TestReviewAdmission_FirstAttemptAdmitted(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-admit@example.com")

	adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt: %v", err)
	}
	if !adm.Admitted {
		t.Fatal("expected first attempt admitted")
	}
	if adm.RetryAfter != 0 {
		t.Errorf("expected zero RetryAfter on admission, got %v", adm.RetryAfter)
	}
	if got := reviewAttemptCount(t, store, user.ID); got != 1 {
		t.Errorf("expected 1 stored attempt, got %d", got)
	}
}

// TestReviewAdmission_ShortWindowBoundary pins 5 admissions per rolling 15m:
// the 6th is denied with a Retry-After within the short window, and ageing
// the oldest admission out re-opens capacity.
func TestReviewAdmission_ShortWindowBoundary(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-short@example.com")

	now := time.Now().UTC()
	for i := 0; i < 5; i++ {
		insertReviewAttemptAt(t, store, user.ID, now.Add(-time.Duration(i)*time.Minute))
	}
	adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt: %v", err)
	}
	if adm.Admitted {
		t.Fatal("expected 6th attempt within 15m denied")
	}
	if adm.RetryAfter <= 0 || adm.RetryAfter > 15*time.Minute {
		t.Errorf("expected RetryAfter in (0,15m], got %v", adm.RetryAfter)
	}
	if got := reviewAttemptCount(t, store, user.ID); got != 5 {
		t.Errorf("denied attempt must not append history: got %d rows, want 5", got)
	}

	// Age every admission past the short window: capacity returns.
	if _, err := store.db.ExecContext(context.Background(),
		`DELETE FROM review_auth_attempts WHERE user_id = ?`, user.ID); err != nil {
		t.Fatalf("clear attempts: %v", err)
	}
	for i := 0; i < 5; i++ {
		insertReviewAttemptAt(t, store, user.ID, now.Add(-16*time.Minute-time.Duration(i)*time.Minute))
	}
	adm, err = store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt after ageing: %v", err)
	}
	if !adm.Admitted {
		t.Fatal("expected admission after short-window history aged out")
	}
}

// TestReviewAdmission_ShortWindowEdgeInclusion pins the boundary: an
// admission exactly at now-15m is expired (strictly-newer counting) and does
// not consume short-window capacity.
func TestReviewAdmission_ShortWindowEdgeInclusion(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-edge@example.com")

	now := time.Now().UTC()
	for i := 0; i < 4; i++ {
		insertReviewAttemptAt(t, store, user.ID, now.Add(-time.Duration(i)*time.Second))
	}
	// Fifth row lands ~15m ago; allow 2s of test-execution skew.
	insertReviewAttemptAt(t, store, user.ID, now.Add(-15*time.Minute-2*time.Second))
	adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt: %v", err)
	}
	if !adm.Admitted {
		t.Fatal("expected admission: only 4 attempts are strictly inside 15m")
	}
}

// TestReviewAdmission_LongWindowCapsAtTwenty pins the daily budget: 20
// admissions spread beyond the short window still throttle, success never
// resets, and Retry-After points past the long window.
func TestReviewAdmission_LongWindowCapsAtTwenty(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-long@example.com")

	now := time.Now().UTC()
	for i := 0; i < 20; i++ {
		// 70 minutes apart: outside the short window, inside 24h.
		insertReviewAttemptAt(t, store, user.ID, now.Add(-time.Duration(20+i*70)*time.Minute))
	}
	adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt: %v", err)
	}
	if adm.Admitted {
		t.Fatal("expected 21st attempt within 24h denied")
	}
	if adm.RetryAfter <= 15*time.Minute || adm.RetryAfter > 24*time.Hour {
		t.Errorf("expected RetryAfter in (15m,24h], got %v", adm.RetryAfter)
	}
	if got := reviewAttemptCount(t, store, user.ID); got != 20 {
		t.Errorf("denied attempt must not extend the window: got %d rows, want 20", got)
	}
}

// TestReviewAdmission_DeniedDoesNotExtend pins that a denied submission moves
// no timestamp: consecutive denials report non-increasing Retry-After.
func TestReviewAdmission_DeniedDoesNotExtend(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-noextend@example.com")

	now := time.Now().UTC()
	for i := 0; i < 5; i++ {
		insertReviewAttemptAt(t, store, user.ID, now.Add(-time.Duration(i)*time.Minute))
	}
	first, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("first ReserveReviewAttempt: %v", err)
	}
	second, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("second ReserveReviewAttempt: %v", err)
	}
	if first.Admitted || second.Admitted {
		t.Fatal("expected both attempts denied")
	}
	if second.RetryAfter > first.RetryAfter {
		t.Errorf("denial extended the window: first %v, second %v", first.RetryAfter, second.RetryAfter)
	}
}

// TestReviewAdmission_PruningBoundsRetention pins opportunistic pruning:
// history at/below now-24h is reclaimed, so idle accounts keep no rows.
func TestReviewAdmission_PruningBoundsRetention(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-prune@example.com")

	now := time.Now().UTC()
	insertReviewAttemptAt(t, store, user.ID, now.Add(-25*time.Hour))
	insertReviewAttemptAt(t, store, user.ID, now.Add(-23*time.Hour))
	adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
	if err != nil {
		t.Fatalf("ReserveReviewAttempt: %v", err)
	}
	if !adm.Admitted {
		t.Fatal("expected admission: only 1 attempt is inside 24h")
	}
	if got := reviewAttemptCount(t, store, user.ID); got != 2 {
		t.Errorf("expected pruned history (1 aged + 1 new), got %d rows", got)
	}
}

// TestReviewAdmission_MissingUserFailsWithoutSession pins the lifecycle
// fence: reserving for a purged account reports ErrUserMissing and stores
// nothing.
func TestReviewAdmission_MissingUserFailsWithoutSession(t *testing.T) {
	store := setupTestStore(t)
	_, err := store.ReserveReviewAttempt(context.Background(), "no-such-user")
	if !errors.Is(err, ErrUserMissing) {
		t.Fatalf("expected ErrUserMissing, got %v", err)
	}
}

// TestReviewAdmission_StoreFailureFailsClosed pins fail-closed behavior: a
// broken store returns an error (never an admission).
func TestReviewAdmission_StoreFailureFailsClosed(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-broken@example.com")
	_ = store.Close()

	if _, err := store.ReserveReviewAttempt(context.Background(), user.ID); err == nil {
		t.Fatal("expected error from closed store, got admission")
	}
}

// TestReviewAdmission_ConcurrentLastSlot pins atomicity: N racers against one
// remaining short-window slot admit exactly one.
func TestReviewAdmission_ConcurrentLastSlot(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-race@example.com")

	now := time.Now().UTC()
	for i := 0; i < 4; i++ {
		insertReviewAttemptAt(t, store, user.ID, now.Add(-time.Duration(i)*time.Minute))
	}
	const racers = 8
	var wg sync.WaitGroup
	admitted := make([]bool, racers)
	for i := 0; i < racers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			adm, err := store.ReserveReviewAttempt(context.Background(), user.ID)
			if err == nil && adm.Admitted {
				admitted[i] = true
			}
		}(i)
	}
	wg.Wait()
	winners := 0
	for _, w := range admitted {
		if w {
			winners++
		}
	}
	if winners != 1 {
		t.Fatalf("expected exactly 1 winner for the last slot, got %d", winners)
	}
	if got := reviewAttemptCount(t, store, user.ID); got != 5 {
		t.Errorf("expected 5 stored attempts, got %d", got)
	}
}

// TestReviewAdmission_OtherAccountsUnaffected pins per-account isolation:
// exhausting one account's budget leaves another account's budget intact.
func TestReviewAdmission_OtherAccountsUnaffected(t *testing.T) {
	store := setupTestStore(t)
	a := newReviewUser(t, store, "review-iso-a@example.com")
	b := newReviewUser(t, store, "review-iso-b@example.com")

	now := time.Now().UTC()
	for i := 0; i < 5; i++ {
		insertReviewAttemptAt(t, store, a.ID, now.Add(-time.Duration(i)*time.Minute))
	}
	if adm, err := store.ReserveReviewAttempt(context.Background(), a.ID); err != nil || adm.Admitted {
		t.Fatalf("expected A throttled, got adm=%+v err=%v", adm, err)
	}
	adm, err := store.ReserveReviewAttempt(context.Background(), b.ID)
	if err != nil || !adm.Admitted {
		t.Fatalf("expected B admitted, got adm=%+v err=%v", adm, err)
	}
}

// TestReviewAttempts_PurgeRemovesAttemptRows pins that account deletion
// atomically removes persisted review-attempt rows with the other
// operational data (no FK-cascade reliance, no other-account damage).
func TestReviewAttempts_PurgeRemovesAttemptRows(t *testing.T) {
	store := setupTestStore(t)
	user := newReviewUser(t, store, "review-purge@example.com")
	other := newReviewUser(t, store, "review-purge-other@example.com")

	now := time.Now().UTC()
	insertReviewAttemptAt(t, store, user.ID, now)
	insertReviewAttemptAt(t, store, other.ID, now)

	digestFn := func(subject string) string { return "digest:" + subject }
	if _, err := store.PurgeUser(context.Background(), user.ID, "", digestFn); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	var n int
	if err := store.db.QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = ?`, user.ID).Scan(&n); err != nil {
		t.Fatalf("count purged attempts: %v", err)
	}
	if n != 0 {
		t.Errorf("expected purged account's attempts removed, got %d", n)
	}
	if err := store.db.QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = ?`, other.ID).Scan(&n); err != nil {
		t.Fatalf("count other attempts: %v", err)
	}
	if n != 1 {
		t.Errorf("expected other account's attempts intact, got %d", n)
	}
}

// TestReviewAttempts_MigrationParity pins the additive schema contract: the
// table and its index exist on a fresh store and previous images keep
// running (no destructive migration).
func TestReviewAttempts_MigrationParity(t *testing.T) {
	store := setupTestStore(t)
	var table string
	if err := store.db.QueryRowContext(context.Background(), `
		SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'review_auth_attempts'
	`).Scan(&table); err != nil {
		t.Fatalf("review_auth_attempts table missing: %v", err)
	}
	var idx int
	if err := store.db.QueryRowContext(context.Background(), `
		SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_review_auth_attempts_user_time'
	`).Scan(&idx); err != nil {
		t.Fatalf("index check: %v", err)
	}
	if idx != 1 {
		t.Error("expected idx_review_auth_attempts_user_time index")
	}
	var colDefault sql.NullString
	if err := store.db.QueryRowContext(context.Background(), `
		SELECT dflt_value FROM pragma_table_info('review_auth_attempts') WHERE name = 'admitted_at'
	`).Scan(&colDefault); err != nil {
		t.Fatalf("column check: %v", err)
	}
	// The migration's DEFAULT NOW() must survive the SQLite adapter, which
	// rewrites NOW() to (datetime('now')) (see sqliteReplacements): a bare
	// non-empty check would still pass on a wrong default (e.g. a literal
	// timestamp or an unconverted NOW()).
	if !colDefault.Valid || !strings.Contains(strings.ToLower(colDefault.String), "datetime('now')") {
		t.Errorf("expected admitted_at default to be adapted NOW(), got %+v", colDefault)
	}
}
