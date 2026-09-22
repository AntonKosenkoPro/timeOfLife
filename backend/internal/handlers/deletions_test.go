package handlers

import (
	"net/http"
	"testing"
	"time"
)

// tombstoneResp mirrors the Deletion response for test assertions.
type tombstoneResp struct {
	Resource  string `json:"resource"`
	ID        string `json:"id"`
	DeletedAt string `json:"deleted_at"`
}

func newDeletionsHandler(t *testing.T) (*Handler, string) {
	t.Helper()
	h, _, _, tok := newCatalogHandler(t)
	return h, tok
}

// GET /deletions with no tombstones returns 200 with a bare [] (never null).
func TestListDeletions_Empty(t *testing.T) {
	h, tok := newDeletionsHandler(t)

	w := serve(h, jsonReq(t, "GET", "/api/v1/deletions", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}
	if w.Body.String() != "[]\n" {
		t.Errorf("expected bare empty array, got %q", w.Body.String())
	}
}

// Deleting a category/entry via the API records tombstones listed by
// GET /deletions, oldest first. Tombstones are entries/categories only —
// activity tombstones no longer exist.
func TestListDeletions_AfterDeletes(t *testing.T) {
	h, tok := newDeletionsHandler(t)

	catID := createCategoryHelper(t, h, tok, "Sport", "tag")
	entryID := newEntryHelper(t, h, tok, "Gym", []string{catID})

	delEntry := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+entryID, tok, nil))
	if delEntry.Code != http.StatusNoContent {
		t.Fatalf("delete entry: expected 204, got %d", delEntry.Code)
	}
	delCat := serve(h, jsonReq(t, "DELETE", "/api/v1/categories/"+catID, tok, nil))
	if delCat.Code != http.StatusNoContent {
		t.Fatalf("delete category: expected 204, got %d", delCat.Code)
	}

	w := serve(h, jsonReq(t, "GET", "/api/v1/deletions", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}
	var list []tombstoneResp
	decodeBody(t, w, &list)
	if len(list) != 2 {
		t.Fatalf("expected 2 tombstones, got %d: %+v", len(list), list)
	}
	byResource := map[string]tombstoneResp{}
	for _, tomb := range list {
		byResource[tomb.Resource] = tomb
		if tomb.DeletedAt == "" {
			t.Errorf("expected non-empty deleted_at, got %+v", tomb)
		}
		if tomb.Resource != "entry" && tomb.Resource != "category" {
			t.Errorf("unexpected tombstone resource %q (entries/categories only): %+v", tomb.Resource, tomb)
		}
	}
	if byResource["category"].ID != catID || byResource["entry"].ID != entryID {
		t.Errorf("tombstone ids do not match the deleted records: %+v", list)
	}
	// Ordering: deleted_at ASC.
	for i := 1; i < len(list); i++ {
		prev, _ := time.Parse(time.RFC3339Nano, list[i-1].DeletedAt)
		cur, _ := time.Parse(time.RFC3339Nano, list[i].DeletedAt)
		if cur.Before(prev) {
			t.Errorf("expected deleted_at ASC ordering, got %+v", list)
			break
		}
	}
}

// A malformed deleted_since cursor is a 422 validation error (mirrors
// modified_since); absent/empty is a full list.
func TestListDeletions_DeletedSinceValidation(t *testing.T) {
	h, tok := newDeletionsHandler(t)

	wb := serve(h, jsonReq(t, "GET", "/api/v1/deletions?deleted_since=garbage", tok, nil))
	if wb.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for malformed deleted_since, got %d (body=%s)", wb.Code, wb.Body.String())
	}
	var resp struct {
		Error struct {
			Code    string            `json:"code"`
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, wb, &resp)
	if resp.Error.Code != "validation_error" {
		t.Errorf("expected code validation_error, got %q", resp.Error.Code)
	}
	if _, ok := resp.Error.Details["deleted_since"]; !ok {
		t.Errorf("expected deleted_since in details, got %+v", resp.Error.Details)
	}

	// Empty value = full list (200, not 422).
	we := serve(h, jsonReq(t, "GET", "/api/v1/deletions?deleted_since=", tok, nil))
	if we.Code != http.StatusOK {
		t.Errorf("expected 200 for empty deleted_since, got %d", we.Code)
	}
}

// GET /deletions?deleted_since= passes the cursor through to the store: only
// tombstones strictly newer than the cursor are returned.
func TestListDeletions_DeletedSinceFilter(t *testing.T) {
	h, tok := newDeletionsHandler(t)

	actID := newEntry(t, h, tok)
	del1 := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+actID, tok, nil))
	if del1.Code != http.StatusNoContent {
		t.Fatalf("delete 1: expected 204, got %d", del1.Code)
	}

	// Pin the cursor to the current second (SQLite second precision), then
	// wait so the second delete's tombstone is strictly newer.
	cursor := time.Now().UTC().Truncate(time.Second)
	time.Sleep(1100 * time.Millisecond)

	actID2 := newEntry(t, h, tok)
	del2 := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+actID2, tok, nil))
	if del2.Code != http.StatusNoContent {
		t.Fatalf("delete 2: expected 204, got %d", del2.Code)
	}

	w := serve(h, jsonReq(t, "GET", "/api/v1/deletions?deleted_since="+cursor.Format(time.RFC3339), tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}
	var list []tombstoneResp
	decodeBody(t, w, &list)
	if len(list) != 1 || list[0].ID != actID2 {
		t.Errorf("expected only the newer tombstone, got %+v", list)
	}

	// No cursor = full list.
	wf := serve(h, jsonReq(t, "GET", "/api/v1/deletions", tok, nil))
	decodeBody(t, wf, &list)
	if len(list) != 2 {
		t.Errorf("expected 2 tombstones on the full list, got %d", len(list))
	}
}
