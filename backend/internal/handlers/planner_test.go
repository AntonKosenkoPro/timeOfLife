package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// plannerResp mirrors the PlannerTask response for test assertions.
type plannerResp struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	PositionKey string  `json:"position_key"`
	CompletedOn *string `json:"completed_on"`
	Revision    int64   `json:"revision"`
	Deleted     bool    `json:"deleted"`
}

// plannerOp posts one planner operation and returns the recorder.
func plannerOp(t *testing.T, h *Handler, tok string, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	return serve(h, jsonReq(t, "POST", "/api/v1/planner/operations", tok, body))
}

func TestPlanner_CreateValidation(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	cases := []struct {
		name string
		body map[string]any
		want string
	}{
		{"missing intent", map[string]any{"operation_id": v7(), "task_id": v7()}, "intent"},
		{"bad intent", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "nuke"}, "intent"},
		{"bad operation id", map[string]any{"operation_id": "nope", "task_id": v7(), "intent": "delete"}, "operation_id"},
		{"bad task id", map[string]any{"operation_id": v7(), "task_id": "nope", "intent": "delete"}, "task_id"},
		{"create without name", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "create", "position_key": "500000"}, "name"},
		{"create blank name", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "create", "name": "  ", "position_key": "500000"}, "name"},
		{"create without key", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "create", "name": "Read"}, "position_key"},
		{"create bad key", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "create", "name": "Read", "position_key": "abc"}, "position_key"},
		{"create trailing-zero key", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "create", "name": "Read", "position_key": "500000.50"}, "position_key"},
		{"complete without date", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "complete"}, "completed_on"},
		{"complete bad date", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "complete", "completed_on": "2026-02-30"}, "completed_on"},
		{"complete datetime", map[string]any{"operation_id": v7(), "task_id": v7(), "intent": "complete", "completed_on": "2026-11-25T10:00:00Z"}, "completed_on"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := plannerOp(t, h, tok, tc.body)
			if w.Code != http.StatusUnprocessableEntity {
				t.Fatalf("expected 422, got %d (%s)", w.Code, w.Body.String())
			}
			var resp struct {
				Error struct {
					Details map[string]string `json:"details"`
				} `json:"error"`
			}
			decodeBody(t, w, &resp)
			if _, ok := resp.Error.Details[tc.want]; !ok {
				t.Fatalf("expected details[%q], got %v", tc.want, resp.Error.Details)
			}
		})
	}
}

func TestPlanner_CreateRenameCompleteDeleteFlow(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	opID, taskID := v7(), v7()

	w := plannerOp(t, h, tok, map[string]any{
		"operation_id": opID, "task_id": taskID,
		"intent": "create", "name": "Read", "position_key": "500000",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d (%s)", w.Code, w.Body.String())
	}
	var created plannerResp
	decodeBody(t, w, &created)
	if created.Revision != 1 || created.CompletedOn != nil || created.Deleted {
		t.Fatalf("unexpected created state: %+v", created)
	}

	// Lost-response replay of the same operation id: 200 with identical state.
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": opID, "task_id": taskID,
		"intent": "create", "name": "Read", "position_key": "500000",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("replay: expected 200, got %d (%s)", w.Code, w.Body.String())
	}
	var replayed plannerResp
	decodeBody(t, w, &replayed)
	if replayed.Revision != 1 || replayed.ID != taskID {
		t.Fatalf("replay must return stored state: %+v", replayed)
	}

	// Rename then complete converge on the same task with rising revisions.
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID, "intent": "rename", "name": "Read books",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("rename: expected 201, got %d (%s)", w.Code, w.Body.String())
	}
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID, "intent": "complete", "completed_on": "2026-11-25",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("complete: expected 201, got %d (%s)", w.Code, w.Body.String())
	}
	var done plannerResp
	decodeBody(t, w, &done)
	if done.Revision != 3 || done.Name != "Read books" || done.CompletedOn == nil || *done.CompletedOn != "2026-11-25" {
		t.Fatalf("unexpected completed state: %+v", done)
	}

	// Delete is terminal: renames and delayed creates answer 410.
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID, "intent": "delete",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("delete: expected 201, got %d (%s)", w.Code, w.Body.String())
	}
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID, "intent": "rename", "name": "Late",
	})
	if w.Code != http.StatusGone || errCode(t, w) != "planner_gone" {
		t.Fatalf("rename after delete: expected 410 planner_gone, got %d (%s)", w.Code, w.Body.String())
	}
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID,
		"intent": "create", "name": "Resurrect", "position_key": "500001",
	})
	if w.Code != http.StatusGone {
		t.Fatalf("delayed create after delete: expected 410, got %d (%s)", w.Code, w.Body.String())
	}

	// Unknown ids are 404, not 410.
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": v7(), "intent": "rename", "name": "Ghost",
	})
	if w.Code != http.StatusNotFound {
		t.Fatalf("rename unknown: expected 404, got %d (%s)", w.Code, w.Body.String())
	}
}

func TestPlanner_CreateCollision(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)
	taskID := v7()

	w := plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID,
		"intent": "create", "name": "Read", "position_key": "500000",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d", w.Code)
	}
	w = plannerOp(t, h, tok, map[string]any{
		"operation_id": v7(), "task_id": taskID,
		"intent": "create", "name": "Other", "position_key": "500001",
	})
	if w.Code != http.StatusConflict || errCode(t, w) != "planner_conflict" {
		t.Fatalf("expected 409 planner_conflict, got %d (%s)", w.Code, w.Body.String())
	}
}

func TestPlanner_FeedPagination(t *testing.T) {
	h, _, _, tok := newCatalogHandler(t)

	var ids []string
	for i, kv := range []struct{ name, key string }{
		{"A", "500000"}, {"B", "500001"}, {"C", "500002"},
	} {
		_ = i
		id := v7()
		ids = append(ids, id)
		w := plannerOp(t, h, tok, map[string]any{
			"operation_id": v7(), "task_id": id,
			"intent": "create", "name": kv.name, "position_key": kv.key,
		})
		if w.Code != http.StatusCreated {
			t.Fatalf("create %d: expected 201, got %d", i, w.Code)
		}
	}

	get := func(query string) (int, map[string]any) {
		t.Helper()
		w := serve(h, jsonReq(t, "GET", "/api/v1/planner/feed"+query, tok, nil))
		var resp map[string]any
		decodeBody(t, w, &resp)
		return w.Code, resp
	}
	code, page1 := get("?limit=2")
	if code != http.StatusOK {
		t.Fatalf("feed: expected 200, got %d", code)
	}
	changes := page1["changes"].([]any)
	if len(changes) != 2 || page1["watermark_revision"].(float64) != 3 || page1["has_more"] != true {
		t.Fatalf("page1 wrong: %+v", page1)
	}
	first := changes[0].(map[string]any)
	if first["revision"].(float64) != 1 {
		t.Fatalf("feed must be revision-ordered: %+v", first)
	}
	code, page2 := get("?after_revision=2&limit=2")
	if code != http.StatusOK {
		t.Fatalf("feed page2: expected 200, got %d", code)
	}
	if len(page2["changes"].([]any)) != 1 {
		t.Fatalf("page2 wrong: %+v", page2)
	}
	if _, ok := page2["has_more"]; ok {
		t.Fatalf("exhausted feed must omit has_more: %+v", page2)
	}
	code, _ = get("?after_revision=nope")
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("bad after_revision: expected 422, got %d", code)
	}

	_ = ids
}

func TestPlanner_Isolation(t *testing.T) {
	h, store, _, _ := newCatalogHandler(t)
	_, tokA, _, tokB := twoUsers(t, store)

	taskID := v7()
	w := plannerOp(t, h, tokA, map[string]any{
		"operation_id": v7(), "task_id": taskID,
		"intent": "create", "name": "Read", "position_key": "500000",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d", w.Code)
	}
	// Other account sees an empty feed and cannot touch the task.
	w = serve(h, jsonReq(t, "GET", "/api/v1/planner/feed", tokB, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("feed: expected 200, got %d", w.Code)
	}
	var feed struct {
		Changes   []plannerResp `json:"changes"`
		Watermark int64         `json:"watermark_revision"`
	}
	decodeBody(t, w, &feed)
	if len(feed.Changes) != 0 || feed.Watermark != 0 {
		t.Fatalf("account B must see nothing: %+v", feed)
	}
	w = plannerOp(t, h, tokB, map[string]any{
		"operation_id": v7(), "task_id": taskID, "intent": "delete",
	})
	if w.Code != http.StatusNotFound {
		t.Fatalf("cross-account delete: expected 404, got %d", w.Code)
	}
	// Unauthenticated requests are rejected before any planner logic.
	w = serve(h, jsonReq(t, "GET", "/api/v1/planner/feed", "", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous feed: expected 401, got %d", w.Code)
	}
}
