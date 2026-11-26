package db

import (
	"context"
	"errors"
	"strings"
	"testing"
)

// Shared position-key allocator fixtures (mirrored in backend/api/openapi.yaml
// and the iOS allocator parity tests — all three must agree).
func TestPlanner_AllocatePositionKey_Fixtures(t *testing.T) {
	str := func(s string) *string { return &s }
	cases := []struct {
		name          string
		before, after *string
		want          string
	}{
		{"empty list", nil, nil, "500000"},
		{"append", str("500000"), nil, "500001"},
		{"append again", str("500001"), nil, "500002"},
		{"between", str("500000"), str("500001"), "500000.5"},
		{"between lower half", str("500000"), str("500000.5"), "500000.25"},
		{"between upper half", str("500000.5"), str("500001"), "500000.75"},
		{"prepend", nil, str("500000"), "499999"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := AllocatePositionKey(tc.before, tc.after)
			if err != nil {
				t.Fatalf("AllocatePositionKey: %v", err)
			}
			if got != tc.want {
				t.Fatalf("expected %q, got %q", tc.want, got)
			}
			if !ValidatePositionKey(got) {
				t.Fatalf("allocated key %q fails validation", got)
			}
		})
	}
}

func TestPlanner_ValidatePositionKey(t *testing.T) {
	valid := []string{"500000", "000000", "999999", "500000.5", "500000.25", "499999.000000000000000000000000000001"}
	for _, k := range valid {
		if !ValidatePositionKey(k) {
			t.Errorf("expected valid: %q", k)
		}
	}
	invalid := []string{"", "50000", "5000000", "500000.", "500000.50", "500000.0", "abc", "500000.5 ", "-1", "50000a", strings.Repeat("1", 40)}
	for _, k := range invalid {
		if ValidatePositionKey(k) {
			t.Errorf("expected invalid: %q", k)
		}
	}
}

func plannerUser(t *testing.T, store *SQLiteStore, email string) string {
	t.Helper()
	u, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	return u.ID
}

func plannerCreate(t *testing.T, store *SQLiteStore, userID, name, key string) PlannerTask {
	t.Helper()
	task, created, err := store.ApplyPlannerOperation(context.Background(), userID, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentCreate,
		Name: &name, PositionKey: &key,
	})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if !created {
		t.Fatal("expected created=true")
	}
	return task
}

func TestPlanner_CreateAssignsSequentialRevisions(t *testing.T) {
	store := setupTestStore(t)
	uid := plannerUser(t, store, "planner-seq@example.com")

	a := plannerCreate(t, store, uid, "Read", "500000")
	b := plannerCreate(t, store, uid, "Run", "500001")
	if a.Revision != 1 || b.Revision != 2 {
		t.Fatalf("expected revisions 1,2 got %d,%d", a.Revision, b.Revision)
	}
	if a.CompletedOn != nil || a.Deleted {
		t.Fatal("new task must be open and live")
	}
}

func TestPlanner_DedupReplayReturnsStoredState(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-dedup@example.com")

	opID, taskID := uuidV7(), uuidV7()
	name, key := "Read", "500000"
	first, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: opID, TaskID: taskID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil || !created {
		t.Fatalf("create: %v created=%v", err, created)
	}
	// Rename under a new operation, then replay the ORIGINAL create: the
	// replay must return the current state with no new revision.
	other, newName := uuidV7(), "Read books"
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: other, TaskID: taskID, Intent: PlannerIntentRename, Name: &newName,
	}); err != nil {
		t.Fatalf("rename: %v", err)
	}
	replayed, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: opID, TaskID: taskID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil {
		t.Fatalf("replay: %v", err)
	}
	if created {
		t.Fatal("replay must return created=false")
	}
	if replayed.Revision != 2 || replayed.Name != "Read books" {
		t.Fatalf("replay must return stored state, got %+v", replayed)
	}
	_ = first
}

func TestPlanner_IndependentFieldsCompose(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-fields@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	// Rename from one device, move from another, complete from a third: all
	// three field updates survive on the same task.
	newName, newKey, date := "Read books", "500001", "2026-11-25"
	for _, op := range []PlannerOperation{
		{OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRename, Name: &newName},
		{OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentMove, PositionKey: &newKey},
		{OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentComplete, CompletedOn: &date},
	} {
		if _, _, err := store.ApplyPlannerOperation(ctx, uid, op); err != nil {
			t.Fatalf("%s: %v", op.Intent, err)
		}
	}
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 4 || len(tasks) != 1 {
		t.Fatalf("expected watermark 4 with one task, got wm=%d n=%d", wm, len(tasks))
	}
	completed := tasks[0]
	if completed.CompletedOn == nil || *completed.CompletedOn != date {
		t.Fatalf("completion must persist, got %+v", completed)
	}
	// Reopen clears the date without touching name or position.
	open, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentReopen,
	})
	if err != nil {
		t.Fatalf("second reopen: %v", err)
	}
	if open.CompletedOn != nil || open.Name != newName || open.PositionKey != newKey {
		t.Fatalf("reopen must clear only the date, got %+v", open)
	}
}

func TestPlanner_ConflictingRenamesConvergeInAcceptanceOrder(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-order@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	first, second := "Alpha", "Beta"
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRename, Name: &first,
	}); err != nil {
		t.Fatalf("rename 1: %v", err)
	}
	last, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRename, Name: &second,
	})
	if err != nil {
		t.Fatalf("rename 2: %v", err)
	}
	if last.Name != second || last.Revision != 3 {
		t.Fatalf("latest accepted intent must win, got %+v", last)
	}
}

func TestPlanner_RetagOwnRevision(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-retag@example.com")

	// Create with an initial set: the response and the feed both carry it.
	catA, catB, catC := uuidV7(), uuidV7(), uuidV7()
	name, key := "Read", "500000"
	created, isNew, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentCreate,
		Name: &name, PositionKey: &key, CategoryIDs: []string{catA, catB},
	})
	if err != nil || !isNew {
		t.Fatalf("create with categories: %v %v", created, err)
	}
	if len(created.CategoryIDs) != 2 || created.CategoryIDs[0] != catA || created.CategoryIDs[1] != catB {
		t.Fatalf("create must carry the initial set, got %+v", created)
	}
	// A bare create defaults to the empty set.
	plain := plannerCreate(t, store, uid, "Plain", "500001")
	if len(plain.CategoryIDs) != 0 {
		t.Fatalf("bare create must default to empty, got %+v", plain)
	}

	// Retag replaces the ordered set with its own revision (per-account
	// revision 3 — the bare create above consumed 2), leaving the
	// name and position untouched.
	retagged, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: created.ID, Intent: PlannerIntentRetag,
		CategoryIDs: []string{catC},
	})
	if err != nil {
		t.Fatalf("retag: %v", err)
	}
	if retagged.Revision != 3 || len(retagged.CategoryIDs) != 1 || retagged.CategoryIDs[0] != catC {
		t.Fatalf("retag must replace the set with its own revision, got %+v", retagged)
	}
	if retagged.Name != "Read" || retagged.PositionKey != "500000" {
		t.Fatalf("retag must leave name and position untouched, got %+v", retagged)
	}
	// An empty retag clears the set (full replace, not a merge).
	cleared, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: created.ID, Intent: PlannerIntentRetag,
		CategoryIDs: []string{},
	})
	if err != nil || len(cleared.CategoryIDs) != 0 || cleared.Revision != 4 {
		t.Fatalf("empty retag must clear the set, got %+v %v", cleared, err)
	}
	// A later rename composes: the cleared set stays cleared.
	newName := "Read books"
	renamed, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: created.ID, Intent: PlannerIntentRename, Name: &newName,
	})
	if err != nil || renamed.Name != newName || len(renamed.CategoryIDs) != 0 {
		t.Fatalf("rename must compose with the retag, got %+v %v", renamed, err)
	}
	// The feed carries the latest set per task.
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 5 {
		t.Fatalf("expected watermark 5, got %d", wm)
	}
	for _, task := range tasks {
		if task.ID == created.ID && (len(task.CategoryIDs) != 0 || task.Name != "Read books") {
			t.Fatalf("feed must carry the latest retag state, got %+v", task)
		}
	}
}

func TestPlanner_RetagTerminalAndUnknown(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-retag-terminal@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	// A retag on the terminal marker is terminally refused.
	cat := uuidV7()
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRetag,
		CategoryIDs: []string{cat},
	}); !errors.Is(err, ErrPlannerGone) {
		t.Fatalf("expected ErrPlannerGone for retag after delete, got %v", err)
	}
	// Unknown ids are 404, not 410.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentRetag,
		CategoryIDs: []string{cat},
	}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for unknown retag, got %v", err)
	}
}

func TestPlanner_DeleteIsTerminal(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-terminal@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	deleted, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentDelete,
	})
	if err != nil || !created || !deleted.Deleted {
		t.Fatalf("delete: %v created=%v deleted=%+v", err, created, deleted)
	}
	// A delayed create for the same id is terminally refused.
	name, key := "Read again", "500001"
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	}); !errors.Is(err, ErrPlannerGone) {
		t.Fatalf("expected ErrPlannerGone for delayed create, got %v", err)
	}
	// Field ops on the deleted task are terminally refused too.
	newName := "Renamed"
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRename, Name: &newName,
	}); !errors.Is(err, ErrPlannerGone) {
		t.Fatalf("expected ErrPlannerGone for rename, got %v", err)
	}
	// Second delete (new op id) is replay-safe: terminal state, no revision.
	again, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentDelete,
	})
	if err != nil || created || !again.Deleted || again.Revision != deleted.Revision {
		t.Fatalf("second delete must be a no-op replay, got %+v created=%v err=%v", again, created, err)
	}
	// Unknown ids are 404, not 410.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentDelete,
	}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound for unknown id, got %v", err)
	}
}

func TestPlanner_CreateCollisionUnderDifferentOpID(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-collide@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	name, key := "Other", "500001"
	clash, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if !errors.Is(err, ErrPlannerConflict) {
		t.Fatalf("expected ErrPlannerConflict, got %v", err)
	}
	if created || clash.ID != task.ID || clash.Name != "Read" {
		t.Fatalf("conflict must return the server task, got %+v", clash)
	}
}

func TestPlanner_FeedPaginationAndWatermark(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-feed@example.com")

	// Five sequential creates land revisions 1..5.
	keys := []string{"500000", "500001", "500002", "500003", "500004"}
	var lastRev int64
	for i, name := range []string{"A", "B", "C", "D", "E"} {
		tk := plannerCreate(t, store, uid, name, keys[i])
		lastRev = tk.Revision
	}
	if lastRev != 5 {
		t.Fatalf("expected 5 revisions, got %d", lastRev)
	}
	// Page 1 (limit 2): revisions 1-2, hasMore.
	page1, wm, hasMore, err := store.ListPlannerFeed(ctx, uid, 0, 2)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 5 || !hasMore || len(page1) != 2 || page1[0].Revision != 1 || page1[1].Revision != 2 {
		t.Fatalf("page1 wrong: wm=%d hasMore=%v %+v", wm, hasMore, page1)
	}
	// Resume from the committed page: revisions 3-4, still more.
	page2, wm2, hasMore2, err := store.ListPlannerFeed(ctx, uid, page1[1].Revision, 2)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm2 != 5 || !hasMore2 || len(page2) != 2 || page2[0].Revision != 3 {
		t.Fatalf("page2 wrong: wm=%d hasMore=%v %+v", wm2, hasMore2, page2)
	}
	// Final page: revision 5 only, exhausted.
	page3, _, hasMore3, err := store.ListPlannerFeed(ctx, uid, page2[1].Revision, 2)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if hasMore3 || len(page3) != 1 || page3[0].Revision != 5 {
		t.Fatalf("page3 wrong: hasMore=%v %+v", hasMore3, page3)
	}
	// Feed includes terminally deleted tasks (not just visible Today rows).
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: page1[0].ID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	full, wmFull, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	// Five rows: the deletion rewrote task A's revision to 6, so the feed
	// carries latest-state-per-task (revisions 2..6), ending with A's
	// terminal marker.
	if wmFull != 6 || len(full) != 5 {
		t.Fatalf("feed must include the deletion marker: wm=%d n=%d", wmFull, len(full))
	}
	if !full[4].Deleted || full[4].ID != page1[0].ID || full[4].Revision != 6 {
		t.Fatalf("last change must be the deletion marker, got %+v", full[4])
	}
}

func TestPlanner_IsolationBetweenAccounts(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uidA := plannerUser(t, store, "planner-iso-a@example.com")
	uidB := plannerUser(t, store, "planner-iso-b@example.com")

	a := plannerCreate(t, store, uidA, "Read", "500000")
	if _, _, err := store.ApplyPlannerOperation(ctx, uidB, PlannerOperation{
		OperationID: uuidV7(), TaskID: a.ID, Intent: PlannerIntentDelete,
	}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("cross-account delete must 404, got %v", err)
	}
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uidB, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 0 || len(tasks) != 0 {
		t.Fatalf("account B must see nothing, got wm=%d n=%d", wm, len(tasks))
	}
	// Same task id under another account is a separate row.
	name, key := "Read", "500000"
	b, created, err := store.ApplyPlannerOperation(ctx, uidB, PlannerOperation{
		OperationID: uuidV7(), TaskID: a.ID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil || !created || b.Revision != 1 {
		t.Fatalf("per-account rows must be independent: %+v %v %v", b, created, err)
	}
}

func TestPlanner_WriterRacingPageBoundary(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-race@example.com")

	keys := []string{"500000", "500001", "500002"}
	for i, name := range []string{"A", "B", "C"} {
		plannerCreate(t, store, uid, name, keys[i])
	}
	// Page 1 fixes the committed watermark at 3.
	page1, wm1, hasMore1, err := store.ListPlannerFeed(ctx, uid, 0, 2)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm1 != 3 || !hasMore1 || len(page1) != 2 {
		t.Fatalf("page1 wrong: wm=%d hasMore=%v n=%d", wm1, hasMore1, len(page1))
	}
	// A concurrent writer commits revisions 4-5 while the client holds page 1.
	plannerCreate(t, store, uid, "D", "500003")
	plannerCreate(t, store, uid, "E", "500004")
	// Resuming from the committed page cursor picks up everything exactly
	// once: the racing writes are neither skipped nor duplicated.
	page2, wm2, hasMore2, err := store.ListPlannerFeed(ctx, uid, page1[1].Revision, 10)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm2 != 5 || hasMore2 {
		t.Fatalf("resume watermark must be 5 with no further pages, got wm=%d hasMore=%v", wm2, hasMore2)
	}
	var revs []int64
	for _, tk := range append(append([]PlannerTask{}, page1...), page2...) {
		revs = append(revs, tk.Revision)
	}
	want := []int64{1, 2, 3, 4, 5}
	if len(revs) != len(want) {
		t.Fatalf("resume must cover revisions 1-5 exactly once, got %v", revs)
	}
	for i := range want {
		if revs[i] != want[i] {
			t.Fatalf("resume must cover revisions 1-5 exactly once, got %v", revs)
		}
	}
	// A task rewritten past the previous watermark still converges: delete
	// A (rev 1→6) after the first pull, then pull from the old cursor —
	// A arrives with its terminal marker, never lost behind the cursor.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: page1[0].ID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	page3, _, _, err := store.ListPlannerFeed(ctx, uid, page1[1].Revision, 10)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	// Revisions 3,4,5 plus A's rewrite at 6 — latest-state-per-task.
	if len(page3) != 4 || page3[3].Revision != 6 || !page3[3].Deleted || page3[3].ID != page1[0].ID {
		t.Fatalf("superseded task must arrive with its marker: %+v", page3)
	}
}

func TestPlanner_PurgeRemovesPlannerState(t *testing.T) {
	store := setupTestStore(t)
	ctx := context.Background()
	uid := plannerUser(t, store, "planner-purge@example.com")

	task := plannerCreate(t, store, uid, "Read", "500000")
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := store.PurgeUser(ctx, uid, "", func(string) string { return "digest" }); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	// All planner state is gone with the account: a fresh account id sees an
	// empty feed, and the old task id is unknown (410 markers do not
	// outlive the purge).
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 0 || len(tasks) != 0 {
		t.Fatalf("purged account must have no planner state, got wm=%d n=%d", wm, len(tasks))
	}
}
