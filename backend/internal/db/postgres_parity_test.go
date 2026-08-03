package db

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/migrations"
)

// PostgreSQL parity suite (R-007 / 1.1-API-007): the same critical catalog
// semantics the SQLite store is tested against, executed against real
// PostgreSQL so SQLite-only CI cannot mask production behavior drift.
//
// Gated on TEST_PG_DSN — `make test:pg` sets it against docker-compose.
// When unset, every test here skips and `go test ./...` stays green offline.

func newParityStore(t *testing.T) *PostgresStore {
	t.Helper()
	dsn := os.Getenv("TEST_PG_DSN")
	if dsn == "" {
		t.Skip("TEST_PG_DSN not set — skipping PostgreSQL parity tests (make test:pg)")
	}

	ctx := context.Background()
	store, err := NewPostgresStore(ctx, dsn)
	if err != nil {
		t.Fatalf("NewPostgresStore: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })

	if err := migrations.RunPostgres(ctx, store.Pool()); err != nil {
		t.Fatalf("RunPostgres: %v", err)
	}

	// Truncate for isolation (migrations are idempotent IF NOT EXISTS).
	if _, err := store.Pool().Exec(ctx, `
		TRUNCATE entries, activity_categories, activities, categories,
		         refresh_tokens, otp_codes, users RESTART IDENTITY CASCADE
	`); err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return store
}

func parityUser(t *testing.T, store *PostgresStore, email string) string {
	t.Helper()
	u, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	return u.ID
}

func parityActivity(t *testing.T, store *PostgresStore, userID, name string) Activity {
	t.Helper()
	a, created, err := store.CreateActivity(context.Background(), Activity{
		ID: uuidV7(), UserID: userID, Name: name,
	}, nil)
	if err != nil {
		t.Fatalf("CreateActivity: %v", err)
	}
	if !created {
		t.Fatalf("CreateActivity: expected created=true for %q", name)
	}
	return a
}

func TestPostgres_CreateActivity_IdempotentReplay(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "replay@example.com")

	a := Activity{ID: uuidV7(), UserID: uid, Name: "Gym"}
	_, created, err := store.CreateActivity(context.Background(), a, nil)
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}
	_, created, err = store.CreateActivity(context.Background(), a, nil)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if created {
		t.Fatal("replay of same id must return created=false")
	}
}

func TestPostgres_CreateActivity_NameCollision(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "collision@example.com")

	parityActivity(t, store, uid, "Gym")
	_, _, err := store.CreateActivity(context.Background(), Activity{
		ID: uuidV7(), UserID: uid, Name: "gym",
	}, nil)
	if !errors.Is(err, ErrActivityExists) {
		t.Fatalf("expected ErrActivityExists, got %v", err)
	}
}

func TestPostgres_UpdateActivity_LWWConflict(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "lww@example.com")
	a := parityActivity(t, store, uid, "Gym")

	stale := a.UpdatedAt.Add(-time.Hour)
	name := "Renamed"
	_, err := store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		Name: &name, UpdatedAt: stale,
	})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict on stale write, got %v", err)
	}
}

func TestPostgres_DeleteActivity_CascadesEntries(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "cascade@example.com")
	a := parityActivity(t, store, uid, "Gym")

	started := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	ended := started.Add(time.Hour)
	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: started, EndedAt: &ended,
	}); err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}

	if err := store.DeleteActivity(context.Background(), uid, a.ID); err != nil {
		t.Fatalf("DeleteActivity: %v", err)
	}
	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 0 {
		t.Fatalf("expected 0 entries after cascade, got %d", len(items))
	}
}

func TestPostgres_CrossUserIsolation(t *testing.T) {
	store := newParityStore(t)
	uidA := parityUser(t, store, "owner-a@example.com")
	uidB := parityUser(t, store, "owner-b@example.com")
	a := parityActivity(t, store, uidA, "Private")

	if _, err := store.GetActivity(context.Background(), uidB, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user B must not see user A's activity, got %v", err)
	}
	if err := store.DeleteActivity(context.Background(), uidB, a.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user B must not delete user A's activity, got %v", err)
	}
}
