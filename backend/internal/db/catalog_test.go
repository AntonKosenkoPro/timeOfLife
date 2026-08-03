package db

import (
	"context"
	"errors"
	"sync"
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
		ID: uuidV7(), UserID: userID, Name: name,
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
	if got.Name != "Gym" {
		t.Errorf("unexpected activity: %+v", got)
	}
	if len(got.Categories) != 1 || got.Categories[0].ID != cat.ID {
		t.Errorf("expected 1 category tag, got %+v", got.Categories)
	}
	if got.Categories[0].Name != "Sport" {
		t.Errorf("expected tag name Sport, got %q", got.Categories[0].Name)
	}
	if got.Categories[0].Icon != "tag" {
		t.Errorf("expected tag icon tag, got %q", got.Categories[0].Icon)
	}
}

func TestStore_CreateActivity_IdempotentReplay(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "idem@example.com")

	a := mustCreateActivity(t, store, uid, "Run", nil)
	replay, created, err := store.CreateActivity(context.Background(), Activity{
		ID: a.ID, UserID: uid, Name: "Run",
	}, nil)
	if err != nil {
		t.Fatalf("replay CreateActivity: %v", err)
	}
	if created {
		t.Error("expected created=false on idempotent replay")
	}
	if replay.ID != a.ID {
		t.Errorf("replay should return the original record, got %+v", replay)
	}
}

func TestStore_CreateActivity_NameCollision(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "collide@example.com")

	a := mustCreateActivity(t, store, uid, "Gym", nil)
	winner, created, err := store.CreateActivity(context.Background(), Activity{
		ID: uuidV7(), UserID: uid, Name: "gym",
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

func TestStore_ActivityCategoryPositionOrdering(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "ordered-tags@example.com")
	first := mustCreateCategory(t, store, uid, "First")
	second := mustCreateCategory(t, store, uid, "Second")
	a := mustCreateActivity(t, store, uid, "Gym", []string{second.ID, first.ID, second.ID})

	if len(a.Categories) != 2 || a.Categories[0].ID != second.ID || a.Categories[1].ID != first.ID {
		t.Fatalf("expected initial order [%s %s], got %+v", second.ID, first.ID, a.Categories)
	}

	ordered := []string{first.ID, second.ID}
	updated, err := store.UpdateActivity(context.Background(), uid, a.ID, ActivityPatch{
		CategoryIDs: &ordered, UpdatedAt: a.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateActivity reorder: %v", err)
	}
	if len(updated.Categories) != 2 || updated.Categories[0].ID != first.ID || updated.Categories[1].ID != second.ID {
		t.Errorf("expected reordered categories [%s %s], got %+v", first.ID, second.ID, updated.Categories)
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
		ID: uuidV7(), UserID: uid, Name: "work", Icon: "briefcase",
	}); !errors.Is(err, ErrCategoryExists) {
		t.Fatalf("expected ErrCategoryExists, got %v", err)
	}
	// Update.
	updated, err := store.UpdateCategory(context.Background(), uid, c.ID, CategoryPatch{
		Name: ptr("Job"), Icon: ptr("briefcase"), UpdatedAt: c.UpdatedAt.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateCategory: %v", err)
	}
	if updated.Name != "Job" {
		t.Errorf("expected name Job, got %q", updated.Name)
	}
	if updated.Icon != "briefcase" {
		t.Errorf("expected icon briefcase, got %q", updated.Icon)
	}
	// Delete.
	if err := store.DeleteCategory(context.Background(), uid, c.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}
	if err := store.DeleteCategory(context.Background(), uid, c.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound on second delete, got %v", err)
	}
}

func TestStore_CreateEntry_ResolvesActivityName(t *testing.T) {
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
	if e.ActivityName != "Gym" {
		t.Errorf("expected activity_name 'Gym', got %q", e.ActivityName)
	}
	if e.ActivityID == nil || *e.ActivityID != a.ID {
		t.Error("expected entry linked to the activity")
	}
	if e.DurationSeconds == nil || *e.DurationSeconds != 3600 {
		t.Errorf("expected duration 3600, got %v", e.DurationSeconds)
	}
	if len(e.Categories) != 1 || e.Categories[0].Name != "Sport" {
		t.Errorf("expected inferred Sport tag, got %+v", e.Categories)
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
	a := mustCreateActivity(t, store, uid, "Gym", nil)
	// Whole-second UTC times: the SQLite TEXT timestamp format truncates
	// sub-seconds, so fixed times keep the round-trip exact.
	start := time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: start,
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

func TestStore_ListEntries_Pagination(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "page@example.com")
	a := mustCreateActivity(t, store, uid, "Gym", nil)
	base := time.Date(2026, 7, 1, 9, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		st := base.Add(time.Duration(i) * time.Hour)
		_, _, err := store.CreateEntry(context.Background(), Entry{
			ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: st,
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

// F2: CreateEntry with an activity_id bumps the activity's last_used_at to the
// entry's started_at, without regressing it for historical entries.
func TestStore_CreateEntry_BumpsActivityLastUsedAt(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "bump@example.com")
	a := mustCreateActivity(t, store, uid, "Gym", nil)
	if a.LastUsedAt != nil {
		t.Fatalf("expected nil last_used_at on a new activity, got %v", a.LastUsedAt)
	}
	start := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: start,
	}); err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	got, err := store.GetActivity(context.Background(), uid, a.ID)
	if err != nil {
		t.Fatalf("GetActivity: %v", err)
	}
	if got.LastUsedAt == nil || !got.LastUsedAt.Equal(start) {
		t.Errorf("expected last_used_at=%v, got %v", start, got.LastUsedAt)
	}
	// A historical (earlier) entry must not regress last_used_at.
	earlier := start.Add(-2 * time.Hour)
	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: earlier,
	}); err != nil {
		t.Fatalf("CreateEntry earlier: %v", err)
	}
	got, err = store.GetActivity(context.Background(), uid, a.ID)
	if err != nil {
		t.Fatalf("GetActivity 2: %v", err)
	}
	if got.LastUsedAt == nil || !got.LastUsedAt.Equal(start) {
		t.Errorf("expected last_used_at to stay %v (no regression), got %v", start, got.LastUsedAt)
	}
}

// F3: a partial PATCH that moves ended_at before the existing started_at (or
// vice versa) must be rejected by the store rather than persisting a negative
// duration_seconds.
func TestStore_UpdateEntry_PartialPatchRejectsNegativeDuration(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "neg@example.com")
	a := mustCreateActivity(t, store, uid, "Gym", nil)
	start := time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC)
	end := start.Add(time.Hour)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: start, EndedAt: &end,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	// Move only ended_at to before the existing started_at.
	earlier := start.Add(-time.Hour)
	if _, err := store.UpdateEntry(context.Background(), uid, e.ID, EntryPatch{
		EndedAt:   NullableTime{Set: true, Valid: true, Value: earlier},
		UpdatedAt: e.UpdatedAt.Add(time.Second),
	}); !errors.Is(err, ErrEndBeforeStart) {
		t.Fatalf("expected ErrEndBeforeStart, got %v", err)
	}
	// Move only started_at to after the existing ended_at.
	later := end.Add(time.Hour)
	if _, err := store.UpdateEntry(context.Background(), uid, e.ID, EntryPatch{
		StartedAt: &later,
		UpdatedAt: e.UpdatedAt.Add(time.Second),
	}); !errors.Is(err, ErrEndBeforeStart) {
		t.Fatalf("expected ErrEndBeforeStart on started_at move, got %v", err)
	}
}

// F5: the `to` filter is an inclusive upper bound on started_at.
func TestStore_ListEntries_ToFilterInclusive(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "tofilter@example.com")
	a := mustCreateActivity(t, store, uid, "Gym", nil)
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	for i := 0; i < 3; i++ {
		st := base.Add(time.Duration(i) * time.Hour)
		if _, _, err := store.CreateEntry(context.Background(), Entry{
			ID: uuidV7(), UserID: uid, ActivityID: &a.ID, StartedAt: st,
		}); err != nil {
			t.Fatalf("CreateEntry %d: %v", i, err)
		}
	}
	to := base.Add(time.Hour) // 10:00 — exactly matches the middle entry.
	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{To: &to})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 2 { // 09:00 and 10:00 inclusive
		t.Errorf("expected 2 items (inclusive to), got %d", len(items))
	}
}

// F7: updating a missing entry returns ErrNotFound (contract guard for the
// concurrent-delete race, which re-checks existence on RowsAffected==0).
func TestStore_UpdateEntry_MissingReturnsNotFound(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "missing@example.com")
	_, err := store.UpdateEntry(context.Background(), uid, "does-not-exist", EntryPatch{
		UpdatedAt: time.Now(),
	})
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

// F8: a concurrent name collision that races past the pre-check must surface as
// ErrActivityExists (409), not a raw UNIQUE-constraint error (500). With a
// single pooled connection, the pre-check and INSERT release the connection
// between statements, so a burst of identical-name creates reliably reaches the
// INSERT-path UNIQUE violation.
func TestStore_CreateActivity_ConcurrentNameCollision(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "race@example.com")
	const n = 100
	var wg sync.WaitGroup
	errs := make([]error, n)
	created := make([]bool, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, isNew, err := store.CreateActivity(context.Background(), Activity{
				ID: uuidV7(), UserID: uid, Name: "Gym",
			}, nil)
			errs[i] = err
			created[i] = isNew
		}(i)
	}
	wg.Wait()
	createdCount := 0
	for i := 0; i < n; i++ {
		if created[i] {
			createdCount++
		}
		if errs[i] != nil && !errors.Is(errs[i], ErrActivityExists) {
			t.Errorf("goroutine %d: expected nil or ErrActivityExists, got %v", i, errs[i])
		}
	}
	if createdCount != 1 {
		t.Errorf("expected exactly 1 created activity, got %d", createdCount)
	}
}

// F8 (categories): same race contract for CreateCategory.
func TestStore_CreateCategory_ConcurrentNameCollision(t *testing.T) {
	store := setupTestStore(t)
	defer func() { _ = store.Close() }()
	uid := newTestUser(t, store, "catrace@example.com")
	const n = 100
	var wg sync.WaitGroup
	errs := make([]error, n)
	created := make([]bool, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, isNew, err := store.CreateCategory(context.Background(), Category{
				ID: uuidV7(), UserID: uid, Name: "Sport", Icon: "tag",
			})
			errs[i] = err
			created[i] = isNew
		}(i)
	}
	wg.Wait()
	createdCount := 0
	for i := 0; i < n; i++ {
		if created[i] {
			createdCount++
		}
		if errs[i] != nil && !errors.Is(errs[i], ErrCategoryExists) {
			t.Errorf("goroutine %d: expected nil or ErrCategoryExists, got %v", i, errs[i])
		}
	}
	if createdCount != 1 {
		t.Errorf("expected exactly 1 created category, got %d", createdCount)
	}
}
