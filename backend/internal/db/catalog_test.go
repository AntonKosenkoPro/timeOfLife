package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// newTestUser creates a user and returns its id, for scoping catalog rows.
func newTestUser(t *testing.T, store *SQLiteStore, email string) string {
	t.Helper()
	u, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	return u.ID
}

func mustCreateActivity(t *testing.T, store *SQLiteStore, userID, name string, categoryIDs []string) Activity {
	t.Helper()
	a, created, err := store.CreateActivity(context.Background(), Activity{
		ID: uuidV7(), UserID: userID, Name: name, Color: "blue", Icon: "figure.run",
	}, categoryIDs)
	if err != nil {
		t.Fatalf("CreateActivity: %v", err)
	}
	if !created {
		t.Fatalf("CreateActivity: expected created=true for %q", name)
	}
	return a
}

func mustCreateCategory(t *testing.T, store *SQLiteStore, userID, name string) Category {
	t.Helper()
	c, created, err := store.CreateCategory(context.Background(), Category{
		ID: uuidV7(), UserID: userID, Name: name, Color: "green",
	})
	if err != nil {
		t.Fatalf("CreateCategory: %v", err)
	}
	if !created {
		t.Fatalf("CreateCategory: expected created=true for %q", name)
	}
	return c
}

func TestStore_CreateAndGetActivity(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "act@example.com")

	cat := mustCreateCategory(t, store, uid, "Sport")
	a := mustCreateActivity(t, store, uid, "Gym", []string{cat.ID})

	got, err := store.GetActivity(context.Background(), uid, a.ID)
	if err != nil {
		t.Fatalf("GetActivity: %v", err)
	}
	if got.Name != "Gym" || got.Color != "blue" || got.Icon != "figure.run" {
		t.Errorf("unexpected activity: %+v", got)
	}
	if len(got.Categories) != 1 || got.Categories[0].ID != cat.ID {
		t.Errorf("expected 1 category tag, got %+v", got.Categories)
	}
	if got.Categories[0].Name != "Sport" {
		t.Errorf("expected tag name Sport, got %q", got.Categories[0].Name)
	}
}

func TestStore_CreateActivity_IdempotentReplay(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "idem@example.com")

	a := mustCreateActivity(t, store, uid, "Run", nil)
	replay, created, err := store.CreateActivity(context.Background(), Activity{
		ID: a.ID, UserID: uid, Name: "Run", Color: "red", Icon: "figure.walk",
	}, nil)
	if err != nil {
		t.Fatalf("replay CreateActivity: %v", err)
	}
	if created {
		t.Error("expected created=false on idempotent replay")
	}
	if replay.ID != a.ID || replay.Color != "blue" {
		t.Errorf("replay should return the original record, got %+v", replay)
	}
}

func TestStore_CreateActivity_NameCollision(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "collide@example.com")

	a := mustCreateActivity(t, store, uid, "Gym", nil)
	winner, created, err := store.CreateActivity(context.Background(), Activity{
		ID: uuidV7(), UserID: uid, Name: "gym", Color: "red", Icon: "figure.walk",
	}, nil)
	if !errors.Is(err, ErrActivityExists) {
		t.Fatalf("expected ErrActivityExists, got %v", err)
	}
	if created {
		t.Error("expected created=false on collision")
	}
	if winner.ID != a.ID {
		t.Errorf("expected winner to be the existing activity %q, got %q", a.ID, winner.ID)
	}
}

func TestStore_UpdateActivity_LWW(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "lww@example.com")
	a := mustCreateActivity(t, store, uid, "Read", nil)

	// Stale write (equal updated_at) → conflict.
	_, err := store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		Name: ptr("Reading"), UpdatedAt: a.UpdatedAt,
	})
	if !errors.Is(err, ErrConflict) {
		t.Fatalf("expected ErrConflict on stale write, got %v", err)
	}

	// Newer write → applies.
	newer := a.UpdatedAt.Add(time.Second)
	updated, err := store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		Name: ptr("Reading"), UpdatedAt: newer,
	})
	if err != nil {
		t.Fatalf("UpdateActivity: %v", err)
	}
	if updated.Name != "Reading" {
		t.Errorf("expected name Reading, got %q", updated.Name)
	}
	if !updated.UpdatedAt.Equal(newer) {
		t.Errorf("expected updated_at=%v, got %v", newer, updated.UpdatedAt)
	}
}

func TestStore_UpdateActivity_NameCollision(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "ucollide@example.com")
	mustCreateActivity(t, store, uid, "Gym", nil)
	a2 := mustCreateActivity(t, store, uid, "Run", nil)

	_, err := store.UpdateActivity(context.Background(), uid, a2.ID, ActivityPatch{
		Name: ptr("gym"), UpdatedAt: a2.UpdatedAt.Add(time.Second),
	})
	if !errors.Is(err, ErrActivityExists) {
		t.Fatalf("expected ErrActivityExists, got %v", err)
	}
}

func TestStore_UpdateActivity_ReplaceTags(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "tags@example.com")
	c1 := mustCreateCategory(t, store, uid, "Sport")
	c2 := mustCreateCategory(t, store, uid, "Work")
	a := mustCreateActivity(t, store, uid, "Gym", []string{c1.ID})

	// Replace with c2.
	ids := []string{c2.ID}
	updated, err := store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		CategoryIDs: &ids, UpdatedAt: a.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateActivity replace tags: %v", err)
	}
	if len(updated.Categories) != 1 || updated.Categories[0].ID != c2.ID {
		t.Errorf("expected only c2 tag, got %+v", updated.Categories)
	}

	// Invalid category id → ErrInvalidCategoryID.
	bad := []string{"not-a-real-id"}
	_, err = store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		CategoryIDs: &bad, UpdatedAt: a.UpdatedAt.Add(2 * time.Second),
	})
	if !errors.Is(err, ErrInvalidCategoryID) {
		t.Fatalf("expected ErrInvalidCategoryID, got %v", err)
	}
}

func TestStore_DeleteActivity_Cascades(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "cascade@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	a := mustCreateActivity(t, store, uid, "Gym", []string{cat.ID})

	_, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: time.Now().Add(-time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}

	if err := store.DeleteActivity(context.Background(), uid, a.ID); err != nil {
		t.Fatalf("DeleteActivity: %v", err)
	}

	if _, err := store.GetActivity(context.Background(), uid, a.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("expected activity gone, got %v", err)
	}
	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 0 {
		t.Errorf("expected entries cascaded away, got %d", len(items))
	}
}

func TestStore_DeleteCategory_RemovesJoinKeepsEntries(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "delcat@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	a := mustCreateActivity(t, store, uid, "Gym", []string{cat.ID})
	_, _, _ = store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: time.Now().Add(-time.Hour),
	})

	if err := store.DeleteCategory(context.Background(), uid, cat.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}
	got, err := store.GetActivity(context.Background(), uid, a.ID)
	if err != nil {
		t.Fatalf("GetActivity after category delete: %v", err)
	}
	if len(got.Categories) != 0 {
		t.Errorf("expected tag removed, got %+v", got.Categories)
	}
	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 1 {
		t.Errorf("expected entry retained, got %d", len(items))
	}
}

func TestStore_CategoryCRUD(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "cat@example.com")

	c := mustCreateCategory(t, store, uid, "Work")
	// Collision.
	if _, _, err := store.CreateCategory(context.Background(), Category{
		ID: uuidV7(), UserID: uid, Name: "work", Color: "red",
	}); !errors.Is(err, ErrCategoryExists) {
		t.Fatalf("expected ErrCategoryExists, got %v", err)
	}
	// Update.
	updated, err := store.UpdateCategory(context.Background(), uid, c.ID, CategoryPatch{
		Name: ptr("Job"), UpdatedAt: c.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateCategory: %v", err)
	}
	if updated.Name != "Job" {
		t.Errorf("expected name Job, got %q", updated.Name)
	}
	// Delete.
	if err := store.DeleteCategory(context.Background(), uid, c.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}
	if err := store.DeleteCategory(context.Background(), uid, c.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound on second delete, got %v", err)
	}
}

func TestStore_CreateEntry_SnapshotFromActivity(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "snap@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	a := mustCreateActivity(t, store, uid, "Gym", []string{cat.ID})

	start := time.Now().Add(-time.Hour)
	end := start.Add(time.Hour)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: start, EndedAt: &end,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if e.ActivityNameSnapshot != "Gym" {
		t.Errorf("expected snapshot 'Gym', got %q", e.ActivityNameSnapshot)
	}
	if !e.Linked || e.ActivityID == nil {
		t.Error("expected linked entry")
	}
	if e.DurationSeconds == nil || *e.DurationSeconds != 3600 {
		t.Errorf("expected duration 3600, got %v", e.DurationSeconds)
	}
	if len(e.Categories) != 1 || e.Categories[0].Name != "Sport" {
		t.Errorf("expected inferred Sport tag, got %+v", e.Categories)
	}
}

func TestStore_CreateEntry_FreeText(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "freetext@example.com")
	start := time.Now()
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityNameSnapshot: "Adhoc thing", StartedAt: start,
	})
	if err != nil {
		t.Fatalf("CreateEntry free text: %v", err)
	}
	if e.ActivityNameSnapshot != "Adhoc thing" {
		t.Errorf("expected snapshot 'Adhoc thing', got %q", e.ActivityNameSnapshot)
	}
	if e.Linked || e.ActivityID != nil {
		t.Error("expected unlinked free-text entry")
	}
	if e.EndedAt != nil {
		t.Error("expected running timer (nil ended_at)")
	}
}

func TestStore_CreateEntry_ActivityNotOwned(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "owner@example.com")
	other := newTestUser(t, store, "other@example.com")
	a := mustCreateActivity(t, store, other, "Their Gym", nil)

	_, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: time.Now(),
	})
	if !errors.Is(err, ErrActivityNotFound) {
		t.Fatalf("expected ErrActivityNotFound, got %v", err)
	}
}

func TestStore_UpdateEntry_StopsTimer(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "stop@example.com")
	// Whole-second UTC times: the SQLite TEXT timestamp format truncates
	// sub-seconds, so fixed times keep the round-trip exact.
	start := time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, StartedAt: start,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	end := start.Add(time.Hour)
	endedAt := NullableTime{Set: true, Valid: true, Value: end}
	updated, err := store.UpdateEntry(context.Background(), uid, e.ID, EntryPatch{
		EndedAt: endedAt, UpdatedAt: e.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateEntry: %v", err)
	}
	if updated.EndedAt == nil || !updated.EndedAt.Equal(end) {
		t.Errorf("expected ended_at=%v, got %v", end, updated.EndedAt)
	}
	if updated.DurationSeconds == nil || *updated.DurationSeconds != 3600 {
		t.Errorf("expected duration 3600, got %v", updated.DurationSeconds)
	}
}

func TestStore_UnlinkEntry_SnapshotsTags(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "unlink@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	a := mustCreateActivity(t, store, uid, "Gym", []string{cat.ID})
	start := time.Now().Add(-time.Hour)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: start,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}

	unlinked, err := store.UnlinkEntry(context.Background(), uid, e.ID)
	if err != nil {
		t.Fatalf("UnlinkEntry: %v", err)
	}
	if unlinked.Linked || unlinked.ActivityID != nil {
		t.Error("expected entry unlinked")
	}
	if len(unlinked.Categories) != 1 || unlinked.Categories[0].Name != "Sport" {
		t.Errorf("expected frozen Sport tag, got %+v", unlinked.Categories)
	}

	// Second unlink → conflict.
	if _, err := store.UnlinkEntry(context.Background(), uid, e.ID); !errors.Is(err, ErrConflict) {
		t.Errorf("expected ErrConflict on second unlink, got %v", err)
	}

	// The activity is unaffected.
	if _, err := store.GetActivity(context.Background(), uid, a.ID); err != nil {
		t.Errorf("activity should still exist, got %v", err)
	}
}

func TestStore_ListEntries_Pagination(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "page@example.com")
	base := time.Date(2026, 7, 1, 9, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		st := base.Add(time.Duration(i) * time.Hour)
		_, _, err := store.CreateEntry(context.Background(), Entry{
			ID: uuidV7(), UserID: uid, ActivityNameSnapshot: "x", StartedAt: st,
		})
		if err != nil {
			t.Fatalf("CreateEntry %d: %v", i, err)
		}
	}

	page1, next, err := store.ListEntries(context.Background(), uid, EntryFilter{Limit: 2})
	if err != nil {
		t.Fatalf("ListEntries page1: %v", err)
	}
	if len(page1) != 2 {
		t.Fatalf("expected 2 items, got %d", len(page1))
	}
	if next == "" {
		t.Fatal("expected next cursor")
	}
	// Newest first.
	if !page1[0].StartedAt.Equal(base.Add(4 * time.Hour)) {
		t.Errorf("expected newest first, got %v", page1[0].StartedAt)
	}

	page2, next2, err := store.ListEntries(context.Background(), uid, EntryFilter{Limit: 2, Cursor: next})
	if err != nil {
		t.Fatalf("ListEntries page2: %v", err)
	}
	if len(page2) != 2 {
		t.Fatalf("expected 2 items, got %d", len(page2))
	}
	if next2 == "" {
		t.Fatal("expected second next cursor")
	}

	page3, next3, err := store.ListEntries(context.Background(), uid, EntryFilter{Limit: 2, Cursor: next2})
	if err != nil {
		t.Fatalf("ListEntries page3: %v", err)
	}
	if len(page3) != 1 {
		t.Fatalf("expected 1 item on last page, got %d", len(page3))
	}
	if next3 != "" {
		t.Errorf("expected empty cursor on last page, got %q", next3)
	}
}

func TestStore_CrossUserIsolation(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	u1 := newTestUser(t, store, "u1@example.com")
	u2 := newTestUser(t, store, "u2@example.com")
	a := mustCreateActivity(t, store, u1, "Mine", nil)

	if _, err := store.GetActivity(context.Background(), u2, a.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("u2 should not see u1's activity, got %v", err)
	}
	if err := store.DeleteActivity(context.Background(), u2, a.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("u2 should not delete u1's activity, got %v", err)
	}
}

// ptr returns a pointer to s (helper for patch fields).
func ptr(s string) *string { return &s }
