package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

// writeCatalogStoreErr maps a db store error (returned alongside its record)
// to the Epic 1 error contract. record carries the server's current version
// (for conflict) or the winning record (for *_exists), used to populate details.
func (h *Handler) writeCatalogStoreErr(w http.ResponseWriter, record any, err error, action string) {
	switch {
	case errors.Is(err, db.ErrNotFound):
		writeError(w, http.StatusNotFound, codeNotFound, "Not found", nil)
	case errors.Is(err, db.ErrConflict):
		writeError(w, http.StatusConflict, codeConflict,
			"Outdated version; a newer record exists on the server.", versionDetails(record))
	case errors.Is(err, db.ErrActivityExists):
		writeError(w, http.StatusConflict, codeActivityExists,
			"An activity with this name already exists.", idNameDetails(record))
	case errors.Is(err, db.ErrCategoryExists):
		writeError(w, http.StatusConflict, codeCategoryExists,
			"A category with this name already exists.", idNameDetails(record))
	case errors.Is(err, db.ErrActivityNotFound):
		writeError(w, http.StatusNotFound, codeActivityMissing, "Referenced activity not found", nil)
	case errors.Is(err, db.ErrDuplicateImport):
		writeError(w, http.StatusConflict, codeDuplicateImport,
			"An entry with this source and source_ref already exists.", nil)
	case errors.Is(err, db.ErrEndBeforeStart):
		writeValidation(w, validationErrs{"ended_at": "ended_at must be after started_at"})
	case errors.Is(err, db.ErrInvalidCategoryID):
		writeValidation(w, validationErrs{"category_ids": "One or more categories do not exist"})
	default:
		h.logger.Error(action+" failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "An internal error occurred", nil)
	}
}

// versionDetails returns {updated_at: <server's current version>} for a 409 conflict.
func versionDetails(record any) any {
	var t time.Time
	switch v := record.(type) {
	case db.Activity:
		t = v.UpdatedAt
	case db.Category:
		t = v.UpdatedAt
	case db.Entry:
		t = v.UpdatedAt
	default:
		return nil
	}
	return map[string]string{"updated_at": t.UTC().Format(time.RFC3339Nano)}
}

// idNameDetails returns {id, name} of the winning record for a *_exists 409.
func idNameDetails(record any) any {
	switch v := record.(type) {
	case db.Activity:
		return map[string]string{"id": v.ID, "name": v.Name}
	case db.Category:
		return map[string]string{"id": v.ID, "name": v.Name}
	}
	return nil
}

// ---------- Activities ----------

// ListActivities handles GET /activities (?q= typeahead filter, ?modified_since= delta pull).
func (h *Handler) ListActivities(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	var modifiedSince *time.Time
	if v := q.Get("modified_since"); v != "" {
		t, ok := parseRFC3339(v)
		if !ok {
			writeValidation(w, validationErrs{"modified_since": "modified_since must be a valid RFC 3339 timestamp"})
			return
		}
		modifiedSince = &t
	}
	acts, err := h.store.ListActivities(r.Context(), userID, q.Get("q"), modifiedSince)
	if err != nil {
		h.logger.Error("list activities failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "An internal error occurred", nil)
		return
	}
	if acts == nil {
		acts = []db.Activity{}
	}
	writeJSON(w, http.StatusOK, acts)
}

// CreateActivity handles POST /activities (idempotent on id).
func (h *Handler) CreateActivity(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req activityCreateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid create activity body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	name := strings.TrimSpace(req.Name)
	errs := validationErrs{}
	validateID(req.ID, errs)
	validateName("name", name, errs)
	validateNotes(req.Notes, errs)
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	a := db.Activity{ID: req.ID, UserID: userID, Name: name, Notes: req.Notes}
	created, isNew, err := h.store.CreateActivity(r.Context(), a, req.CategoryIDs)
	if err != nil {
		h.writeCatalogStoreErr(w, created, err, "create activity")
		return
	}
	status := http.StatusCreated
	if !isNew {
		status = http.StatusOK
	}
	h.logger.Info("activity saved", "userID", userID, "activityID", created.ID, "created", isNew)
	writeJSON(w, status, created)
}

// GetActivity handles GET /activities/{id}.
func (h *Handler) GetActivity(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	a, err := h.store.GetActivity(r.Context(), userID, chi.URLParam(r, "id"))
	if err != nil {
		h.writeCatalogStoreErr(w, a, err, "get activity")
		return
	}
	writeJSON(w, http.StatusOK, a)
}

// UpdateActivity handles PATCH /activities/{id} (partial, LWW).
func (h *Handler) UpdateActivity(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req activityUpdateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid update activity body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	errs := validationErrs{}
	if req.Name != nil {
		n := strings.TrimSpace(*req.Name)
		validateName("name", n, errs)
		req.Name = &n
	}
	if req.Notes != nil {
		validateNotes(*req.Notes, errs)
	}
	if req.CategoryIDs != nil {
		for _, cid := range *req.CategoryIDs {
			if !validateUUIDv7(cid) {
				errs.add("category_ids", "category_ids must be valid UUIDs")
				break
			}
		}
	}
	validateTimestamp("updated_at", req.UpdatedAt, true, errs)
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	updatedAt, _ := parseRFC3339(req.UpdatedAt)
	patch := db.ActivityPatch{
		Name: req.Name, Notes: req.Notes,
		CategoryIDs: req.CategoryIDs, UpdatedAt: updatedAt,
	}
	updated, err := h.store.UpdateActivity(r.Context(), userID, chi.URLParam(r, "id"), patch)
	if err != nil {
		h.writeCatalogStoreErr(w, updated, err, "update activity")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// DeleteActivity handles DELETE /activities/{id} (hard delete, cascades).
func (h *Handler) DeleteActivity(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteActivity(r.Context(), userID, chi.URLParam(r, "id")); err != nil {
		h.writeCatalogStoreErr(w, nil, err, "delete activity")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---------- Categories ----------

// ListCategories handles GET /categories (ordered by name).
func (h *Handler) ListCategories(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	cats, err := h.store.ListCategories(r.Context(), userID)
	if err != nil {
		h.logger.Error("list categories failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "An internal error occurred", nil)
		return
	}
	if cats == nil {
		cats = []db.Category{}
	}
	writeJSON(w, http.StatusOK, cats)
}

// CreateCategory handles POST /categories (idempotent on id).
func (h *Handler) CreateCategory(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req categoryCreateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid create category body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	name := strings.TrimSpace(req.Name)
	icon := strings.ToLower(req.Icon)
	errs := validationErrs{}
	validateID(req.ID, errs)
	validateName("name", name, errs)
	validateIcon(icon, errs)
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	c := db.Category{ID: req.ID, UserID: userID, Name: name, Icon: icon}
	created, isNew, err := h.store.CreateCategory(r.Context(), c)
	if err != nil {
		h.writeCatalogStoreErr(w, created, err, "create category")
		return
	}
	status := http.StatusCreated
	if !isNew {
		status = http.StatusOK
	}
	h.logger.Info("category saved", "userID", userID, "categoryID", created.ID, "created", isNew)
	writeJSON(w, status, created)
}

// GetCategory handles GET /categories/{id}.
func (h *Handler) GetCategory(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	c, err := h.store.GetCategory(r.Context(), userID, chi.URLParam(r, "id"))
	if err != nil {
		h.writeCatalogStoreErr(w, c, err, "get category")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// UpdateCategory handles PATCH /categories/{id} (partial, LWW).
func (h *Handler) UpdateCategory(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req categoryUpdateReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.Warn("invalid update category body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	errs := validationErrs{}
	if req.Name != nil {
		n := strings.TrimSpace(*req.Name)
		validateName("name", n, errs)
		req.Name = &n
	}
	if req.Icon != nil {
		i := strings.ToLower(*req.Icon)
		validateIcon(i, errs)
		req.Icon = &i
	}
	validateTimestamp("updated_at", req.UpdatedAt, true, errs)
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	updatedAt, _ := parseRFC3339(req.UpdatedAt)
	patch := db.CategoryPatch{Name: req.Name, Icon: req.Icon, UpdatedAt: updatedAt}
	updated, err := h.store.UpdateCategory(r.Context(), userID, chi.URLParam(r, "id"), patch)
	if err != nil {
		h.writeCatalogStoreErr(w, updated, err, "update category")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// DeleteCategory handles DELETE /categories/{id} (hard delete; entries unaffected).
func (h *Handler) DeleteCategory(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteCategory(r.Context(), userID, chi.URLParam(r, "id")); err != nil {
		h.writeCatalogStoreErr(w, nil, err, "delete category")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
