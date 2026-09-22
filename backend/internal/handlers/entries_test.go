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
	w = serve(h, jsonReq(t, "POST", "/api/v1/entries", "", map[string]any{"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z"}))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("create entry: expected 401, got %d", w.Code)
	}
}

func TestCreateEntry_WithTextAndCategories(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	catID := createCategoryHelper(t, h, tok, "Sport", "tag")

	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "notes": "leg day", "category_ids": []string{catID},
		"started_at": "2026-07-27T09:00:00Z", "ended_at": "2026-07-27T10:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	if e.ActivityText != "Gym" || e.Notes != "leg day" {
		t.Errorf("expected Gym/leg day, got %q/%q", e.ActivityText, e.Notes)
	}
	if len(e.Categories) != 1 || e.Categories[0].ID != catID {
		t.Errorf("expected own Sport tag, got %+v", e.Categories)
	}
}

// Entry create validation: activity_text (trimmed non-empty, 60 runes) and
// notes (280 runes) gate the write; category id format is checked.
func TestCreateEntry_Validation(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	// Missing activity_text → 422.
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{"id": v7()}))
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d (body=%s)", w.Code, w.Body.String())
	}
	var resp struct {
		Error struct {
			Code    string            `json:"code"`
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w, &resp)
	if resp.Error.Code != "validation_error" {
		t.Errorf("expected code validation_error, got %q", resp.Error.Code)
	}
	if _, ok := resp.Error.Details["activity_text"]; !ok {
		t.Errorf("expected activity_text in details, got %+v", resp.Error.Details)
	}

	// Whitespace-only text is rejected.
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "   ", "started_at": "2026-07-27T09:00:00Z",
	}))
	if w2.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422 for whitespace-only text, got %d (body=%s)", w2.Code, w2.Body.String())
	}

	// 61 runes of text → 422 (rune count, not bytes).
	sixtyOneRunes := ""
	for i := 0; i < 61; i++ {
		sixtyOneRunes += "я"
	}
	w3 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": sixtyOneRunes, "started_at": "2026-07-27T09:00:00Z",
	}))
	if w3.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422 for 61-rune text, got %d (body=%s)", w3.Code, w3.Body.String())
	}

	// ended_at before started_at → 422 with ended_at detail.
	w4 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T10:00:00Z", "ended_at": "2026-07-27T09:00:00Z",
	}))
	if w4.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d (body=%s)", w4.Code, w4.Body.String())
	}
	var resp4 struct {
		Error struct {
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w4, &resp4)
	if _, ok := resp4.Error.Details["ended_at"]; !ok {
		t.Errorf("expected ended_at in details, got %+v", resp4.Error.Details)
	}
}

// 60 Cyrillic runes (120 bytes) pass — the limit is a rune count.
func TestCreateEntry_RuneCountText(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	sixtyRunes := ""
	for i := 0; i < 60; i++ {
		sixtyRunes += "я"
	}
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": sixtyRunes, "started_at": "2026-07-27T09:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("60 Cyrillic chars: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
}

// Trim rule over the wire: `"  Gym  "` is stored as `Gym`.
func TestCreateEntry_TrimsText(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "  Gym  ", "started_at": "2026-07-27T09:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	if e.ActivityText != "Gym" {
		t.Errorf("expected trimmed Gym, got %q", e.ActivityText)
	}
}

// Case-sensitive identity (D1): `Gym` and `GYM` are independent texts — the
// relay neither merges nor remaps them; recents/LWW treat them as separate.
func TestCreateEntry_CaseSensitiveIdentity(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w1 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z",
	}))
	if w1.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w1.Code, w1.Body.String())
	}
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "GYM", "started_at": "2026-07-27T10:00:00Z",
	}))
	if w2.Code != http.StatusCreated {
		t.Fatalf("GYM must be an independent entry (no case-insensitive collision), got %d (body=%s)", w2.Code, w2.Body.String())
	}
	var e2 entryResp
	decodeBody(t, w2, &e2)
	if e2.ActivityText != "GYM" {
		t.Errorf("case must be preserved exactly, got %q", e2.ActivityText)
	}

	// Recents keep them as separate exact-text groups.
	wr := serve(h, jsonReq(t, "GET", "/api/v1/entries/recents", tok, nil))
	if wr.Code != http.StatusOK {
		t.Fatalf("recents: expected 200, got %d (body=%s)", wr.Code, wr.Body.String())
	}
	var recents []entryResp
	decodeBody(t, wr, &recents)
	if len(recents) != 2 || recents[0].ActivityText != "GYM" || recents[1].ActivityText != "Gym" {
		t.Errorf("expected separate groups [GYM Gym] newest-first, got %+v", recents)
	}
}

// GET /entries/recents mirrors the D5 query: one entry per exact text (the
// group's newest wins, with its own categories), newest-first, limit 6 default.
func TestListRecents(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	catID := createCategoryHelper(t, h, tok, "Sport", "tag")

	anchor := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	createAt := func(text string, categoryIDs []string, offset time.Duration) string {
		t.Helper()
		body := map[string]any{
			"id":            v7(),
			"activity_text": text,
			"started_at":    anchor.Add(offset).Format(time.RFC3339),
		}
		if categoryIDs != nil {
			body["category_ids"] = categoryIDs
		}
		w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, body))
		if w.Code != http.StatusCreated {
			t.Fatalf("create entry %q: expected 201, got %d (body=%s)", text, w.Code, w.Body.String())
		}
		var e entryResp
		decodeBody(t, w, &e)
		return e.ID
	}

	createAt("Gym", []string{catID}, 0)          // older Gym
	winner := createAt("Gym", nil, 48*time.Hour) // newest Gym — beats every Text* entry
	texts := make([]string, 0, 10)
	for i := 0; i < 10; i++ { // 10 more distinct texts, spread across the clock
		texts = append(texts, "Text"+string(rune('A'+i)))
	}
	newEntriesWithTexts(t, h, tok, texts)

	w := serve(h, jsonReq(t, "GET", "/api/v1/entries/recents", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", w.Code, w.Body.String())
	}
	var recents []entryResp
	decodeBody(t, w, &recents)
	if len(recents) != 6 {
		t.Fatalf("expected default limit 6, got %d", len(recents))
	}
	// Gym's group is the newest overall and its newest entry wins it.
	if recents[0].ID != winner {
		t.Errorf("expected the newest Gym entry to win its group, got %+v", recents[0])
	}
}

// Prune rule (D7): a PATCH merge with unknown category ids drops them and
// keeps the remainder — never 422, never 500.
func TestUpdateEntry_PruneUnknownCategories(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	catID := createCategoryHelper(t, h, tok, "Sport", "tag")
	entryID := newEntryHelper(t, h, tok, "Gym", []string{catID})

	var current entryResp
	got := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+entryID, tok, nil))
	decodeBody(t, got, &current)

	secondID := createCategoryHelper(t, h, tok, "Work", "briefcase")
	patch := serve(h, jsonReq(t, "PATCH", "/api/v1/entries/"+entryID, tok, map[string]any{
		"category_ids": []string{secondID, v7(), catID, v7()},
		"updated_at":   rfc3339Add(current.UpdatedAt, time.Hour),
	}))
	if patch.Code != http.StatusOK {
		t.Fatalf("expected 200 (prune, don't fail), got %d (body=%s)", patch.Code, patch.Body.String())
	}
	var updated entryResp
	decodeBody(t, patch, &updated)
	if len(updated.Categories) != 2 || updated.Categories[0].ID != secondID || updated.Categories[1].ID != catID {
		t.Errorf("expected pruned ordered [Work Sport], got %+v", updated.Categories)
	}
}

// Per-entry isolation over the wire: PATCHing one entry never moves another,
// even with the same exact text.
func TestUpdateEntry_Isolation(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	e1 := newEntryHelper(t, h, tok, "Gym", nil)
	e2 := newEntryHelper(t, h, tok, "Gym", nil)

	var cur entryResp
	decodeBody(t, serve(h, jsonReq(t, "GET", "/api/v1/entries/"+e2, tok, nil)), &cur)

	patch := serve(h, jsonReq(t, "PATCH", "/api/v1/entries/"+e1, tok, map[string]any{
		"activity_text": "GYM",
		"notes":         "only me",
		"updated_at":    rfc3339Add(cur.UpdatedAt, time.Hour),
	}))
	if patch.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", patch.Code, patch.Body.String())
	}

	got2 := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+e2, tok, nil))
	var e2resp entryResp
	decodeBody(t, got2, &e2resp)
	if e2resp.ActivityText != "Gym" || e2resp.Notes != "" {
		t.Errorf("e2 must be untouched, got %q/%q", e2resp.ActivityText, e2resp.Notes)
	}
}

func TestListEntries_Pagination(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	newEntriesWithTexts(t, h, tok, []string{"A", "B", "C"})

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
	entryID := newEntry(t, h, tok)

	wd := serve(h, jsonReq(t, "DELETE", "/api/v1/entries/"+entryID, tok, nil))
	if wd.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", wd.Code)
	}

	wg := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+entryID, tok, nil))
	if wg.Code != http.StatusNotFound {
		t.Errorf("expected 404 after delete, got %d", wg.Code)
	}
}

// F4: an empty ended_at string is treated as omitted (running timer), not as a
// present zero-time timestamp that yields a hugely negative duration.
func TestCreateEntry_EmptyEndedAtIsRunning(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym",
		"started_at": "2026-07-27T09:00:00Z", "ended_at": "",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var entry struct {
		EndedAt         *string `json:"ended_at"`
		DurationSeconds *int    `json:"duration_seconds"`
	}
	decodeBody(t, w, &entry)
	if entry.EndedAt != nil {
		t.Errorf("expected nil ended_at (running), got %v", *entry.EndedAt)
	}
	if entry.DurationSeconds != nil {
		t.Errorf("expected nil duration_seconds (running), got %d", *entry.DurationSeconds)
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
// after the cursor.
func TestListEntries_ModifiedSince(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	we1 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z",
	}))
	var e1 entryResp
	decodeBody(t, we1, &e1)

	we2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Read", "started_at": "2026-07-27T10:00:00Z",
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

	// Explicit provenance round-trips.
	ref := "callback-42"
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z",
		"source": "screentime", "source_ref": ref,
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryMetaResp
	decodeBody(t, w, &e)
	if e.Source != "screentime" || e.SourceRef == nil || *e.SourceRef != ref {
		t.Errorf("expected screentime/%s, got %q/%v", ref, e.Source, e.SourceRef)
	}

	// Omitted provenance defaults to manual/null.
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Read", "started_at": "2026-07-27T10:00:00Z",
	}))
	var e2 entryMetaResp
	decodeBody(t, w2, &e2)
	if e2.Source != "manual" || e2.SourceRef != nil {
		t.Errorf("expected manual/nil, got %q/%v", e2.Source, e2.SourceRef)
	}

	// Unknown source → 422.
	w3 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Walk", "started_at": "2026-07-27T11:00:00Z",
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
	ref := "interval-7"

	body := map[string]any{
		"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z",
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
