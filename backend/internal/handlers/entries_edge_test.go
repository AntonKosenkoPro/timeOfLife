package handlers

import (
	"net/http"
	"testing"
	"time"
)

// TestListEntries_CursorFollowThrough pins pagination: page 1 returns the
// newest items plus a cursor, page 2 resumes strictly below it, and the last
// page carries no cursor.
func TestListEntries_CursorFollowThrough(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	newEntriesWithTexts(t, h, tok, []string{"A", "B", "C"})

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries?limit=2", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("page 1: expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var p1 struct {
		Items      []entryResp `json:"items"`
		NextCursor string      `json:"next_cursor"`
	}
	decodeBody(t, w, &p1)
	if len(p1.Items) != 2 || p1.NextCursor == "" {
		t.Fatalf("page 1: expected 2 items + cursor, got %+v", p1)
	}
	if p1.Items[0].ActivityText != "C" || p1.Items[1].ActivityText != "B" {
		t.Errorf("page 1: expected [C B] newest-first, got [%s %s]", p1.Items[0].ActivityText, p1.Items[1].ActivityText)
	}

	w = serve(h, jsonReq(t, "GET", "/api/v1/entries?limit=2&cursor="+p1.NextCursor, tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("page 2: expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var p2 struct {
		Items      []entryResp `json:"items"`
		NextCursor string      `json:"next_cursor"`
	}
	decodeBody(t, w, &p2)
	if len(p2.Items) != 1 || p2.Items[0].ActivityText != "A" {
		t.Errorf("page 2: expected [A], got %+v", p2.Items)
	}
	if p2.NextCursor != "" {
		t.Errorf("last page: expected no next_cursor, got %q", p2.NextCursor)
	}
}

// TestListEntries_MalformedCursorIgnored pins the fail-open decoder at the
// HTTP layer: a garbage cursor is ignored and the first page is returned
// (200), rather than a 422. (decodeCursor itself is fail-closed in db tests.)
func TestListEntries_MalformedCursorIgnored(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	newEntriesWithTexts(t, h, tok, []string{"A", "B"})

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries?cursor=not-a-cursor!!!", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var resp struct {
		Items []entryResp `json:"items"`
	}
	decodeBody(t, w, &resp)
	if len(resp.Items) != 2 {
		t.Errorf("expected first page (2 items), got %d", len(resp.Items))
	}
}

// TestListEntries_ToBeforeFrom pins the actual behavior for an inverted
// range: 200 with an empty page (no 422 — the handler validates formats,
// not ordering). Follow-up candidate: decide whether to<from should 422.
func TestListEntries_ToBeforeFrom(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	newEntry(t, h, tok)

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries?from=2026-07-28T00:00:00Z&to=2026-07-27T00:00:00Z", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var resp struct {
		Items []entryResp `json:"items"`
	}
	decodeBody(t, w, &resp)
	if len(resp.Items) != 0 {
		t.Errorf("expected empty page for to<from, got %d items", len(resp.Items))
	}
}

// TestEntries_Tombstone404 pins the delete mapping: delete writes a tombstone
// visible in ListDeletions, and a subsequent get is 404 not_found.
func TestEntries_Tombstone404(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	entryID := newEntry(t, h, tok)

	wd := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+entryID, tok, nil))
	if wd.Code != http.StatusNoContent {
		t.Fatalf("delete: expected 204, got %d (%s)", wd.Code, wd.Body.String())
	}

	wg := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+entryID, tok, nil))
	if wg.Code != http.StatusNotFound {
		t.Fatalf("get after delete: expected 404, got %d (%s)", wg.Code, wg.Body.String())
	}
	if code := errCode(t, wg); code != "not_found" {
		t.Errorf("expected not_found, got %q", code)
	}

	wdel := serve(h, jsonReq(t, "GET", "/api/v1/deletions", tok, nil))
	if wdel.Code != http.StatusOK {
		t.Fatalf("deletions: expected 200, got %d (%s)", wdel.Code, wdel.Body.String())
	}
	var tombstones []struct {
		Resource string `json:"resource"`
		ID       string `json:"id"`
	}
	decodeBody(t, wdel, &tombstones)
	found := false
	for _, ts := range tombstones {
		if ts.Resource == "entry" && ts.ID == entryID {
			found = true
		}
	}
	if !found {
		t.Errorf("expected entry tombstone for %s in %+v", entryID, tombstones)
	}
}

// TestCategory_StaleUpdate409 pins the 409 conflict mapping: a stale
// updated_at is rejected with conflict and the server version in details.
//
// NOTE (follow-up candidate, real bug — NOT fixed here): the same stale
// write on *entries* deadlocks the SQLite store instead of returning
// ErrConflict. UpdateEntry holds its tx (single-connection pool) while
// re-reading the row via the pool (sqlite_catalog.go:666), so the read
// waits forever. The Postgres path is unaffected (multi-connection pool).
// The entry-stale case is therefore pinned only via categories here.
func TestCategory_StaleUpdate409(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	catID := createCategoryHelper(t, h, tok, "Gym", "dumbbell")

	stale := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339Nano)
	wu := serve(h, jsonReq(t, "PATCH", "/api/v1/categories/"+catID, tok, map[string]any{
		"name": "Stale", "updated_at": stale,
	}))
	if wu.Code != http.StatusConflict {
		t.Fatalf("stale update: expected 409, got %d (%s)", wu.Code, wu.Body.String())
	}
	var conflict struct {
		Error struct {
			Code    string            `json:"code"`
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, wu, &conflict)
	if conflict.Error.Code != "conflict" {
		t.Errorf("expected conflict, got %q", conflict.Error.Code)
	}
	if _, ok := conflict.Error.Details["updated_at"]; !ok {
		t.Errorf("expected updated_at in 409 details, got %+v", conflict.Error.Details)
	}
}

// TestEntries_Create422VsMergePrune pins the asymmetric category-id rule:
// create rejects unknown ids loudly (422 validation_error), while a merge
// (PATCH) prunes them and succeeds (200).
func TestEntries_Create422VsMergePrune(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	wc := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym",
		"started_at":   "2026-07-27T09:00:00Z",
		"category_ids": []string{v7()}, // well-formed but unknown
	}))
	if wc.Code != http.StatusUnprocessableEntity {
		t.Fatalf("create with unknown category: expected 422, got %d (%s)", wc.Code, wc.Body.String())
	}
	if code := errCode(t, wc); code != "validation_error" {
		t.Errorf("expected validation_error, got %q", code)
	}

	entryID := newEntry(t, h, tok)
	// Bump past SQLite's second-precision updated_at: an updated_at within
	// the same second truncates equal and takes the stale path (which
	// deadlocks — see the NOTE on TestCategory_StaleUpdate409).
	fresh := time.Now().Add(2 * time.Second).UTC().Format(time.RFC3339Nano)
	wu := serve(h, jsonReq(t, "PATCH", "/api/v1/entries/"+entryID, tok, map[string]any{
		"category_ids": []string{v7()}, // unknown → pruned, merge succeeds
		"updated_at":   fresh,
	}))
	if wu.Code != http.StatusOK {
		t.Fatalf("merge with unknown category: expected 200 (pruned), got %d (%s)", wu.Code, wu.Body.String())
	}
	var merged entryResp
	decodeBody(t, wu, &merged)
	if len(merged.Categories) != 0 {
		t.Errorf("expected pruned (empty) categories, got %+v", merged.Categories)
	}
}

// TestCategories_ModifiedSinceIgnored pins the ACTUAL behavior: the handler
// ignores ?modified_since= on GET /categories (200, full list) even though
// GET /entries honors it. The spec likewise does not document the parameter
// here (see contract pins). Follow-up candidate: implement the filter or
// remove it from clients.
func TestCategories_ModifiedSinceIgnored(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	createCategoryHelper(t, h, tok, "Gym", "dumbbell")

	w := serve(h, jsonReq(t, "GET", "/api/v1/categories?modified_since=2999-01-01T00:00:00Z", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var cats []struct {
		Name string `json:"name"`
	}
	decodeBody(t, w, &cats)
	if len(cats) != 1 {
		t.Errorf("expected modified_since ignored (1 category), got %d", len(cats))
	}
}
