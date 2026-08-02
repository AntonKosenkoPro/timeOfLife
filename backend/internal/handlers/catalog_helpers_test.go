package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

const testJWTSecret = "test-secret-key-at-least-32-bytes!!"

// v7 generates a valid UUID v7 for request bodies (client-generated ids).
func v7() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x70
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// mintBearer creates a user and a valid access token for it.
func mintBearer(t *testing.T, store db.Store, email string) (userID, token string) {
	t.Helper()
	user, err := store.UpsertUser(context.Background(), email)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	ts := auth.NewTokenService(testJWTSecret, 15*time.Minute, 7*24*time.Hour)
	tok, err := ts.CreateAccessToken(user.ID, user.Email)
	if err != nil {
		t.Fatalf("CreateAccessToken: %v", err)
	}
	return user.ID, tok
}

// jsonReq builds an authenticated JSON request.
func jsonReq(t *testing.T, method, path, token string, body any) *http.Request {
	t.Helper()
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		r = bytes.NewReader(b)
	}
	req := httptest.NewRequest(method, path, r)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return req
}

// catalogRouter mounts the catalog/entries routes behind AuthMiddleware, so
// tests exercise the real routing + auth + handler stack (chi.URLParam works
// natively; no withID shim needed).
func catalogRouter(h *Handler) http.Handler {
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) {
		r.Group(func(r chi.Router) {
			r.Use(h.AuthMiddleware)
			r.Get("/activities", h.ListActivities)
			r.Post("/activities", h.CreateActivity)
			r.Get("/activities/{id}", h.GetActivity)
			r.Patch("/activities/{id}", h.UpdateActivity)
			r.Delete("/activities/{id}", h.DeleteActivity)
			r.Get("/categories", h.ListCategories)
			r.Post("/categories", h.CreateCategory)
			r.Patch("/categories/{id}", h.UpdateCategory)
			r.Delete("/categories/{id}", h.DeleteCategory)
			r.Get("/entries", h.ListEntries)
			r.Post("/entries", h.CreateEntry)
			r.Get("/entries/{id}", h.GetEntry)
			r.Patch("/entries/{id}", h.UpdateEntry)
			r.Delete("/entries/{id}", h.DeleteEntry)
		})
	})
	return r
}

// serve dispatches a request through the catalog router (auth + routing).
func serve(h *Handler, req *http.Request) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	catalogRouter(h).ServeHTTP(w, req)
	return w
}

func decodeBody(t *testing.T, w *httptest.ResponseRecorder, v any) {
	t.Helper()
	if err := json.NewDecoder(w.Body).Decode(v); err != nil {
		t.Fatalf("decode response: %v (body=%s)", err, w.Body.String())
	}
}

// errCode decodes the error envelope and returns its code.
func errCode(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var resp struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
			Details any    `json:"details"`
		} `json:"error"`
	}
	decodeBody(t, w, &resp)
	return resp.Error.Code
}

// activityResp mirrors the Activity response for test assertions.
type activityResp struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Color      string `json:"color"`
	Icon       string `json:"icon"`
	Notes      string `json:"notes"`
	UpdatedAt  string `json:"updated_at"`
	Categories []struct {
		ID    string `json:"id"`
		Name  string `json:"name"`
		Color string `json:"color"`
	} `json:"categories"`
}

// entryResp mirrors the Entry response for test assertions.
type entryResp struct {
	ID              string  `json:"id"`
	ActivityID      *string `json:"activity_id"`
	ActivityName    string  `json:"activity_name"`
	DurationSeconds *int    `json:"duration_seconds"`
}

func newCatalogHandler(t *testing.T) (*Handler, db.Store, string, string) {
	t.Helper()
	store := newTestStore(t)
	h := newTestHandler(t, store)
	uid, tok := mintBearer(t, store, "catalog-handler@example.com")
	return h, store, uid, tok
}

// newActivity creates an activity for the authenticated user and returns its id.
func newActivity(t *testing.T, h *Handler, tok string) string {
	t.Helper()
	w := serve(h, jsonReq(t, "POST", "/api/v1/activities", tok, map[string]any{
		"id": v7(), "name": "Gym", "color": "blue", "icon": "figure.run",
	}))
	if w.Code != http.StatusCreated {
		t.Fatalf("create activity: expected 201, got %d (body=%s)", w.Code, w.Body.String())
	}
	var a activityResp
	decodeBody(t, w, &a)
	return a.ID
}

// newActivityWithEntries creates an activity plus n time entries for the
// authenticated user and returns the activity id. Entries use deterministic
// 1-hour slots ending at a fixed anchor so durations are reproducible.
func newActivityWithEntries(t *testing.T, h *Handler, tok string, n int) string {
	t.Helper()
	id := newActivity(t, h, tok)
	anchor := time.Date(2026, 7, 27, 9, 0, 0, 0, time.UTC)
	for i := 0; i < n; i++ {
		w := serve(h, jsonReq(t, "POST", "/api/v1/entries", tok, map[string]any{
			"id":          v7(),
			"activity_id": id,
			"started_at":  anchor.Add(time.Duration(i) * time.Hour).Format(time.RFC3339),
			"ended_at":    anchor.Add(time.Duration(i+1) * time.Hour).Format(time.RFC3339),
		}))
		if w.Code != http.StatusCreated {
			t.Fatalf("create entry %d: expected 201, got %d (body=%s)", i, w.Code, w.Body.String())
		}
	}
	return id
}

// twoUsers creates two independent users with valid bearer tokens, for
// ownership-isolation tests (R-014). Returns (userA, tokenA, userB, tokenB).
func twoUsers(t *testing.T, store db.Store) (string, string, string, string) {
	t.Helper()
	uidA, tokA := mintBearer(t, store, "owner-a@example.com")
	uidB, tokB := mintBearer(t, store, "owner-b@example.com")
	return uidA, tokA, uidB, tokB
}
