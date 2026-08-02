package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

// ---------- Entries ----------

// ListEntries handles GET /entries (filters: from,to,activity_id,category_id,limit,cursor).
func (h *Handler) ListEntries(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	errs := validationErrs{}
	f := db.EntryFilter{
		ActivityID: q.Get("activity_id"),
		CategoryID: q.Get("category_id"),
		Cursor:     q.Get("cursor"),
	}
	if v := q.Get("from"); v != "" {
		if t, ok := parseRFC3339(v); ok {
			f.From = &t
		} else {
			errs.add("from", "from must be a valid RFC 3339 timestamp")
		}
	}
	if v := q.Get("to"); v != "" {
		if t, ok := parseRFC3339(v); ok {
			f.To = &t
		} else {
			errs.add("to", "to must be a valid RFC 3339 timestamp")
		}
	}
	if v := q.Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 200 {
			errs.add("limit", "limit must be between 1 and 200")
		} else {
			f.Limit = n
		}
	}
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	items, next, err := h.store.ListEntries(r.Context(), userID, f)
	if err != nil {
		h.logger.Error("list entries failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "An internal error occurred", nil)
		return
	}
	if items == nil {
		items = []db.Entry{}
	}
	resp := map[string]any{"items": items}
	if next != "" {
		resp["next_cursor"] = next
	}
	writeJSON(w, http.StatusOK, resp)
}

// CreateEntry handles POST /entries (idempotent on id).
func (h *Handler) CreateEntry(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req entryCreateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid create entry body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	// An empty ended_at string means "no value" (running timer), not a present
	// zero-time timestamp. Normalize it to omitted so it is not stored as
	// year-0001 with a hugely negative duration_seconds.
	if req.EndedAt != nil && *req.EndedAt == "" {
		req.EndedAt = nil
	}

	errs := validationErrs{}
	validateID(req.ID, errs)
	validateTimestamp("started_at", req.StartedAt, true, errs)
	if req.ActivityID == nil {
		errs.add("activity_id", "activity_id is required")
	} else if !validateUUIDv7(*req.ActivityID) {
		errs.add("activity_id", "activity_id must be a valid UUID v7")
	}
	if req.EndedAt != nil {
		validateTimestamp("ended_at", *req.EndedAt, false, errs)
	}
	// ended_at must be after started_at when both are present and valid. The
	// store independently guards the partial-PATCH merged value (and direct
	// store calls); here we surface the plain both-present case with precise
	// field-level details for the common create path.
	if req.EndedAt != nil && req.StartedAt != "" {
		if st, ok1 := parseRFC3339(req.StartedAt); ok1 {
			if et, ok2 := parseRFC3339(*req.EndedAt); ok2 && !et.After(st) {
				errs.add("ended_at", "ended_at must be after started_at")
			}
		}
	}
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	startedAt, _ := parseRFC3339(req.StartedAt)
	var endedAt *time.Time
	if req.EndedAt != nil {
		et, _ := parseRFC3339(*req.EndedAt)
		endedAt = &et
	}
	e := db.Entry{
		ID:         req.ID,
		UserID:     userID,
		ActivityID: req.ActivityID,
		StartedAt:  startedAt,
		EndedAt:    endedAt,
	}
	created, isNew, err := h.store.CreateEntry(r.Context(), e)
	if err != nil {
		h.writeCatalogStoreErr(w, created, err, "create entry")
		return
	}
	status := http.StatusCreated
	if !isNew {
		status = http.StatusOK
	}
	h.logger.Info("entry saved", "userID", userID, "entryID", created.ID, "created", isNew)
	writeJSON(w, status, created)
}

// GetEntry handles GET /entries/{id}.
func (h *Handler) GetEntry(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	e, err := h.store.GetEntry(r.Context(), userID, chi.URLParam(r, "id"))
	if err != nil {
		h.writeCatalogStoreErr(w, e, err, "get entry")
		return
	}
	writeJSON(w, http.StatusOK, e)
}

// UpdateEntry handles PATCH /entries/{id} (partial, LWW; recomputes duration).
func (h *Handler) UpdateEntry(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req entryUpdateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid update entry body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}

	errs := validationErrs{}
	if req.StartedAt != nil {
		validateTimestamp("started_at", *req.StartedAt, false, errs)
	}
	if req.EndedAt.Set && req.EndedAt.Bad {
		errs.add("ended_at", "ended_at must be a valid RFC 3339 timestamp")
	}
	validateTimestamp("updated_at", req.UpdatedAt, true, errs)
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	var startedAt *time.Time
	if req.StartedAt != nil {
		st, _ := parseRFC3339(*req.StartedAt)
		startedAt = &st
	}
	var endedAt db.NullableTime
	if req.EndedAt.Set {
		endedAt = db.NullableTime{Set: true, Valid: req.EndedAt.Valid, Value: req.EndedAt.Value}
	}
	updatedAt, _ := parseRFC3339(req.UpdatedAt)
	patch := db.EntryPatch{StartedAt: startedAt, EndedAt: endedAt, UpdatedAt: updatedAt}
	updated, err := h.store.UpdateEntry(r.Context(), userID, chi.URLParam(r, "id"), patch)
	if err != nil {
		h.writeCatalogStoreErr(w, updated, err, "update entry")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// DeleteEntry handles DELETE /entries/{id} (hard delete).
func (h *Handler) DeleteEntry(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteEntry(r.Context(), userID, chi.URLParam(r, "id")); err != nil {
		h.writeCatalogStoreErr(w, nil, err, "delete entry")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
