package db

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/migrations"
)

// PostgreSQL parity suite (R-007 / 1.1-API-007): the same critical entry/
// category semantics the SQLite store is tested against, executed against real
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
		TRUNCATE entry_categories, entries, categories,
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

func parityCategory(t *testing.T, store *PostgresStore, userID, name string) Category {
	t.Helper()
	c, created, err := store.CreateCategory(context.Background(), Category{
		ID: uuidV7(), UserID: userID, Name: name, Icon: "tag",
	})
	if err != nil {
		t.Fatalf("CreateCategory: %v", err)
	}
	if !created {
		t.Fatalf("CreateCategory: expected created=true for %q", name)
	}
	return c
}

func parityEntry(t *testing.T, store *PostgresStore, userID, text string, cats []CategoryTag, started time.Time) Entry {
	t.Helper()
	e, created, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: userID, ActivityText: text, Categories: cats, StartedAt: started,
	})
	if err != nil {
		t.Fatalf("CreateEntry %q: %v", text, err)
	}
	if !created {
		t.Fatalf("CreateEntry: expected created=true for %q", text)
	}
	return e
}

func TestPostgres_CreateCategory_IdempotentReplay(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "replay@example.com")

	c := Category{ID: uuidV7(), UserID: uid, Name: "Sport", Icon: "tag"}
	_, created, err := store.CreateCategory(context.Background(), c)
	if err != nil || !created {
		t.Fatalf("first create: created=%v err=%v", created, err)
	}
	_, created, err = store.CreateCategory(context.Background(), c)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if created {
		t.Fatal("replay of same id must return created=false")
	}
}

func TestPostgres_CreateCategory_NameCollision(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "collision@example.com")

	parityCategory(t, store, uid, "Sport")
	_, _, err := store.CreateCategory(context.Background(), Category{
		ID: uuidV7(), UserID: uid, Name: "sport", Icon: "tag",
	})
	if !errors.Is(err, ErrCategoryExists) {
		t.Fatalf("expected ErrCategoryExists, got %v", err)
	}
}

func TestPostgres_UpdateCategory_LWWConflict(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "lww@example.com")
	c := parityCategory(t, store, uid, "Sport")

	stale := c.UpdatedAt.Add(-time.Hour)
	name := "Renamed"
	_, err := store.UpdateCategory(context.Background(), uid, c.ID, CategoryPatch{
		Name: &name, UpdatedAt: stale,
	})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict on stale write, got %v", err)
	}
}

func TestPostgres_CrossUserIsolation(t *testing.T) {
	store := newParityStore(t)
	uidA := parityUser(t, store, "owner-a@example.com")
	uidB := parityUser(t, store, "owner-b@example.com")
	c := parityCategory(t, store, uidA, "Private")

	if _, err := store.GetCategory(context.Background(), uidB, c.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user B must not see user A's category, got %v", err)
	}
	if err := store.DeleteCategory(context.Background(), uidB, c.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("user B must not delete user A's category, got %v", err)
	}
}

// Parity: entries own their text/categories/notes; per-entry isolation.
func TestPostgres_EntryOwnsFields_Isolation(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-own@example.com")
	c1 := parityCategory(t, store, uid, "Sport")
	c2 := parityCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e1 := parityEntry(t, store, uid, "Gym", []CategoryTag{{ID: c1.ID}}, base)
	e2 := parityEntry(t, store, uid, "Gym", []CategoryTag{{ID: c2.ID}}, base.Add(time.Hour))

	// Retext/retag e1 only; e2 must not move.
	updated, err := store.UpdateEntry(context.Background(), uid, e1.ID, EntryPatch{
		ActivityText: ptr("GYM"),
		Notes:        ptr("notes-1"),
		CategoryIDs:  &[]CategoryTag{{ID: c2.ID}},
		UpdatedAt:    e1.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateEntry: %v", err)
	}
	if updated.ActivityText != "GYM" || updated.Notes != "notes-1" {
		t.Errorf("expected GYM/notes-1, got %q/%q", updated.ActivityText, updated.Notes)
	}
	got2, err := store.GetEntry(context.Background(), uid, e2.ID)
	if err != nil {
		t.Fatalf("GetEntry e2: %v", err)
	}
	if got2.ActivityText != "Gym" || got2.Notes != "" {
		t.Errorf("e2 must be unchanged, got %q/%q", got2.ActivityText, got2.Notes)
	}
	if len(got2.Categories) != 1 || got2.Categories[0].ID != c2.ID {
		t.Errorf("e2 categories must be unchanged, got %+v", got2.Categories)
	}
}

// Parity (D1/D5): recents group by exact activity_text — `Gym` ≠ `GYM` — with
// per-group newest wins, newest-first.
func TestPostgres_ListRecents_ExactTextIdentity(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-recents@example.com")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	parityEntry(t, store, uid, "Gym", nil, base)
	parityEntry(t, store, uid, "GYM", nil, base.Add(time.Hour))
	parityEntry(t, store, uid, "Gym", nil, base.Add(2*time.Hour))

	recents, err := store.ListRecents(context.Background(), uid, 6)
	if err != nil {
		t.Fatalf("ListRecents: %v", err)
	}
	if len(recents) != 2 {
		t.Fatalf("expected 2 exact-text groups, got %d: %+v", len(recents), recents)
	}
	if recents[0].ActivityText != "Gym" || recents[1].ActivityText != "GYM" {
		t.Errorf("expected newest-first [Gym GYM], got [%s %s]", recents[0].ActivityText, recents[1].ActivityText)
	}
	if !recents[0].StartedAt.Equal(base.Add(2 * time.Hour)) {
		t.Errorf("each group's newest entry wins, got %v", recents[0].StartedAt)
	}
}

// Parity (D7): a merge prunes unknown category ids and keeps the remainder.
func TestPostgres_UpdateEntry_PruneUnknownCategories(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-prune@example.com")
	c1 := parityCategory(t, store, uid, "Sport")
	c2 := parityCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := parityEntry(t, store, uid, "Gym", []CategoryTag{{ID: c1.ID}}, base)

	ids := []CategoryTag{{ID: c2.ID}, {ID: "unknown"}, {ID: c1.ID}, {ID: ""}, {ID: c2.ID}}
	updated, err := store.UpdateEntry(context.Background(), uid, e.ID, EntryPatch{
		CategoryIDs: &ids, UpdatedAt: e.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateEntry prune: %v", err)
	}
	if len(updated.Categories) != 2 || updated.Categories[0].ID != c2.ID || updated.Categories[1].ID != c1.ID {
		t.Errorf("expected pruned ordered [Work Sport], got %+v", updated.Categories)
	}
}

// Parity (category-management D5): association order is preserved in the
// response, and Category deletion leaves entries intact.
func TestPostgres_EntryCategories_OrderAndDeletePreservesEntries(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-join@example.com")

	var catIDs []string
	for _, name := range []string{"Work", "Health", "Travel"} {
		c := parityCategory(t, store, uid, name)
		catIDs = append(catIDs, c.ID)
	}

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym",
		Categories: []CategoryTag{{ID: catIDs[1]}, {ID: catIDs[0]}, {ID: catIDs[2]}},
		StartedAt:  base,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if len(e.Categories) != 3 ||
		e.Categories[0].ID != catIDs[1] || e.Categories[1].ID != catIDs[0] || e.Categories[2].ID != catIDs[2] {
		t.Fatalf("expected order [%s %s %s], got %+v", catIDs[1], catIDs[0], catIDs[2], e.Categories)
	}

	if err := store.DeleteCategory(context.Background(), uid, catIDs[0]); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}

	got, err := store.GetEntry(context.Background(), uid, e.ID)
	if err != nil {
		t.Fatalf("GetEntry after category delete: %v", err)
	}
	if len(got.Categories) != 2 {
		t.Errorf("expected 2 remaining tags, got %+v", got.Categories)
	}
	for _, tag := range got.Categories {
		if tag.ID == catIDs[0] {
			t.Errorf("deleted category still attached: %+v", got.Categories)
		}
	}
	if got.ActivityText != "Gym" {
		t.Errorf("entry text must survive category deletion, got %q", got.ActivityText)
	}
}

// Parity: modified_since filtering on entries.
func TestPostgres_ListEntries_ModifiedSince(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-entries-modified@example.com")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e1, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
	})
	if err != nil {
		t.Fatalf("CreateEntry 1: %v", err)
	}
	time.Sleep(5 * time.Millisecond)
	e2, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Read", StartedAt: base.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateEntry 2: %v", err)
	}

	cursor := e1.UpdatedAt
	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{ModifiedSince: &cursor})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 1 || items[0].ID != e2.ID {
		t.Errorf("expected only the newer entry, got %d items", len(items))
	}
}

// Parity: provenance persistence + duplicate-import rejection.
func TestPostgres_CreateEntry_ProvenanceAndDuplicateImport(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-provenance@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	ref := "interval-42"

	// Default provenance on entries created without it.
	e1, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if e1.Source != "manual" || e1.SourceRef != nil {
		t.Errorf("expected manual/nil provenance, got %q/%v", e1.Source, e1.SourceRef)
	}

	// Explicit provenance persists and round-trips.
	e2, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Read", StartedAt: base.Add(time.Hour),
		Source: "screentime", SourceRef: &ref,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	got, err := store.GetEntry(context.Background(), uid, e2.ID)
	if err != nil {
		t.Fatalf("GetEntry: %v", err)
	}
	if got.Source != "screentime" || got.SourceRef == nil || *got.SourceRef != ref {
		t.Errorf("round-trip: expected screentime/%s, got %q/%v", ref, got.Source, got.SourceRef)
	}

	// Duplicate (source, source_ref) is rejected.
	_, _, err = store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base.Add(2 * time.Hour),
		Source: "screentime", SourceRef: &ref,
	})
	if !errors.Is(err, ErrDuplicateImport) {
		t.Fatalf("expected ErrDuplicateImport, got %v", err)
	}
}

// Parity (category-management D5): a PATCH merge that touches joins inside one
// transaction rolls back the whole entry mutation on failure — no partial
// field/join state survives.
func TestPostgres_UpdateEntry_JoinRollsBackAtomically(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-rollback@example.com")

	cat := parityCategory(t, store, uid, "Sport")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym",
		Categories: []CategoryTag{{ID: cat.ID}}, StartedAt: base,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}

	text := "Renamed Gym"
	ids := []CategoryTag{{ID: cat.ID}, {ID: uuidV7()}} // second id does not exist
	if _, err := store.UpdateEntry(context.Background(), uid, e.ID, EntryPatch{
		ActivityText: &text,
		CategoryIDs:  &ids,
		UpdatedAt:    e.UpdatedAt.Add(time.Hour),
	}); err != nil {
		t.Fatalf("UpdateEntry with unknown id must prune, not fail: %v", err)
	}

	got, err := store.GetEntry(context.Background(), uid, e.ID)
	if err != nil {
		t.Fatalf("GetEntry: %v", err)
	}
	if got.ActivityText != "Renamed Gym" {
		t.Errorf("expected the text change to apply, got %q", got.ActivityText)
	}
	if len(got.Categories) != 1 || got.Categories[0].ID != cat.ID {
		t.Errorf("expected the unknown id pruned and the known id kept, got %+v", got.Categories)
	}
}

// Parity: every hard DELETE writes one tombstone; tombstones are
// entries/categories only — no resource can emit an activity tombstone.
func TestPostgres_DeleteWritesTombstones(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-tomb@example.com")

	c, _, err := store.CreateCategory(context.Background(), Category{
		ID: uuidV7(), UserID: uid, Name: "Sport", Icon: "tag",
	})
	if err != nil {
		t.Fatalf("CreateCategory: %v", err)
	}
	started := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: started,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}

	if err := store.DeleteEntry(context.Background(), uid, e.ID); err != nil {
		t.Fatalf("DeleteEntry: %v", err)
	}
	if err := store.DeleteCategory(context.Background(), uid, c.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}

	tombs, err := store.ListDeletions(context.Background(), uid, nil)
	if err != nil {
		t.Fatalf("ListDeletions: %v", err)
	}
	if len(tombs) != 2 {
		t.Fatalf("expected 2 tombstones, got %d: %+v", len(tombs), tombs)
	}
	byResource := map[string]Tombstone{}
	for _, tomb := range tombs {
		byResource[tomb.Resource] = tomb
	}
	for resource, wantID := range map[string]string{
		"category": c.ID, "entry": e.ID,
	} {
		tomb, ok := byResource[resource]
		if !ok {
			t.Errorf("expected a %s tombstone, got %+v", resource, tombs)
			continue
		}
		if tomb.ID != wantID {
			t.Errorf("%s tombstone: expected id %q, got %q", resource, wantID, tomb.ID)
		}
	}
}

// Parity: since-filter and ASC ordering on ListDeletions.
func TestPostgres_ListDeletions_SinceFilter(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-tomb-since@example.com")

	e1 := parityEntry(t, store, uid, "Gym", nil, time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC))
	time.Sleep(5 * time.Millisecond)
	e2 := parityEntry(t, store, uid, "Read", nil, time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC))

	if err := store.DeleteEntry(context.Background(), uid, e1.ID); err != nil {
		t.Fatalf("DeleteEntry 1: %v", err)
	}
	time.Sleep(5 * time.Millisecond)
	cursor := time.Now().UTC()
	time.Sleep(5 * time.Millisecond)
	if err := store.DeleteEntry(context.Background(), uid, e2.ID); err != nil {
		t.Fatalf("DeleteEntry 2: %v", err)
	}

	tombs, err := store.ListDeletions(context.Background(), uid, &cursor)
	if err != nil {
		t.Fatalf("ListDeletions: %v", err)
	}
	if len(tombs) != 1 || tombs[0].ID != e2.ID {
		t.Errorf("expected only the newer tombstone, got %+v", tombs)
	}

	future := cursor.Add(time.Hour)
	tombs, err = store.ListDeletions(context.Background(), uid, &future)
	if err != nil {
		t.Fatalf("ListDeletions future: %v", err)
	}
	if len(tombs) != 0 {
		t.Errorf("expected 0 tombstones with a future cursor, got %d", len(tombs))
	}

	tombs, err = store.ListDeletions(context.Background(), uid, nil)
	if err != nil {
		t.Fatalf("ListDeletions full: %v", err)
	}
	if len(tombs) != 2 || tombs[0].ID != e1.ID || tombs[1].ID != e2.ID {
		t.Errorf("expected full list oldest-first, got %+v", tombs)
	}
}

// Parity: recreating an id clears its tombstone; a double delete keeps the
// tombstone and returns ErrNotFound.
func TestPostgres_RecreateClearsAndDoubleDeleteKeeps(t *testing.T) {
	store := newParityStore(t)
	uid := parityUser(t, store, "pg-tomb-recreate@example.com")
	ctx := context.Background()

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := parityEntry(t, store, uid, "Gym", nil, base)
	if err := store.DeleteEntry(ctx, uid, e.ID); err != nil {
		t.Fatalf("DeleteEntry: %v", err)
	}
	// Recreate the same id clears the tombstone.
	if _, created, err := store.CreateEntry(ctx, Entry{
		ID: e.ID, UserID: uid, ActivityText: "Gym", StartedAt: base,
	}); err != nil || !created {
		t.Fatalf("recreate: created=%v err=%v", created, err)
	}
	tombs, err := store.ListDeletions(ctx, uid, nil)
	if err != nil {
		t.Fatalf("ListDeletions: %v", err)
	}
	if len(tombs) != 0 {
		t.Errorf("expected recreation to clear the tombstone, got %+v", tombs)
	}

	// Double delete: ErrNotFound, tombstone kept (re-created then deleted).
	if err := store.DeleteEntry(ctx, uid, e.ID); err != nil {
		t.Fatalf("DeleteEntry (recreated row): %v", err)
	}
	if err := store.DeleteEntry(ctx, uid, e.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound on second delete, got %v", err)
	}
	tombs, err = store.ListDeletions(ctx, uid, nil)
	if err != nil {
		t.Fatalf("ListDeletions 2: %v", err)
	}
	if len(tombs) != 1 || tombs[0].Resource != "entry" || tombs[0].ID != e.ID {
		t.Errorf("expected exactly one entry tombstone kept, got %+v", tombs)
	}
}

// Parity: tombstones are scoped per user.
func TestPostgres_ListDeletions_UserScoping(t *testing.T) {
	store := newParityStore(t)
	uidA := parityUser(t, store, "pg-tomb-a@example.com")
	uidB := parityUser(t, store, "pg-tomb-b@example.com")
	ctx := context.Background()

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	eA := parityEntry(t, store, uidA, "Mine", nil, base)
	eB := parityEntry(t, store, uidB, "Theirs", nil, base)
	if err := store.DeleteEntry(ctx, uidA, eA.ID); err != nil {
		t.Fatalf("DeleteEntry A: %v", err)
	}
	if err := store.DeleteEntry(ctx, uidB, eB.ID); err != nil {
		t.Fatalf("DeleteEntry B: %v", err)
	}

	tombsA, err := store.ListDeletions(ctx, uidA, nil)
	if err != nil {
		t.Fatalf("ListDeletions A: %v", err)
	}
	if len(tombsA) != 1 || tombsA[0].ID != eA.ID {
		t.Errorf("user A: expected only their tombstone, got %+v", tombsA)
	}
	tombsB, err := store.ListDeletions(ctx, uidB, nil)
	if err != nil {
		t.Fatalf("ListDeletions B: %v", err)
	}
	if len(tombsB) != 1 || tombsB[0].ID != eB.ID {
		t.Errorf("user B: expected only their tombstone, got %+v", tombsB)
	}
}

// TestPostgres_UpsertUserByAppleSubject exercises the SIWA upsert against real
// PostgreSQL: the conflict target must match the partial unique index
// (idx_users_apple_subject … WHERE apple_subject IS NOT NULL). Omitting the
// predicate fails with SQLSTATE 42P10 at runtime — a bug SQLite's
// INSERT OR IGNORE cannot reproduce.
func TestPostgres_UpsertUserByAppleSubject(t *testing.T) {
	store := newParityStore(t)
	ctx := context.Background()

	first, err := store.UpsertUserByAppleSubject(ctx, "apple-sub-parity", "relay@privaterelay.appleid.com")
	if err != nil {
		t.Fatalf("first upsert: %v", err)
	}
	if !first.EmailVerified {
		t.Error("expected email_verified=true on create")
	}

	// Same subject, email withheld (Apple's behavior on re-auth): same user,
	// original email retained, still verified.
	second, err := store.UpsertUserByAppleSubject(ctx, "apple-sub-parity", "")
	if err != nil {
		t.Fatalf("second upsert (conflict path): %v", err)
	}
	if second.ID != first.ID {
		t.Errorf("expected same user ID across sign-ins: %q vs %q", first.ID, second.ID)
	}
	if second.Email != first.Email {
		t.Errorf("expected retained email %q, got %q", first.Email, second.Email)
	}
	if !second.EmailVerified {
		t.Error("expected email_verified=true after conflict update")
	}
}
