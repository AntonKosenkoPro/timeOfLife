package handlers

import (
	"net/http/httptest"
	"testing"
)

// Sample tests demonstrating the factory helpers. These factories exist so
// ATDD/automation tests (1.4-UNIT-005/006, 1.1-API-003, ...) seed state
// deterministically instead of hand-rolling request bodies.

func TestFactory_NewEntriesWithTexts_CreatesEntries(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	ids := newEntriesWithTexts(t, h, tok, []string{"Gym", "Read"})

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
	for _, id := range ids {
		found := false
		for _, e := range resp.Items {
			if e.ID == id {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("created entry %q missing from the list", id)
		}
	}
}

func TestFactory_TwoUsers_AreIsolated(t *testing.T) {
	store := newTestStore(t)
	h := newTestHandler(t, store)
	_, tokA, _, tokB := twoUsers(t, store)

	// User A creates an entry; user B must not see it (ownership, R-014).
	eID := newEntry(t, h, tokA)
	w := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+eID, tokB, nil))
	if w.Code != 404 {
		t.Fatalf("user B viewing user A's entry: expected 404, got %d", w.Code)
	}
	if code := errCode(t, w); code != "not_found" {
		t.Errorf("expected code not_found, got %q", code)
	}
	_ = httptest.NewRecorder
}
