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
// to the catalog error contract. record carries the server's current version
// (for conflict) or the winning record (for *_exists), used to populate details.
func (h *Handler) writeCatalogStoreErr(w http.ResponseWriter, record any, err error, action string) {
	switch {
	case errors.Is(err, db.ErrNotFound):
		writeError(w, http.StatusNotFound, codeNotFound, "Not found", nil)
	case errors.Is(err, db.ErrConflict):
		writeError(w, http.StatusConflict, codeConflict,
			"Outdated version; a newer record exists on the server.", versionDetails(record))
	case errors.Is(err, db.ErrCategoryExists):
		writeError(w, http.StatusConflict, codeCategoryExists,
			"A category with this name already exists.", idNameDetails(record))
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
// A missing winner (unresolvable cross-account id collision — record ids are
// relay-global while the winner re-query is user-scoped) yields nil details,
// never empty-string ids/names, so no client ever builds an empty-id route.
// Populated winners are returned byte-for-byte as before.
func idNameDetails(record any) any {
	if v, ok := record.(db.Category); ok && v.ID != "" {
		return map[string]string{"id": v.ID, "name": v.Name}
	}
	return nil
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

// ---------- Deletion tombstones ----------

// ListDeletions handles GET /deletions (?deleted_since= delta pull). Returns
// the user's deletion tombstones ordered by deleted_at ASC; a nil result
// serializes as [] so the client never decodes null.
func (h *Handler) ListDeletions(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var deletedSince *time.Time
	if v := r.URL.Query().Get("deleted_since"); v != "" {
		t, ok := parseRFC3339(v)
		if !ok {
			writeValidation(w, validationErrs{"deleted_since": "deleted_since must be a valid RFC 3339 timestamp"})
			return
		}
		deletedSince = &t
	}
	tombstones, err := h.store.ListDeletions(r.Context(), userID, deletedSince)
	if err != nil {
		h.logger.Error("list deletions failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal_error", "An internal error occurred", nil)
		return
	}
	if tombstones == nil {
		tombstones = []db.Tombstone{}
	}
	writeJSON(w, http.StatusOK, tombstones)
}
