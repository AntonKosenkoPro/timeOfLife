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
		"id": v7(), "name": "Gym",
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
	if e.ActivityID == nil || *e.ActivityID != a.ID {
		t.Errorf("expected activity_id %s, got %+v", a.ID, e)
	}
	if e.ActivityName != "Gym" {
		t.Errorf("expected activity_name Gym, got %q", e.ActivityName)
	}
	if e.DurationSeconds == nil || *e.DurationSeconds != 3600 {
		t.Errorf("expected duration 3600, got %v", e.DurationSeconds)
	}
}

func TestCreateEntry_ActivityNotOwned(t *testing.T) {
	store := newTestStore(t)
	h := newTestHandler(t, store)
	_, tok1 := mintBearer(t, store, "owner@example.com")
	_, tok2 := mintBearer(t, store, "other@example.com")

	wa := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok2, map[string]any{
		"id": v7(), "name": "Yoga",
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
	activityID := newActivity(t, h, tok)
	for i := 0; i < 3; i++ {
		w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
			"id": v7(), "activity_id": activityID,
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

func TestDeleteEntry(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	activityID := newActivity(t, h, tok)
	we := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T09:00:00Z",
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

// F4: an empty ended_at string is treated as omitted (running timer), not as a
// present zero-time timestamp that yields a hugely negative duration.
func TestCreateEntry_EmptyEndedAtIsRunning(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	activityID := newActivity(t, h, tok)
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID,
		"started_at": "2026-07-27T09:00:00Z", "ended_at": "",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e struct {
		EndedAt         *string `json:"ended_at"`
		DurationSeconds *int    `json:"duration_seconds"`
	}
	decodeBody(t, w, &e)
	if e.EndedAt != nil {
		t.Errorf("expected nil ended_at (running), got %v", *e.EndedAt)
	}
	if e.DurationSeconds != nil {
		t.Errorf("expected nil duration_seconds (running), got %d", *e.DurationSeconds)
	}
}

// F6: GET /entries returns 422 validation_error for unparseable from/to or an
// out-of-range limit, rather than silently dropping the filter and returning
// the full unfiltered list.
func TestListEntries_InvalidParamsReturn422(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	cases := []string{
		"/api/v1/entries?from=garbage",
		"/api/v1/entries?to=notadate",
		"/api/v1/entries?limit=0",
		"/api/v1/entries?limit=201",
		"/api/v1/entries?limit=abc",
		"/api/v1/entries?modified_since=garbage",
	}
	for _, path := range cases {
		w := serve(h, jsonReq(t, "GET", path, tok, nil))
		if w.Code != http.StatusUnprocessableEntity {
			t.Errorf("%s: expected 422, got %d (body=%s)", path, w.Code, w.Body.String())
			continue
		}
		if code := errCode(t, w); code != "validation_error" {
			t.Errorf("%s: expected validation_error, got %q", path, code)
		}
	}
}

// Delta pull-sync: GET /entries?modified_since= returns only entries updated
// after the cursor; GET /activities?modified_since= behaves the same.
func TestListEntries_ModifiedSince(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	activityID := newActivity(t, h, tok)

	we1 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T09:00:00Z",
	}))
	var e1 entryResp
	decodeBody(t, we1, &e1)

	we2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T10:00:00Z",
	}))
	var e2 entryResp
	decodeBody(t, we2, &e2)

	// Pin distinct updated_at values (SQLite stores second precision, so two
	// creates in the same second share updated_at): e1 at T+1s, e2 at T+2s.
	now := time.Now().UTC().Truncate(time.Second)
	t1 := now.Add(time.Second).Format(time.RFC3339)
	t2 := now.Add(2 * time.Second).Format(time.RFC3339)
	if w := serve(h, jsonReq(t, "PATCH", "/api/v1/entries/"+e1.ID, tok, map[string]any{
		"updated_at": t1,
	})); w.Code != http.StatusOK {
		t.Fatalf("pin e1: expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}
	if w := serve(h, jsonReq(t, "PATCH", "/api/v1/entries/"+e2.ID, tok, map[string]any{
		"updated_at": t2,
	})); w.Code != http.StatusOK {
		t.Fatalf("pin e2: expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries?modified_since="+t1, tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp struct {
		Items []entryResp `json:"items"`
	}
	decodeBody(t, w, &resp)
	if len(resp.Items) != 1 || resp.Items[0].ID != e2.ID {
		t.Errorf("expected only the newer entry, got %d items", len(resp.Items))
	}
}

// Provenance: POST /entries accepts source/source_ref, defaults to manual,
// and rejects an unknown source with 422.
func TestCreateEntry_Provenance(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	activityID := newActivity(t, h, tok)

	// Explicit provenance round-trips.
	ref := "callback-42"
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T09:00:00Z",
		"source": "screentime", "source_ref": ref,
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	if e.Source != "screentime" || e.SourceRef == nil || *e.SourceRef != ref {
		t.Errorf("expected screentime/%s, got %q/%v", ref, e.Source, e.SourceRef)
	}

	// Omitted provenance defaults to manual/null.
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T10:00:00Z",
	}))
	var e2 entryResp
	decodeBody(t, w2, &e2)
	if e2.Source != "manual" || e2.SourceRef != nil {
		t.Errorf("expected manual/nil, got %q/%v", e2.Source, e2.SourceRef)
	}

	// Unknown source → 422.
	w3 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T11:00:00Z",
		"source": "time-machine",
	}))
	if w3.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422 for unknown source, got %d (body=%s)", w3.Code, w3.Body.String())
	}
}

// Duplicate import: a second POST with the same (source, source_ref) is
// rejected with 409 duplicate_import.
func TestCreateEntry_DuplicateImportRejected(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	activityID := newActivity(t, h, tok)
	ref := "interval-7"

	body := map[string]any{
		"id": v7(), "activity_id": activityID, "started_at": "2026-07-27T09:00:00Z",
		"source": "screentime", "source_ref": ref,
	}
	w1 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, body))
	if w1.Code != http.StatusCreated {
		t.Fatalf("first create: expected 201, got %d (body=%s)", w1.Code, w1.Body.String())
	}

	body["id"] = v7()
	body["started_at"] = "2026-07-27T10:00:00Z"
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, body))
	if w2.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	if code := errCode(t, w2); code != "duplicate_import" {
		t.Errorf("expected code duplicate_import, got %q", code)
	}
}
