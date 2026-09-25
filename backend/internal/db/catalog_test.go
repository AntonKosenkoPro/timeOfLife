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

func mustCreateEntry(t *testing.T, store *SQLiteStore, userID, text string, cats []CategoryTag, startedAt time.Time) Entry {
	t.Helper()
	e, created, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: userID, ActivityText: text, Categories: cats, StartedAt: startedAt,
	})
	if err != nil {
		t.Fatalf("CreateEntry %q: %v", text, err)
	}
	if !created {
		t.Fatalf("CreateEntry: expected created=true for %q", text)
	}
	return e
}

func TestStore_CreateEntry_OwnsTextCategoriesNotes(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "own@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")

	start := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", Notes: "leg day",
		Categories: []CategoryTag{{ID: cat.ID}}, StartedAt: start,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if e.ActivityText != "Gym" || e.Notes != "leg day" {
		t.Errorf("expected Gym/leg day, got %q/%q", e.ActivityText, e.Notes)
	}
	if len(e.Categories) != 1 || e.Categories[0].ID != cat.ID || e.Categories[0].Name != "Sport" || e.Categories[0].Icon != "tag" {
		t.Errorf("expected own Sport tag, got %+v", e.Categories)
	}

	// Read back identically.
	got, err := store.GetEntry(context.Background(), uid, e.ID)
	if err != nil {
		t.Fatalf("GetEntry: %v", err)
	}
	if got.ActivityText != "Gym" || got.Notes != "leg day" {
		t.Errorf("round-trip mismatch: %q/%q", got.ActivityText, got.Notes)
	}
	if len(got.Categories) != 1 || got.Categories[0].ID != cat.ID {
		t.Errorf("round-trip categories mismatch: %+v", got.Categories)
	}
}

// Per-entry isolation: editing one entry's text, categories, or notes never
// touches another entry, even with the same exact text.
func TestStore_EntriesAreIsolated(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "isolated@example.com")
	c1 := mustCreateCategory(t, store, uid, "Sport")
	c2 := mustCreateCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e1 := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: c1.ID}}, base)
	e2 := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: c2.ID}}, base.Add(time.Hour))

	// Retext/retag e1 only.
	newer := e1.UpdatedAt.Add(time.Second)
	updated, err := store.UpdateEntry(context.Background(), uid, e1.ID, EntryPatch{
		ActivityText: ptr("GYM"),
		CategoryIDs:  &[]CategoryTag{{ID: c2.ID}},
		UpdatedAt:    newer,
	})
	if err != nil {
		t.Fatalf("UpdateEntry: %v", err)
	}
	if updated.ActivityText != "GYM" {
		t.Errorf("expected e1 text GYM, got %q", updated.ActivityText)
	}
	if len(updated.Categories) != 1 || updated.Categories[0].ID != c2.ID {
		t.Errorf("expected e1 tags replaced with Work, got %+v", updated.Categories)
	}

	// e2 unchanged.
	got2, err := store.GetEntry(context.Background(), uid, e2.ID)
	if err != nil {
		t.Fatalf("GetEntry e2: %v", err)
	}
	if got2.ActivityText != "Gym" {
		t.Errorf("e2 text must be unchanged, got %q", got2.ActivityText)
	}
	if len(got2.Categories) != 1 || got2.Categories[0].ID != c2.ID {
		t.Errorf("e2 categories must be unchanged, got %+v", got2.Categories)
	}
}

// Exact identity (D1): `Gym` and `GYM` are independent texts; recents group
// by exact activity_text, so they never merge.
func TestStore_Recents_ExactTextIdentity(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "case@example.com")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	mustCreateEntry(t, store, uid, "Gym", nil, base)
	mustCreateEntry(t, store, uid, "GYM", nil, base.Add(time.Hour))
	mustCreateEntry(t, store, uid, "Gym", nil, base.Add(2*time.Hour))

	recents, err := store.ListRecents(context.Background(), uid, 6)
	if err != nil {
		t.Fatalf("ListRecents: %v", err)
	}
	if len(recents) != 2 {
		t.Fatalf("expected 2 exact-text groups (Gym, GYM), got %d: %+v", len(recents), recents)
	}
	if recents[0].ActivityText != "Gym" || recents[1].ActivityText != "GYM" {
		t.Errorf("expected groups Gym then GYM (newest-first), got %q then %q",
			recents[0].ActivityText, recents[1].ActivityText)
	}
	if !recents[0].StartedAt.Equal(base.Add(2 * time.Hour)) {
		t.Errorf("each group's newest entry wins, got %v", recents[0].StartedAt)
	}
}

// Recents (D5): GROUP BY exact activity_text, per group the newest started_at
// wins with its ordered categories, ordered by that max DESC, LIMIT n.
func TestStore_ListRecents(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "recents@example.com")
	sport := mustCreateCategory(t, store, uid, "Sport")
	work := mustCreateCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	// Gym: newest entry at +3h carries its own categories.
	mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: sport.ID}}, base)
	mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: work.ID}}, base.Add(3*time.Hour))
	// Read: only one entry, older than Gym's newest but newer than nothing else.
	mustCreateEntry(t, store, uid, "Read", nil, base.Add(time.Hour))

	recents, err := store.ListRecents(context.Background(), uid, 6)
	if err != nil {
		t.Fatalf("ListRecents: %v", err)
	}
	if len(recents) != 2 {
		t.Fatalf("expected 2 recents, got %d", len(recents))
	}
	if recents[0].ActivityText != "Gym" || recents[1].ActivityText != "Read" {
		t.Errorf("expected newest-first [Gym Read], got [%s %s]", recents[0].ActivityText, recents[1].ActivityText)
	}
	if len(recents[0].Categories) != 1 || recents[0].Categories[0].ID != work.ID {
		t.Errorf("the winning entry's own categories come with it, got %+v", recents[0].Categories)
	}
	two, err := store.ListRecents(context.Background(), uid, 1)
	if err != nil {
		t.Fatalf("ListRecents limit: %v", err)
	}
	if len(two) != 1 || two[0].ActivityText != "Gym" {
		t.Errorf("expected only the newest group, got %+v", two)
	}
}

// Trim rule: `"Gym "` trims to `Gym` on write (no `"Gym "` ghosts); the raw
// case is preserved.
func TestStore_EntryTextTrimmedCasePreserved(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "trim@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := mustCreateEntry(t, store, uid, "  Gym  ", nil, base)
	if e.ActivityText != "Gym" {
		t.Errorf("expected trimmed Gym, got %q", e.ActivityText)
	}
	// Case preserved exactly.
	e2 := mustCreateEntry(t, store, uid, "GYM", nil, base.Add(time.Hour))
	if e2.ActivityText != "GYM" {
		t.Errorf("expected case preserved GYM, got %q", e2.ActivityText)
	}
}

// Create with an unknown category id: creates fail loudly (422 contract),
// unlike merges which prune.
func TestStore_CreateEntry_UnknownCategoryRejected(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "unknown-cat@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	_, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym",
		Categories: []CategoryTag{{ID: "missing"}}, StartedAt: base,
	})
	if !errors.Is(err, ErrInvalidCategoryID) {
		t.Fatalf("expected ErrInvalidCategoryID on create, got %v", err)
	}
}

// Prune rule (D7): a merge (PATCH with category_ids) drops unknown ids and
// keeps the remainder — never failing the cycle.
func TestStore_UpdateEntry_PruneUnknownCategories(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "prune@example.com")
	c1 := mustCreateCategory(t, store, uid, "Sport")
	c2 := mustCreateCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: c1.ID}}, base)

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

// Category deletion strips the category from entries but never deletes or
// modifies the entries themselves (their text/notes/timings stay intact).
func TestStore_DeleteCategory_RemovesJoinsKeepsEntries(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "delcat@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: cat.ID}}, base)

	if err := store.DeleteCategory(context.Background(), uid, cat.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}
	got, err := store.GetEntry(context.Background(), uid, e.ID)
	if err != nil {
		t.Fatalf("GetEntry after category delete: %v", err)
	}
	if len(got.Categories) != 0 {
		t.Errorf("expected join removed, got %+v", got.Categories)
	}
	if got.ActivityText != "Gym" || got.Notes != "" {
		t.Errorf("entry text/notes must survive category delete, got %q/%q", got.ActivityText, got.Notes)
	}
	if got.DurationSeconds != nil {
		t.Errorf("expected duration preserved (nil = running), got %v", got.DurationSeconds)
	}
}

// entry_categories cascade: deleting an entry removes its joins; deleting a
// category removes its joins — entries survive untagged.
func TestStore_EntryCategoriesCascade(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "cascade@example.com")
	cat := mustCreateCategory(t, store, uid, "Sport")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: cat.ID}}, base)

	// Recreate with the same id after delete must not resurrect stale joins.
	if err := store.DeleteEntry(context.Background(), uid, e.ID); err != nil {
		t.Fatalf("DeleteEntry: %v", err)
	}
	again := mustCreateEntry(t, store, uid, "Gym", nil, base)
	got, err := store.GetEntry(context.Background(), uid, again.ID)
	if err != nil {
		t.Fatalf("GetEntry: %v", err)
	}
	if len(got.Categories) != 0 {
		t.Errorf("recreated entry must start with no stale joins, got %+v", got.Categories)
	}

	if err := store.DeleteCategory(context.Background(), uid, cat.ID); err != nil {
		t.Fatalf("DeleteCategory: %v", err)
	}
	if _, err := store.GetEntry(context.Background(), uid, again.ID); err != nil {
		t.Errorf("entry must survive category deletion: %v", err)
	}
}

func TestStore_CategoryCRUD(t *testing.T) {
	store := setupTestStore(t)
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

func TestStore_UpdateEntry_StopsTimer(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "stop@example.com")
	// Whole-second UTC times: the SQLite TEXT timestamp format truncates
	// sub-seconds, so fixed times keep the round-trip exact.
	start := time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: start,
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
	uid := newTestUser(t, store, "page@example.com")
	base := time.Date(2026, 7, 1, 9, 0, 0, 0, time.UTC)
	for i := 0; i < 5; i++ {
		mustCreateEntry(t, store, uid, "Gym", nil, base.Add(time.Duration(i)*time.Hour))
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
	u1 := newTestUser(t, store, "u1@example.com")
	u2 := newTestUser(t, store, "u2@example.com")
	c := mustCreateCategory(t, store, u1, "Sport")

	if _, err := store.GetCategory(context.Background(), u2, c.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("u2 should not see u1's category, got %v", err)
	}
	if err := store.DeleteCategory(context.Background(), u2, c.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("u2 should not delete u1's category, got %v", err)
	}
}

// Cross-account id collision (fix-cross-account-id-collision): record ids are
// a global PRIMARY KEY while the id pre-check and the winner re-query are
// user-scoped. Reusing an id committed under another user answers
// ErrCategoryExists with a zero-value winner (the lookup misses), which the
// handler must surface as 409 with nil details — never {"id":"","name":""}.
func TestStore_CreateCategory_CrossUserIDCollision(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	u1 := newTestUser(t, store, "xcat-a@example.com")
	u2 := newTestUser(t, store, "xcat-b@example.com")
	id := uuidV7()

	if _, _, err := store.CreateCategory(ctx, Category{
		ID: id, UserID: u1, Name: "Sport", Icon: "tag",
	}); err != nil {
		t.Fatalf("user A create: %v", err)
	}
	// Distinct name: the failure is purely the global id collision.
	winner, _, err := store.CreateCategory(ctx, Category{
		ID: id, UserID: u2, Name: "Other", Icon: "briefcase",
	})
	if !errors.Is(err, ErrCategoryExists) {
		t.Fatalf("expected ErrCategoryExists, got %v", err)
	}
	if winner.ID != "" || winner.Name != "" {
		t.Errorf("cross-user winner lookup must miss (zero winner for nil details), got %+v", winner)
	}
}

// Cross-user entry id collision (fix-cross-account-id-collision): the same
// global-PK trip the client disambiguation relies on. The push maps to
// ErrDuplicateImport (409) while GetEntry as the second user answers
// ErrNotFound (404) — the row belongs to the other user.
func TestStore_CreateEntry_CrossUserIDCollision(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	u1 := newTestUser(t, store, "xentry-a@example.com")
	u2 := newTestUser(t, store, "xentry-b@example.com")
	id := uuidV7()
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)

	if _, _, err := store.CreateEntry(ctx, Entry{
		ID: id, UserID: u1, ActivityText: "Gym", StartedAt: base,
	}); err != nil {
		t.Fatalf("user A create: %v", err)
	}
	if _, _, err := store.CreateEntry(ctx, Entry{
		ID: id, UserID: u2, ActivityText: "Read", StartedAt: base.Add(time.Hour),
	}); !errors.Is(err, ErrDuplicateImport) {
		t.Fatalf("expected ErrDuplicateImport, got %v", err)
	}
	if _, err := store.GetEntry(ctx, u2, id); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for the second user, got %v", err)
	}
}

// ptr returns a pointer to s (helper for patch fields).
func ptr(s string) *string { return &s }

// F3: a partial PATCH that moves ended_at before the existing started_at (or
// vice versa) must be rejected by the store rather than persisting a negative
// duration_seconds.
func TestStore_UpdateEntry_PartialPatchRejectsNegativeDuration(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "neg@example.com")
	start := time.Date(2026, 7, 27, 10, 0, 0, 0, time.UTC)
	end := start.Add(time.Hour)
	e, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: start, EndedAt: &end,
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
	uid := newTestUser(t, store, "tofilter@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	for i := 0; i < 3; i++ {
		mustCreateEntry(t, store, uid, "Gym", nil, base.Add(time.Duration(i)*time.Hour))
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
	uid := newTestUser(t, store, "missing@example.com")
	_, err := store.UpdateEntry(context.Background(), uid, "does-not-exist", EntryPatch{
		UpdatedAt: time.Now(),
	})
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

// Delta pull-sync: ListEntries with ModifiedSince returns only entries whose
// updated_at is newer than the cursor.
func TestStore_ListEntries_ModifiedSince(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "entries-modified@example.com")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	e1, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
	})
	if err != nil {
		t.Fatalf("CreateEntry 1: %v", err)
	}
	e2, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Read", StartedAt: base.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateEntry 2: %v", err)
	}

	// Pin distinct updated_at values (LWW requires newer-than-stored): e1 at
	// T+1s, e2 at T+2s, cursor at T+1s.
	now := time.Now().UTC().Truncate(time.Second)
	t1 := now.Add(time.Second)
	t2 := now.Add(2 * time.Second)
	if _, err := store.UpdateEntry(context.Background(), uid, e1.ID, EntryPatch{
		UpdatedAt: t1,
	}); err != nil {
		t.Fatalf("pin e1: %v", err)
	}
	if _, err := store.UpdateEntry(context.Background(), uid, e2.ID, EntryPatch{
		UpdatedAt: t2,
	}); err != nil {
		t.Fatalf("pin e2: %v", err)
	}

	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{ModifiedSince: &t1})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 1 || items[0].ID != e2.ID {
		t.Errorf("expected only the newer entry, got %d items", len(items))
	}

	// An update bumps updated_at and must be picked up by a delta pull.
	ended := base.Add(2 * time.Hour)
	updated, err := store.UpdateEntry(context.Background(), uid, e1.ID, EntryPatch{
		EndedAt: NullableTime{Set: true, Valid: true, Value: ended}, UpdatedAt: t2.Add(time.Second),
	})
	if err != nil {
		t.Fatalf("UpdateEntry: %v", err)
	}
	items, _, err = store.ListEntries(context.Background(), uid, EntryFilter{ModifiedSince: &t1})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 2 {
		t.Errorf("expected 2 items after update, got %d", len(items))
	}
	if items[0].ID != updated.ID && items[1].ID != updated.ID {
		t.Errorf("expected the updated entry in the delta, got %+v", items)
	}
}

// ListEntries category filter re-points through entry_categories.
func TestStore_ListEntries_CategoryFilter(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "catfilter@example.com")
	sport := mustCreateCategory(t, store, uid, "Sport")
	work := mustCreateCategory(t, store, uid, "Work")

	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	tagged := mustCreateEntry(t, store, uid, "Gym", []CategoryTag{{ID: sport.ID}}, base)
	mustCreateEntry(t, store, uid, "Read", []CategoryTag{{ID: work.ID}}, base.Add(time.Hour))

	items, _, err := store.ListEntries(context.Background(), uid, EntryFilter{CategoryID: sport.ID})
	if err != nil {
		t.Fatalf("ListEntries: %v", err)
	}
	if len(items) != 1 || items[0].ID != tagged.ID {
		t.Errorf("expected only the Sport-tagged entry, got %+v", items)
	}
}

// Provenance: entries created without source/source_ref default to
// manual/null (back-compat); entries created with them persist them.
func TestStore_CreateEntry_ProvenanceDefaultsAndPersistence(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "provenance@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)

	// No provenance → manual/null.
	e1, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if e1.Source != "manual" {
		t.Errorf("expected default source manual, got %q", e1.Source)
	}
	if e1.SourceRef != nil {
		t.Errorf("expected nil source_ref, got %q", *e1.SourceRef)
	}

	// Explicit provenance persists.
	ref := "callback-123"
	e2, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Read", StartedAt: base.Add(time.Hour),
		Source: "screentime", SourceRef: &ref,
	})
	if err != nil {
		t.Fatalf("CreateEntry: %v", err)
	}
	if e2.Source != "screentime" || e2.SourceRef == nil || *e2.SourceRef != ref {
		t.Errorf("expected screentime/%s, got %q/%v", ref, e2.Source, e2.SourceRef)
	}

	// Round-trip through GetEntry.
	got, err := store.GetEntry(context.Background(), uid, e2.ID)
	if err != nil {
		t.Fatalf("GetEntry: %v", err)
	}
	if got.Source != "screentime" || got.SourceRef == nil || *got.SourceRef != ref {
		t.Errorf("round-trip: expected screentime/%s, got %q/%v", ref, got.Source, got.SourceRef)
	}
}

// Duplicate import prevention: a second create with the same
// (user_id, source, source_ref) is rejected by the partial unique index.
func TestStore_CreateEntry_DuplicateImportRejected(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "dup-import@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	ref := "interval-42"

	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
		Source: "screentime", SourceRef: &ref,
	}); err != nil {
		t.Fatalf("first create: %v", err)
	}
	_, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base.Add(time.Hour),
		Source: "screentime", SourceRef: &ref,
	})
	if !errors.Is(err, ErrDuplicateImport) {
		t.Fatalf("expected ErrDuplicateImport, got %v", err)
	}

	// Same source_ref with a different source is allowed (distinct provenance).
	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base.Add(2 * time.Hour),
		Source: "garmin", SourceRef: &ref,
	}); err != nil {
		t.Fatalf("different source, same ref must be allowed: %v", err)
	}

	// Null source_ref rows are exempt from the constraint (manual entries).
	if _, _, err := store.CreateEntry(context.Background(), Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base.Add(3 * time.Hour),
	}); err != nil {
		t.Fatalf("manual entry must not collide: %v", err)
	}
}

// Idempotent replay with provenance: replaying the same id returns the
// existing record (with its provenance) and does not create a duplicate.
func TestStore_CreateEntry_IdempotentReplayWithProvenance(t *testing.T) {
	store := setupTestStore(t)
	uid := newTestUser(t, store, "replay-provenance@example.com")
	base := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	ref := "garmin-activity-7"

	e := Entry{
		ID: uuidV7(), UserID: uid, ActivityText: "Gym", StartedAt: base,
		Source: "garmin", SourceRef: &ref,
	}
	created, isNew, err := store.CreateEntry(context.Background(), e)
	if err != nil || !isNew {
		t.Fatalf("first create: isNew=%v err=%v", isNew, err)
	}
	replayed, isNew, err := store.CreateEntry(context.Background(), e)
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if isNew {
		t.Fatal("replay must return created=false")
	}
	if replayed.Source != "garmin" || replayed.SourceRef == nil || *replayed.SourceRef != ref {
		t.Errorf("replay must return the stored provenance, got %q/%v", replayed.Source, replayed.SourceRef)
	}
	if replayed.ID != created.ID {
		t.Errorf("replay must return the same record, got %q vs %q", replayed.ID, created.ID)
	}
}

// F8 (categories): same race contract for CreateCategory.
func TestStore_CreateCategory_ConcurrentNameCollision(t *testing.T) {
	store := setupTestStore(t)
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
