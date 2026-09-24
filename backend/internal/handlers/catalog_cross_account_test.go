package handlers

import (
	"encoding/json"
	"net/http"
	"testing"
)

// Cross-account id collision (fix-cross-account-id-collision): record ids are
// a global PRIMARY KEY while the pre-checks and the winner re-query are
// user-scoped. A POST whose id exists under a *different* user must answer
// 409 category_exists with nil/absent details — never {"id":"","name":""} —
// so no client ever builds an empty-id winner route.
func TestCrossAccountCategoryIDCollision_NilWinnerDetails(t *testing.T) {
	h, store, _, _ := newCatalogHandler(t)
	_, tokA, _, tokB := twoUsers(t, store)
	id := v7()

	w1 := serve(h, jsonReq(t, "POST", "/api/v1/categories", tokA, map[string]any{
		"id": id, "name": "Sport", "icon": "tag",
	}))
	if w1.Code != http.StatusCreated {
		t.Fatalf("user A create: expected 201, got %d (body=%s)", w1.Code, w1.Body.String())
	}

	// Same id under user B with a distinct name: the failure is purely the
	// global id collision, not a name clash.
	w2 := serve(h, jsonReq(t, "POST", "/api/v1/categories", tokB, map[string]any{
		"id": id, "name": "Other", "icon": "briefcase",
	}))
	if w2.Code != http.StatusConflict {
		t.Fatalf("user B create: expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	var resp struct {
		Error struct {
			Code    string          `json:"code"`
			Details json.RawMessage `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w2, &resp)
	if resp.Error.Code != "category_exists" {
		t.Fatalf("expected code category_exists, got %q", resp.Error.Code)
	}
	if len(resp.Error.Details) == 0 || string(resp.Error.Details) == "null" {
		return // nil/absent details: the unresolvable-collision form
	}
	var details map[string]string
	if err := json.Unmarshal(resp.Error.Details, &details); err != nil {
		t.Fatalf("details must decode as an object when present: %v (body=%s)", err, w2.Body.String())
	}
	for k, v := range details {
		if v == "" {
			t.Errorf("details must never carry an empty-string %q (body=%s)", k, w2.Body.String())
		}
	}
	if _, ok := details["id"]; ok {
		t.Errorf("unresolvable cross-account collision must carry nil details, got %+v", details)
	}
}

// The populated-winner path is untouched: a same-user name collision still
// answers 409 category_exists with the winner's id and name.
func TestCategoryNameCollision_PopulatedWinnerDetails(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	w1 := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": "Sport", "icon": "tag",
	}))
	if w1.Code != http.StatusCreated {
		t.Fatalf("first create: expected 201, got %d (body=%s)", w1.Code, w1.Body.String())
	}
	var created struct {
		ID string `json:"id"`
	}
	decodeBody(t, w1, &created)

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/categories", tok, map[string]any{
		"id": v7(), "name": "sport", "icon": "briefcase",
	}))
	if w2.Code != http.StatusConflict {
		t.Fatalf("name clash: expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	var resp struct {
		Error struct {
			Code    string            `json:"code"`
			Details map[string]string `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w2, &resp)
	if resp.Error.Code != "category_exists" {
		t.Fatalf("expected code category_exists, got %q", resp.Error.Code)
	}
	if resp.Error.Details["id"] != created.ID || resp.Error.Details["name"] != "Sport" {
		t.Errorf("populated winner must round-trip, got %+v", resp.Error.Details)
	}
}

// Cross-user entry id disambiguation contract (fix-cross-account-id-collision):
// a cross-user id POST trips the global entries PK, which maps to 409
// duplicate_import, and a GET of that id as the second user answers not_found
// (the row belongs to the other user). The client relies on this pair to tell
// a true same-account replay from a cross-user id collision.
func TestCrossUserEntryIDCollision_DisambiguationContract(t *testing.T) {
	h, store, _, _ := newCatalogHandler(t)
	_, tokA, _, tokB := twoUsers(t, store)
	id := v7()

	w1 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tokA, map[string]any{
		"id": id, "activity_text": "Gym", "started_at": "2026-07-27T09:00:00Z",
	}))
	if w1.Code != http.StatusCreated {
		t.Fatalf("user A create: expected 201, got %d (body=%s)", w1.Code, w1.Body.String())
	}

	w2 := serve(h, jsonReq(t, "POST", "/api/v1/entries", tokB, map[string]any{
		"id": id, "activity_text": "Read", "started_at": "2026-07-27T10:00:00Z",
	}))
	if w2.Code != http.StatusConflict {
		t.Fatalf("user B push: expected 409, got %d (body=%s)", w2.Code, w2.Body.String())
	}
	if code := errCode(t, w2); code != "duplicate_import" {
		t.Fatalf("expected code duplicate_import, got %q", code)
	}

	get := serve(h, jsonReq(t, "GET", "/api/v1/entries/"+id, tokB, nil))
	if get.Code != http.StatusNotFound {
		t.Fatalf("user B GET: expected 404, got %d (body=%s)", get.Code, get.Body.String())
	}
	if code := errCode(t, get); code != "not_found" {
		t.Fatalf("expected code not_found, got %q", code)
	}
}
