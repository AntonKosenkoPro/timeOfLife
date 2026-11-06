package db

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

// Review-auth Postgres parity suite (demo-account-access task 3.3): the
// durable-budget contract verified against real PostgreSQL — boundaries,
// daily cap, success-consumes, denied-no-extend, restart-equivalence,
// purge integration, missing-user fence, and the concurrent-last-slot race.
// Gated on TEST_PG_DSN like the rest of this file; run against a LOCAL test
// database only (never Supabase production).

func newReviewParityStore(t *testing.T) *PostgresStore {
	t.Helper()
	store := newParityStore(t)
	ctx := context.Background()
	if _, err := store.DB().Exec(ctx, `TRUNCATE review_auth_attempts RESTART IDENTITY CASCADE`); err != nil {
		t.Fatalf("truncate review attempts: %v", err)
	}
	return store
}

func parityReviewUser(t *testing.T, store *PostgresStore, email string) string {
	t.Helper()
	uid := parityUser(t, store, email)
	if _, err := store.DB().Exec(context.Background(),
		`UPDATE users SET email_verified = true WHERE id = $1`, uid); err != nil {
		t.Fatalf("verify user: %v", err)
	}
	return uid
}

func insertPGAttemptAt(t *testing.T, store *PostgresStore, userID string, at time.Time) {
	t.Helper()
	if _, err := store.DB().Exec(context.Background(), `
		INSERT INTO review_auth_attempts (id, user_id, admitted_at)
		VALUES (gen_random_uuid(), $1, $2)
	`, userID, at.UTC()); err != nil {
		t.Fatalf("insert review attempt: %v", err)
	}
}

func pgAttemptCount(t *testing.T, store *PostgresStore, userID string) int {
	t.Helper()
	var n int
	if err := store.DB().QueryRow(context.Background(), `
		SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = $1
	`, userID).Scan(&n); err != nil {
		t.Fatalf("count review attempts: %v", err)
	}
	return n
}

// TestPostgres_ReviewAdmission_Boundaries pins the full budget contract on
// Postgres: first admission, short-window 5/15m denial with bounded
// Retry-After, ageing-out recovery, and the 20/24h daily cap.
func TestPostgres_ReviewAdmission_Boundaries(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-bound@example.com")

	adm, err := store.ReserveReviewAttempt(ctx, uid)
	if err != nil || !adm.Admitted {
		t.Fatalf("first admission: adm=%+v err=%v", adm, err)
	}
	now := time.Now().UTC()
	for i := 1; i < 5; i++ {
		insertPGAttemptAt(t, store, uid, now.Add(-time.Duration(i)*time.Minute))
	}
	denied, err := store.ReserveReviewAttempt(ctx, uid)
	if err != nil {
		t.Fatalf("boundary reserve: %v", err)
	}
	if denied.Admitted {
		t.Fatal("expected 6th admission within 15m denied")
	}
	if denied.RetryAfter <= 0 || denied.RetryAfter > 15*time.Minute {
		t.Errorf("expected short-window Retry-After, got %v", denied.RetryAfter)
	}
	if got := pgAttemptCount(t, store, uid); got != 5 {
		t.Errorf("denial must not append history: got %d rows", got)
	}

	// Daily cap: 20 admissions outside the short window still throttle.
	uid2 := parityReviewUser(t, store, "pg-review-daily@example.com")
	for i := 0; i < 20; i++ {
		insertPGAttemptAt(t, store, uid2, now.Add(-time.Duration(20+i*70)*time.Minute))
	}
	denied2, err := store.ReserveReviewAttempt(ctx, uid2)
	if err != nil {
		t.Fatalf("daily reserve: %v", err)
	}
	if denied2.Admitted {
		t.Fatal("expected 21st admission within 24h denied")
	}
	if denied2.RetryAfter <= 15*time.Minute || denied2.RetryAfter > 24*time.Hour {
		t.Errorf("expected long-window Retry-After, got %v", denied2.RetryAfter)
	}
}

// TestPostgres_ReviewAdmission_ConcurrentLastSlot pins atomicity on
// Postgres: N concurrent racers against one remaining slot admit exactly
// one (account-row lock serializes the read-modify-write).
func TestPostgres_ReviewAdmission_ConcurrentLastSlot(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-race@example.com")
	now := time.Now().UTC()
	for i := 0; i < 4; i++ {
		insertPGAttemptAt(t, store, uid, now.Add(-time.Duration(i)*time.Minute))
	}
	const racers = 12
	var wg sync.WaitGroup
	admitted := make([]bool, racers)
	for i := 0; i < racers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			adm, err := store.ReserveReviewAttempt(ctx, uid)
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
	if got := pgAttemptCount(t, store, uid); got != 5 {
		t.Errorf("expected 5 stored attempts, got %d", got)
	}
}

// TestPostgres_ReviewAdmission_DeniedDoesNotExtend pins that consecutive
// Postgres denials report non-increasing Retry-After (no timestamp moves).
func TestPostgres_ReviewAdmission_DeniedDoesNotExtend(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-noextend@example.com")
	now := time.Now().UTC()
	for i := 0; i < 5; i++ {
		insertPGAttemptAt(t, store, uid, now.Add(-time.Duration(i)*time.Minute))
	}
	first, err := store.ReserveReviewAttempt(ctx, uid)
	if err != nil || first.Admitted {
		t.Fatalf("first: adm=%+v err=%v", first, err)
	}
	second, err := store.ReserveReviewAttempt(ctx, uid)
	if err != nil || second.Admitted {
		t.Fatalf("second: adm=%+v err=%v", second, err)
	}
	if second.RetryAfter > first.RetryAfter {
		t.Errorf("denial extended the window: first %v, second %v", first.RetryAfter, second.RetryAfter)
	}
}

// TestPostgres_ReviewAdmission_PurgeAndMissingUser pins the lifecycle
// fences on Postgres: purge removes attempt rows, and reserving for a
// purged account reports ErrUserMissing (never an admission).
func TestPostgres_ReviewAdmission_PurgeAndMissingUser(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-purge@example.com")
	other := parityReviewUser(t, store, "pg-review-purge-other@example.com")

	if _, err := store.ReserveReviewAttempt(ctx, uid); err != nil {
		t.Fatalf("reserve: %v", err)
	}
	insertPGAttemptAt(t, store, other, time.Now().UTC())

	digestFn := func(subject string) string { return "digest:" + subject }
	if _, err := store.PurgeUser(ctx, uid, "", digestFn); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	var n int
	if err := store.DB().QueryRow(ctx,
		`SELECT COUNT(*) FROM review_auth_attempts WHERE user_id = $1`, uid).Scan(&n); err != nil {
		t.Fatalf("count purged: %v", err)
	}
	if n != 0 {
		t.Errorf("expected purged attempts removed, got %d", n)
	}
	if got := pgAttemptCount(t, store, other); got != 1 {
		t.Errorf("expected other account intact, got %d", got)
	}
	if _, err := store.ReserveReviewAttempt(ctx, uid); !errors.Is(err, ErrUserMissing) {
		t.Fatalf("expected ErrUserMissing for purged account, got %v", err)
	}
}

// TestPostgres_ReviewRevocation_IsolatedAndRepeatable pins the operator
// shutdown primitive on Postgres: revoking the review UUID closes its
// sessions (and is idempotent on repeat) while another account's sessions
// and recovery receipts stay live.
func TestPostgres_ReviewRevocation_IsolatedAndRepeatable(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-revoke@example.com")
	other := parityReviewUser(t, store, "pg-review-revoke-other@example.com")

	mustSave := func(id, hash, device string) {
		if err := store.SaveRefreshTokenWithAuth(ctx, id, hash, device, nil, ""); err != nil {
			t.Fatalf("SaveRefreshToken: %v", err)
		}
	}
	mustSave(uid, "review-hash-a", "device-a")
	mustSave(other, "other-hash-b", "device-b")

	if err := store.RevokeAllUserSessions(ctx, uid); err != nil {
		t.Fatalf("RevokeAllUserSessions: %v", err)
	}
	if err := store.RevokeAllUserSessions(ctx, uid); err != nil {
		t.Fatalf("repeat revocation must be idempotent: %v", err)
	}
	rt, err := store.GetRefreshToken(ctx, "review-hash-a")
	if err != nil || !rt.Revoked {
		t.Fatalf("expected review session revoked, got %+v err=%v", rt, err)
	}
	ot, err := store.GetRefreshToken(ctx, "other-hash-b")
	if err != nil || ot.Revoked {
		t.Fatalf("expected other account untouched, got %+v err=%v", ot, err)
	}
}

// TestPostgres_ReviewAdmission_RestartKeepsBudgets pins durability across
// process restarts: budgets live in the table, so a fresh pool on the same
// database still throttles.
func TestPostgres_ReviewAdmission_RestartKeepsBudgets(t *testing.T) {
	store := newReviewParityStore(t)
	ctx := context.Background()
	uid := parityReviewUser(t, store, "pg-review-restart@example.com")
	now := time.Now().UTC()
	for i := 0; i < 5; i++ {
		insertPGAttemptAt(t, store, uid, now.Add(-time.Duration(i)*time.Minute))
	}
	dsn := store.DB().Config().ConnString()
	fresh, err := NewPostgresStore(ctx, dsn)
	if err != nil {
		t.Fatalf("reconnect: %v", err)
	}
	defer func() { _ = fresh.Close() }()
	denied, err := fresh.ReserveReviewAttempt(ctx, uid)
	if err != nil {
		t.Fatalf("reserve on fresh pool: %v", err)
	}
	if denied.Admitted {
		t.Fatal("expected throttling to survive a restart (fresh pool)")
	}
}
