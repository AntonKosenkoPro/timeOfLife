package db

import (
	"context"
	"errors"
	"testing"
)

// PostgreSQL planner parity: the same acceptance, dedup, terminality, feed,
// isolation, and purge semantics the SQLite store is tested against,
// executed against real PostgreSQL so SQLite-only CI cannot mask
// production behavior drift (planner_seq locking, DATE handling, receipt
// races).
//
// Gated on TEST_PG_DSN like the rest of the parity suite — `make test:pg`
// sets it against docker-compose. When unset, every test here skips and
// `go test ./...` stays green offline.

func parityPlannerUser(t *testing.T, store *PostgresStore, email string) string {
	t.Helper()
	u, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	return u.ID
}

func TestPostgres_PlannerAcceptDedupTerminal(t *testing.T) {
	store := newParityStore(t)
	ctx := context.Background()
	uid := parityPlannerUser(t, store, "pg-planner@example.com")

	taskID, opID := uuidV7(), uuidV7()
	name, key := "Read", "500000"
	task, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: opID, TaskID: taskID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil || !created || task.Revision != 1 {
		t.Fatalf("create: %+v %v %v", task, created, err)
	}
	// Lost-response replay returns the stored revision without reapplying.
	replayed, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: opID, TaskID: taskID, Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil || created || replayed.Revision != 1 {
		t.Fatalf("replay: %+v %v %v", replayed, created, err)
	}
	// Delete is terminal: a delayed create for the same id is refused.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: taskID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	other, otherKey := "Resurrect", "500001"
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: taskID, Intent: PlannerIntentCreate, Name: &other, PositionKey: &otherKey,
	}); !errors.Is(err, ErrPlannerGone) {
		t.Fatalf("expected ErrPlannerGone, got %v", err)
	}
	// Unknown ids stay 404; accounts stay isolated.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentDelete,
	}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
	uidB := parityPlannerUser(t, store, "pg-planner-b@example.com")
	if _, _, err := store.ApplyPlannerOperation(ctx, uidB, PlannerOperation{
		OperationID: uuidV7(), TaskID: taskID, Intent: PlannerIntentRename, Name: &other,
	}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("cross-account op must 404, got %v", err)
	}
}

func TestPostgres_PlannerFeedAndCivilDate(t *testing.T) {
	store := newParityStore(t)
	ctx := context.Background()
	uid := parityPlannerUser(t, store, "pg-planner-feed@example.com")

	keys := []string{"500000", "500001"}
	for i, name := range []string{"A", "B"} {
		n, k := name, keys[i]
		if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
			OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentCreate, Name: &n, PositionKey: &k,
		}); err != nil {
			t.Fatalf("create: %v", err)
		}
	}
	tasks, wm, hasMore, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 2 || hasMore || len(tasks) != 2 || tasks[0].Revision != 1 || tasks[1].Revision != 2 {
		t.Fatalf("feed wrong: wm=%d hasMore=%v %+v", wm, hasMore, tasks)
	}
	// The civil completion date round-trips as a date on Postgres too.
	date := "2026-11-25"
	done, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: tasks[0].ID, Intent: PlannerIntentComplete, CompletedOn: &date,
	})
	if err != nil {
		t.Fatalf("complete: %v", err)
	}
	if done.CompletedOn == nil || *done.CompletedOn != date {
		t.Fatalf("completion date must round-trip, got %+v", done)
	}
}

func TestPostgres_PlannerRetagParity(t *testing.T) {
	store := newParityStore(t)
	ctx := context.Background()
	uid := parityPlannerUser(t, store, "pg-planner-retag@example.com")

	// Create with an initial set, then retag: the ordered set round-trips
	// the JSON TEXT column on Postgres exactly like SQLite.
	catA, catB := uuidV7(), uuidV7()
	name, key := "Read", "500000"
	task, created, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentCreate,
		Name: &name, PositionKey: &key, CategoryIDs: []string{catA, catB},
	})
	if err != nil || !created {
		t.Fatalf("create with categories: %+v %v %v", task, created, err)
	}
	if len(task.CategoryIDs) != 2 || task.CategoryIDs[0] != catA || task.CategoryIDs[1] != catB {
		t.Fatalf("create must carry the initial set, got %+v", task)
	}
	retagged, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRetag,
		CategoryIDs: []string{catB},
	})
	if err != nil {
		t.Fatalf("retag: %v", err)
	}
	if retagged.Revision != 2 || len(retagged.CategoryIDs) != 1 || retagged.CategoryIDs[0] != catB {
		t.Fatalf("retag must replace the set, got %+v", retagged)
	}
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 2 || len(tasks) != 1 || len(tasks[0].CategoryIDs) != 1 || tasks[0].CategoryIDs[0] != catB {
		t.Fatalf("feed must carry the retagged set, got wm=%d %+v", wm, tasks)
	}
	// A retag on the terminal marker is refused, like every field op.
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentDelete,
	}); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: task.ID, Intent: PlannerIntentRetag,
		CategoryIDs: []string{catA},
	}); !errors.Is(err, ErrPlannerGone) {
		t.Fatalf("expected ErrPlannerGone for retag after delete, got %v", err)
	}
}

func TestPostgres_PlannerPurgeCascades(t *testing.T) {
	store := newParityStore(t)
	ctx := context.Background()
	uid := parityPlannerUser(t, store, "pg-planner-purge@example.com")

	name, key := "Read", "500000"
	task, _, err := store.ApplyPlannerOperation(ctx, uid, PlannerOperation{
		OperationID: uuidV7(), TaskID: uuidV7(), Intent: PlannerIntentCreate, Name: &name, PositionKey: &key,
	})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := store.PurgeUser(ctx, uid, "", func(string) string { return "digest" }); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	tasks, wm, _, err := store.ListPlannerFeed(ctx, uid, 0, 50)
	if err != nil {
		t.Fatalf("feed: %v", err)
	}
	if wm != 0 || len(tasks) != 0 {
		t.Fatalf("purged planner state must be gone: wm=%d n=%d", wm, len(tasks))
	}
	_ = task
}
