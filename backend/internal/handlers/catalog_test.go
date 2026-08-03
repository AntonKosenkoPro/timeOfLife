package handlers

import (
	"net/http"
	"testing"
	"time"
)

func TestCatalog_NoAuth_Returns401(t *testing.T) {
	h, _, _, _ := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "GET", "/api/v1/activities", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("list: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "POST", "/api/v1/activities", "", map[string]any{"id": v7(), "name": "Gym"}))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("create: expected 401, got %d", w.Code)
	}
	w = serve(h, jsonReq(t, "GET", "/api/v1/activities/x", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("get: expected 401, got %d", w.Code)
	}
}

func TestCreateActivity_Success(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym", "notes": "leg day",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var a activityResp
	decodeBody(t, w, &a)
	if a.Name != "Gym" || a.Notes != "leg day" {
		t.Errorf("unexpected activity: %+v", a)
	}
}

func TestCreateActivity_ValidationErrors(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "",
	}))
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
	if _, ok := resp.Error.Details["name"]; !ok {
		t.Errorf("expected name in details, got %+v", resp.Error.Details)
	}
}

func TestCreateActivity_RuneCountName(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	// 60 Cyrillic characters = 120 bytes — must pass (rune count ≤ 60).
	sixtyRunes := ""
	for i := 0; i < 60; i++ {
		sixtyRunes += "я"
	}
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": sixtyRunes,
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("60 Cyrillic chars: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}

	// 61 Cyrillic characters = 122 bytes — must fail (rune count > 60).
	sixtyOneRunes := sixtyRunes + "я"
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": sixtyOneRunes,
	}))
	if w2.Code != http.StatusUnprocessableEntity {
		t.Fatalf("61 Cyrillic chars: expected 422, got %d (body=%s)", w2.Code, w2.Body.String())
	}
}

func TestCreateActivity_RuneCountNotes(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	// 280 Cyrillic characters = 560 bytes — must pass.
	notes := ""
	for i := 0; i < 280; i++ {
		notes += "я"
	}
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Test", "notes": notes,
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("280 Cyrillic notes: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}

	// 281 Cyrillic characters — must fail.
	notes281 := notes + "я"
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Test", "notes": notes281,
	}))
	if w2.Code != http.StatusUnprocessableEntity {
		t.Fatalf("281 Cyrillic notes: expected 422, got %d (body=%s)", w2.Code, w2.Body.String())
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

func TestCreateActivity_IdempotentReplay(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	id := v7()
	body := map[string]any{"id": id, "name": "Run"}

	w1 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, body))
	if w1.Code != http.StatusCreated {
		t.Fatalf("first POST: expected 201, got %d", w1.Code)
	}

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, body))
	if w2.Code != http.StatusOK {
		t.Fatalf("replay POST: expected 200, got %d", w2.Code)
	}
	var a activityResp
	decodeBody(t, w2, &a)
	if a.ID != id {
		t.Errorf("expected same id %q, got %q", id, a.ID)
	}
}

func TestCreateActivity_NameCollision(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	body := map[string]any{"id": v7(), "name": "Gym"}
	w1 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, body))
	if w1.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", w1.Code)
	}

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "gym",
	}))
	if w2.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	if code := errCode(t, w2); code != "activity_exists" {
		t.Errorf("expected code activity_exists, got %q", code)
	}
}

func TestListActivities(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	for _, n := range []string{"Gym", "Read", "Walk"} {
		w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
			"id": v7(), "name": n,
		}))
		if w.Code != http.StatusCreated {
			t.Fatalf("create %q: expected 201, got %d", n, w.Code)
		}
	}

	w := serve(h, jsonReq(t, "GET", "/api/v1/activities", tok, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var list []activityResp
	decodeBody(t, w, &list)
	if len(list) != 3 {
		t.Errorf("expected 3 activities, got %d", len(list))
	}
}

func TestGetActivity_NotFound(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "GET", "/api/v1/activities/"+v7(), tok, nil))
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
	if code := errCode(t, w); code != "not_found" {
		t.Errorf("expected code not_found, got %q", code)
	}
}

func TestUpdateActivity_LWWConflict(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym",
	}))
	var a activityResp
	decodeBody(t, w, &a)

	stale, _ := time.Parse(time.RFC3339, a.UpdatedAt)
	stale = stale.Add(-time.Second)
	w2 := serve(h, jsonReq(t, "PATCH", "/api/v1/activities/"+a.ID, tok, map[string]any{
		"name": "Gym2", "updated_at": stale.Format(time.RFC3339),
	}))
	if w2.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	if code := errCode(t, w2); code != "conflict" {
		t.Errorf("expected code conflict, got %q", code)
	}
}

func TestUpdateActivity_Success(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym",
	}))
	var a activityResp
	decodeBody(t, w, &a)

	newer, _ := time.Parse(time.RFC3339, a.UpdatedAt)
	newer = newer.Add(time.Second)
	w2 := serve(h, jsonReq(t, "PATCH", "/api/v1/activities/"+a.ID, tok, map[string]any{
		"name": "Gym2", "updated_at": newer.Format(time.RFC3339),
	}))
	if w2.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	var updated activityResp
	decodeBody(t, w2, &updated)
	if updated.Name != "Gym2" {
		t.Errorf("expected name Gym2, got %q", updated.Name)
	}
}

func TestDeleteActivity(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym",
	}))
	var a activityResp
	decodeBody(t, w, &a)

	wd := serve(h, jsonReq(t, "DELETE", "/api/v1/activities/"+a.ID, tok, nil))
	if wd.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", wd.Code)
	}

	wd2 := serve(h, jsonReq(t, "DELETE", "/api/v1/activities/"+a.ID, tok, nil))
	if wd2.Code != http.StatusNotFound {
		t.Errorf("expected 404 on second delete, got %d", wd2.Code)
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

func TestActivityCategoryOrder_RoundTrip(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	createCategory := func(name, icon string) string {
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

	firstID := createCategory("Sport", "tag")
	secondID := createCategory("Work", "briefcase")
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym", "category_ids": []string{secondID, firstID},
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("create activity: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var created activityResp
	decodeBody(t, w, &created)
	if len(created.Categories) != 2 || created.Categories[0].ID != secondID || created.Categories[1].ID != firstID {
		t.Fatalf("expected category order [%s %s], got %+v", secondID, firstID, created.Categories)
	}
	if created.Categories[0].Icon != "briefcase" || created.Categories[1].Icon != "tag" {
		t.Errorf("expected ordered category icons, got %+v", created.Categories)
	}

	got := serve(h, jsonReq(t, "GET", "/api/v1/activities/"+created.ID, tok, nil))
	if got.Code != http.StatusOK {
		t.Fatalf("get activity: expected 200, got %d", got.Code)
	}
	var fetched activityResp
	decodeBody(t, got, &fetched)
	if len(fetched.Categories) != 2 || fetched.Categories[0].ID != secondID || fetched.Categories[1].ID != firstID {
		t.Errorf("GET did not preserve category order: %+v", fetched.Categories)
	}
}
