package handlers

import (
	"net/http"
	"testing"
	"time"
)

func TestEntries_NoAuth_Returns401(t *testing.T) {
	h, _, _, _ := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("list entries: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "POST", "/api/v1/entries", "", map[string]any{"id": v7(), "started_at": "2026-07-27T09:00:00Z"}))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("create entry: expected 401, got %d", w.Code)
	}
}

func TestCreateEntry_WithActivity(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	wa := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym", "color": "blue", "icon": "figure.run",
	}))
	var a activityResp
	decodeBody(t, wa, &a)

	we := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": a.ID, "started_at": "2026-07-27T09:00:00Z", "ended_at": "2026-07-27T10:00:00Z",
	}))
	if we.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", we.Code, we.Body.String())
	}
	var e entryResp
	decodeBody(t, we, &e)
	if !e.Linked || e.ActivityID == nil || *e.ActivityID != a.ID {
		t.Errorf("expected linked to %s, got %+v", a.ID, e)
	}
	if e.DurationSeconds == nil || *e.DurationSeconds != 3600 {
		t.Errorf("expected duration 3600, got %v", e.DurationSeconds)
	}
}

func TestCreateEntry_FreeText(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_name_snapshot": "Adhoc", "started_at": "2026-07-27T09:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	if e.Linked {
		t.Error("expected unlinked free-text entry")
	}
}

func TestCreateEntry_ActivityNotOwned(t *testing.T) {
	store := newTestStore(t)
	h := newTestHandler(t, store)
	_, tok1 := mintBearer(t, store, "owner@example.com")
	_, tok2 := mintBearer(t, store, "other@example.com")

	wa := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok2, map[string]any{
		"id": v7(), "name": "Yoga", "color": "purple", "icon": "figure.yoga",
	}))
	var a activityResp
	decodeBody(t, wa, &a)

	we := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok1, map[string]any{
		"id": v7(), "activity_id": a.ID, "started_at": "2026-07-27T09:00:00Z",
	}))
	if we.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d (body=%s)", we.Code, we.Body.String())
	}
	if code := errCode(t, we); code != "activity_not_found" {
		t.Errorf("expected code activity_not_found, got %q", code)
	}
}

func TestCreateEntry_Validation(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{"id": v7()}))
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d (body=%s)", w.Code, w.Body.String())
	}

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "started_at": "2026-07-27T10:00:00Z", "ended_at": "2026-07-27T09:00:00Z",
	}))
	if w2.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	var resp struct {
		Error struct {
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w2, &resp)
	if _, ok := resp.Error.Details["ended_at"]; !ok {
		t.Errorf("expected ended_at in details, got %+v", resp.Error.Details)
	}
}

func TestListEntries_Pagination(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	for i := 0; i < 3; i++ {
		w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
			"id": v7(), "activity_name_snapshot": "x",
			"started_at": time.Date(2026, 7, 1, 9+i, 0, 0, 0, time.UTC).Format(time.RFC3339),
		}))
		if w.Code != http.StatusCreated {
			t.Fatalf("create %d: expected 201, got %d", i, w.Code)
		}
	}

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries?limit=2", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp struct {
		Items      []entryResp `json:"items"`
		NextCursor string      `json:"next_cursor"`
	}
	decodeBody(t, w, &resp)
	if len(resp.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(resp.Items))
	}
	if resp.NextCursor == "" {
		t.Fatal("expected next_cursor")
	}
}

func TestUnlinkEntry(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	wc := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{"id": v7(), "name": "Sport", "color": "green"}))
	var cat struct {
		ID string `json:"id"`
	}
	decodeBody(t, wc, &cat)

	wa := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym", "color": "blue", "icon": "figure.run", "category_ids": []string{cat.ID},
	}))
	var a activityResp
	decodeBody(t, wa, &a)

	we := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": a.ID, "started_at": "2026-07-27T09:00:00Z",
	}))
	var e entryResp
	decodeBody(t, we, &e)

	wu := serve(h, jsonReq(t, "POST", "/api/v1/entries/"+e.ID+"/unlink", tok, nil))
	if wu.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", wu.Code, wu.Body.String())
	}
	var unlinked struct {
		Linked     bool `json:"linked"`
		Categories []struct {
			Name string `json:"name"`
		} `json:"categories"`
	}
	decodeBody(t, wu, &unlinked)
	if unlinked.Linked {
		t.Error("expected linked=false after unlink")
	}
	if len(unlinked.Categories) != 1 || unlinked.Categories[0].Name != "Sport" {
		t.Errorf("expected frozen Sport tag, got %+v", unlinked.Categories)
	}

	wu2 := serve(h, jsonReq(t, "POST", "/api/v1/entries/"+e.ID+"/unlink", tok, nil))
	if wu2.Code != http.StatusConflict {
		t.Errorf("expected 409 on second unlink, got %d", wu2.Code)
	}
}

func TestDeleteEntry(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	we := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_name_snapshot": "x", "started_at": "2026-07-27T09:00:00Z",
	}))
	var e entryResp
	decodeBody(t, we, &e)

	wd := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+e.ID, tok, nil))
	if wd.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", wd.Code)
	}

	wg := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+e.ID, tok, nil))
	if wg.Code != http.StatusNotFound {
		t.Errorf("expected 404 after delete, got %d", wg.Code)
	}
}
