package handlers

import (
	"testing"

	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

// Sample tests demonstrating the factory helpers. These factories exist so
// ATDD/automation tests (1.4-UNIT-005/006, 1.1-API-003, ...) seed state
// deterministically instead of hand-rolling request bodies.

func TestFactory_NewActivityWithEntries_CreatesActivityAndEntries(t *testing.T) {
	h, store, _, tok := newCatalogHandler(t)
	t.Cleanup(func() { _ = store.Close() })

	id := newActivityWithEntries(t, h, tok, 2)

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries", tok, map[string]any{}))
	if w.Code != 200 {
		t.Fatalf("list entries: expected 200, got %d", w.Code)
	}
	var resp struct {
		Items []entryResp `json:"items"`
	}
	decodeBody(t, w, &resp)
	if len(resp.Items) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(resp.Items))
	}
	for _, e := range resp.Items {
		if e.ActivityID == nil || *e.ActivityID != id {
			t.Errorf("entry %q not linked to activity %s", e.ID, id)
		}
	}
}

func TestFactory_TwoUsers_AreIsolated(t *testing.T) {
	store := newTestStore(t)
	h := newTestHandler(t, store)
	_, tokA, _, tokB := twoUsers(t, store)
	t.Cleanup(func() { _ = store.Close() })

	// User A creates an activity; user B must not see it (ownership, R-014).
	aID := newActivity(t, h, tokA)
	w := serve(h, jsonReq(t, "GET", "/api/v1/activities/"+aID, tokB, nil))
	if w.Code != 404 {
		t.Fatalf("user B viewing user A's activity: expected 404, got %d", w.Code)
	}
	if code := errCode(t, w); code != "not_found" {
		t.Errorf("expected code not_found, got %q", code)
	}
}

var _ db.Store
