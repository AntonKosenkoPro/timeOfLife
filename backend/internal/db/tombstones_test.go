package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// mustDelete runs a delete and fails the test on error.
func mustDelete(t *testing.T, err error, what string) {
	t.Helper()
	if err != nil {
		t.Fatalf("%s: %v", what, err)
	}
}

// mustListDeletions runs ListDeletions and fails the test on error.
func mustListDeletions(t *testing.T, store *SQLiteStore, userID string, since *time.Time) []Tombstone {
	t.Helper()
	out, err := store.ListDeletions(context.Background(), userID, since)
	if err != nil {
		t.Fatalf("ListDeletions: %v", err)
	}
	return out
}

// Every hard DELETE (category, entry — the only tombstoned resources now)
// records one tombstone.
func TestStore_DeleteWritesTombstone(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "tomb@example.com")

	c := mustCreateCategory(t, store, uid, "Sport")
	e := mustCreateEntry(t, store, uid, "Gym", nil, time.Now().Add(-time.Hour))

	before := mustListDeletions(t, store, uid, nil)
	if len(before) != 0 {
		t.Fatalf("expected no tombstones before deletes, got %d", len(before))
	}

	mustDelete(t, store.DeleteEntry(context.Background(), uid, e.ID), "DeleteEntry")
	mustDelete(t, store.DeleteCategory(context.Background(), uid, c.ID), "DeleteCategory")

	got := mustListDeletions(t, store, uid, nil)
	if len(got) != 2 {
		t.Fatalf("expected 2 tombstones, got %d: %+v", len(got), got)
	}
	byResource := map[string]Tombstone{}
	for _, tomb := range got {
		byResource[tomb.Resource] = tomb
	}
	for resource, wantID := range map[string]string{
		"category": c.ID, "entry": e.ID,
	} {
		tomb, ok := byResource[resource]
		if !ok {
			t.Errorf("expected a %s tombstone, got %+v", resource, got)
			continue
		}
		if tomb.ID != wantID {
			t.Errorf("%s tombstone: expected id %q, got %q", resource, wantID, tomb.ID)
		}
		if tomb.DeletedAt.IsZero() {
			t.Errorf("%s tombstone: expected non-zero deleted_at", resource)
		}
	}
}

// Delta pull-sync: ListDeletions with a non-nil since returns only tombstones
// strictly newer than the cursor; nil/zero = full list.
func TestStore_ListDeletions_SinceFilter(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "tomb-since@example.com")

	e1 := mustCreateEntry(t, store, uid, "Gym", nil, time.Now().Add(-2*time.Hour))
	e2 := mustCreateEntry(t, store, uid, "Read", nil, time.Now().Add(-time.Hour))

	// Delete e1, then wait past the SQLite second-precision timestamp, then e2.
	mustDelete(t, store.DeleteEntry(context.Background(), uid, e1.ID), "DeleteEntry 1")
	time.Sleep(1100 * time.Millisecond)
	cursor := time.Now().UTC().Truncate(time.Second)
	time.Sleep(1100 * time.Millisecond)
	mustDelete(t, store.DeleteEntry(context.Background(), uid, e2.ID), "DeleteEntry 2")

	after := mustListDeletions(t, store, uid, &cursor)
	if len(after) != 1 || after[0].ID != e2.ID {
		t.Errorf("expected only the newer tombstone, got %+v", after)
	}

	// A future cursor returns nothing.
	future := cursor.Add(time.Hour)
	items := mustListDeletions(t, store, uid, &future)
	if len(items) != 0 {
		t.Errorf("expected 0 tombstones with a future cursor, got %d", len(items))
	}

	// Nil since = full list, ordered by deleted_at ASC.
	full := mustListDeletions(t, store, uid, nil)
	if len(full) != 2 || full[0].ID != e1.ID || full[1].ID != e2.ID {
		t.Errorf("expected full list oldest-first, got %+v", full)
	}

	// Zero since = full list too.
	zero := time.Time{}
	zeroList := mustListDeletions(t, store, uid, &zero)
	if len(zeroList) != 2 {
		t.Errorf("expected 2 tombstones with a zero cursor, got %d", len(zeroList))
	}
}

// Recreating an id clears its tombstone so a recreation never meets its own
// stale tombstone.
func TestStore_RecreateClearsTombstone(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "tomb-recreate@example.com")
	ctx := context.Background()

	e := mustCreateEntry(t, store, uid, "Gym", nil, time.Now().Add(-time.Hour))
	mustDelete(t, store.DeleteEntry(ctx, uid, e.ID), "DeleteEntry")
	if _, created, err := store.CreateEntry(ctx, Entry{
		ID: e.ID, UserID: uid, ActivityText: "Gym", StartedAt: time.Now().Add(-time.Hour),
	}); err != nil || !created {
		t.Fatalf("recreate entry: created=%v err=%v", created, err)
	}
	if got := mustListDeletions(t, store, uid, nil); len(got) != 0 {
		t.Errorf("expected recreation to clear the entry tombstone, got %+v", got)
	}

	// Same for a category.
	c := mustCreateCategory(t, store, uid, "Sport")
	mustDelete(t, store.DeleteCategory(ctx, uid, c.ID), "DeleteCategory")
	if _, created, err := store.CreateCategory(ctx, Category{
		ID: c.ID, UserID: uid, Name: "Sport", Icon: "tag",
	}); err != nil || !created {
		t.Fatalf("recreate category: created=%v err=%v", created, err)
	}
	if got := mustListDeletions(t, store, uid, nil); len(got) != 0 {
		t.Errorf("expected recreation to clear the category tombstone, got %+v", got)
	}
}

// A second delete of an already-deleted id returns ErrNotFound and does NOT
// create a tombstone (the first delete's tombstone is kept, not duplicated).
func TestStore_DoubleDeleteKeepsTombstone(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "tomb-double@example.com")
	ctx := context.Background()

	e := mustCreateEntry(t, store, uid, "Gym", nil, time.Now().Add(-time.Hour))
	c := mustCreateCategory(t, store, uid, "Sport")
	mustDelete(t, store.DeleteEntry(ctx, uid, e.ID), "DeleteEntry")
	if err := store.DeleteEntry(ctx, uid, e.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("entry: expected ErrNotFound on second delete, got %v", err)
	}
	mustDelete(t, store.DeleteCategory(ctx, uid, c.ID), "DeleteCategory")
	if err := store.DeleteCategory(ctx, uid, c.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("category: expected ErrNotFound on second delete, got %v", err)
	}
	got := mustListDeletions(t, store, uid, nil)
	if len(got) != 2 {
		t.Fatalf("expected 2 tombstones (entry, category), got %+v", got)
	}
}

// Tombstone resources are entries and categories only: no delete path can
// emit an activity tombstone any more.
func TestStore_TombstoneResourcesEntriesCategoriesOnly(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "tomb-resources@example.com")
	ctx := context.Background()

	c := mustCreateCategory(t, store, uid, "Sport")
	e := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: c.ID}}, time.Now().Add(-time.Hour))

	mustDelete(t, store.DeleteEntry(ctx, uid, e.ID), "DeleteEntry")
	mustDelete(t, store.DeleteCategory(ctx, uid, c.ID), "DeleteCategory")

	got := mustListDeletions(t, store, uid, nil)
	for _, tomb := range got {
		if tomb.Resource != "entry" && tomb.Resource != "category" {
			t.Errorf("unexpected tombstone resource %q: %+v", tomb.Resource, tomb)
		}
	}
}

// Tombstones are scoped per user: deleting another user's records never leaks
// tombstones across user boundaries.
func TestStore_ListDeletions_UserScoping(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uidA := newTestUser(t, store, "tomb-a@example.com")
	uidB := newTestUser(t, store, "tomb-b@example.com")

	eA := mustCreateEntry(t, store, uidA, "Mine", nil, time.Now().Add(-time.Hour))
	eB := mustCreateEntry(t, store, uidB, "Theirs", nil, time.Now().Add(-time.Hour))
	mustDelete(t, store.DeleteEntry(ctx, uidA, eA.ID), "DeleteEntry A")
	mustDelete(t, store.DeleteEntry(ctx, uidB, eB.ID), "DeleteEntry B")

	gotA := mustListDeletions(t, store, uidA, nil)
	if len(gotA) != 1 || gotA[0].ID != eA.ID {
		t.Errorf("user A: expected only their tombstone, got %+v", gotA)
	}
	gotB := mustListDeletions(t, store, uidB, nil)
	if len(gotB) != 1 || gotB[0].ID != eB.ID {
		t.Errorf("user B: expected only their tombstone, got %+v", gotB)
	}
}
