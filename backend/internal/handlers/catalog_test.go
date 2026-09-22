package handlers

import (
	"net/http"
	"testing"
	"time"
)

func TestCatalog_NoAuth_Returns401(t *testing.T) {
	h, _, _, _ := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "GET", "/api/v1/categories", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("list categories: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "GET", "/api/v1/entries", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("list entries: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "POST", "/api/v1/entries", "", map[string]any{"id": v7(), "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z"}))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("create entry: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "GET", "/api/v1/entries/x", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("get entry: expected 401, got %d", w.Code)
	}
}

// POST /activities* no longer exists (remove-activities-layer): the router
// answers 404/405, never a catalog record.
func TestActivitiesRoutes_Removed(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	for _, tc := range []struct{ method, path string }{
		{"GET", "/api/v1/activities"},
		{"POST", "/api/v1/activities"},
		{"GET", "/api/v1/activities/" + v7()},
		{"PATCH", "/api/v1/activities/" + v7()},
		{"DELETE", "/api/v1/activities/" + v7()},
	} {
		w := serve(h, jsonReq(t, tc.method, tc.path, tok, map[string]any{"id": v7(), "name": "Gym"}))
		if w.Code == http.StatusOK || w.Code == http.StatusCreated || w.Code == http.StatusNoContent {
			t.Errorf("%s %s must not exist any more, got %d", tc.method, tc.path, w.Code)
		}
	}
}

func TestCreateCategory_NewIcons(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	// Each iOS-only icon must be accepted.
	icons := []string{
		"pencil.and.ruler", "brain.head.profile",
		"dumbbell", "bicycle",
		"bed.double", "moon.stars",
		"film", "music.note", "guitar", "camera",
		"hammer", "heart", "leaf", "sparkles",
	}
	for _, icon := range icons {
		w := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
			"id": v7(), "name": icon, "icon": icon,
		}))
		if w.Code != http.StatusCreated {
			t.Errorf("icon %q: expected 201, got %d (body=%s)", icon, w.Code, w.Body.String())
		}
	}
}

func TestCategory_CRUD(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": "Sport", "icon": "tag",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var c struct {
		ID   string `json:"id"`
		Icon string `json:"icon"`
	}
	decodeBody(t, w, &c)
	if c.Icon != "tag" {
		t.Errorf("expected category icon tag, got %q", c.Icon)
	}

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": "sport", "icon": "briefcase",
	}))
	if w2.Code != http.StatusConflict || errCode(t, w2) != "category_exists" {
		t.Errorf("expected 409 category_exists, got %d code=%q", w2.Code, errCode(t, w2))
	}

	wl := serve(h, jsonReq(t, "GET", "/api/v1/categories", tok, nil))
	if wl.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", wl.Code)
	}
	var list []struct {
		ID, Name, Icon string
	}
	decodeBody(t, wl, &list)
	if len(list) != 1 || list[0].Name != "Sport" || list[0].Icon != "tag" {
		t.Errorf("expected one Sport category, got %+v", list)
	}

	wd := serve(h, jsonReq(t, "DELETE", "/api/v1/categories/"+c.ID, tok, nil))
	if wd.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", wd.Code)
	}
}

func TestCreateCategory_InvalidIcon(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": "Sport", "icon": "not-an-icon",
	}))
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422, got %d (body=%s)", w.Code, w.Body.String())
	}
	var resp struct {
		Error struct {
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w, &resp)
	if _, ok := resp.Error.Details["icon"]; !ok {
		t.Errorf("expected icon in details, got %+v", resp.Error.Details)
	}
}

// createCategoryHelper creates a category and returns its id.
func createCategoryHelper(t *testing.T, h *Handler, tok, name, icon string) string {
	t.Helper()
	w := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": name, "icon": icon,
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("create category %q: expected 201, got %d (body=%s)", name, w.Code, w.Body.String())
	}
	var c struct {
		ID string `json:"id"`
	}
	decodeBody(t, w, &c)
	return c.ID
}

// Entry-category association order round-trips through the entry_categories
// join, on both create and read.
func TestEntryCategoryOrder_RoundTrip(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	firstID := createCategoryHelper(t, h, tok, "Sport", "tag")
	secondID := createCategoryHelper(t, h, tok, "Work", "briefcase")

	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "category_ids": []string{secondID, firstID},
		"started_at": "2026-07-27T09:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("create entry: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var created entryResp
	decodeBody(t, w, &created)
	if len(created.Categories) != 2 || created.Categories[0].ID != secondID || created.Categories[1].ID != firstID {
		t.Fatalf("expected category order [%s %s], got %+v", secondID, firstID, created.Categories)
	}
	if created.Categories[0].Icon != "briefcase" || created.Categories[1].Icon != "tag" {
		t.Errorf("expected ordered category icons, got %+v", created.Categories)
	}

	got := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+created.ID, tok, nil))
	if got.Code != http.StatusOK {
		t.Fatalf("get entry: expected 200, got %d", got.Code)
	}
	var fetched entryResp
	decodeBody(t, got, &fetched)
	if len(fetched.Categories) != 2 || fetched.Categories[0].ID != secondID || fetched.Categories[1].ID != firstID {
		t.Errorf("GET did not preserve category order: %+v", fetched.Categories)
	}
}

// Category deletion strips the tag from entries but never deletes or modifies
// the entries themselves (their text/notes/timings stay intact).
func TestDeleteCategory_PreservesEntries(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	catID := createCategoryHelper(t, h, tok, "Sport", "tag")

	created := newEntryWithCategories(t, h, tok, catID)
	entryID := newEntryHelper(t, h, tok, created.Text, created.CategoryIDs)

	del := serve(h, jsonReq(t, "DELETE", "/api/v1/categories/"+catID, tok, nil))
	if del.Code != http.StatusNoContent {
		t.Fatalf("delete category: expected 204, got %d (body=%s)", del.Code, del.Body.String())
	}

	got := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+entryID, tok, nil))
	var e entryResp
	decodeBody(t, got, &e)
	if len(e.Categories) != 0 {
		t.Errorf("expected the deleted category removed from the entry, got %+v", e.Categories)
	}
	if e.ActivityText != created.Text {
		t.Errorf("entry text must survive category deletion, got %q", e.ActivityText)
	}
}

// newEntryWithCategories creates an entry tagged with the given categories and
// returns its response snapshot (text + ids) for later assertions.
func newEntryWithCategories(t *testing.T, h *Handler, tok string, categoryIDs ...string) struct {
	Text        string
	CategoryIDs []string
} {
	t.Helper()
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
		"id": v7(), "activity_text": "Gym", "category_ids": categoryIDs,
		"started_at": "2026-07-27T09:00:00Z",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("create entry: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	ids := make([]string, 0, len(e.Categories))
	for _, c := range e.Categories {
		ids = append(ids, c.ID)
	}
	return struct {
		Text        string
		CategoryIDs []string
	}{Text: e.ActivityText, CategoryIDs: ids}
}

// newEntryHelper creates a one-hour entry with the given text/categories and
// returns its id.
func newEntryHelper(t *testing.T, h *Handler, tok, text string, categoryIDs []string) string {
	t.Helper()
	anchor := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	body := map[string]any{
		"id":            v7(),
		"activity_text": text,
		"started_at":    anchor.Format(time.RFC3339),
		"ended_at":      anchor.Add(time.Hour).Format(time.RFC3339),
	}
	if categoryIDs != nil {
		body["category_ids"] = categoryIDs
	}
	w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, body))
	if w.Code != http.StatusCreated {
		t.Fatalf("create entry: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var e entryResp
	decodeBody(t, w, &e)
	return e.ID
}

// rfc3339Add parses an RFC 3339 timestamp, adds d, and reformats it.
func rfc3339Add(s string, d time.Duration) string {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t, err = time.Parse(time.RFC3339Nano, s)
		if err != nil {
			return s
		}
	}
	return t.Add(d).Format(time.RFC3339Nano)
}
