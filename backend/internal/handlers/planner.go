package handlers

import (
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

const (
	codePlannerConflict = "planner_conflict"
	codePlannerGone     = "planner_gone"
)

// plannerKeyPattern mirrors the OpenAPI position_key pattern: a zero-padded
// 6-digit integer part with an optional fraction of up to 32 digits and no
// trailing zeros. db.ValidatePositionKey is the canonical check; this
// handler-side shape check keeps the 422 field mapping precise.
var plannerKeyPattern = regexp.MustCompile(`^[0-9]{6}(\.[0-9]*[1-9])?$`)

const plannerKeyMaxLen = 6 + 1 + 32

// writePlannerStoreErr maps a planner store error to the planner error
// contract: 404 unknown id, 409 live-id create collision (with the server's
// current task in details), 410 terminal delete. Anything else is a 500.
func (h *Handler) writePlannerStoreErr(w http.ResponseWriter, r *http.Request, err error, taskID string, task db.PlannerTask, action string) {
	switch {
	case errors.Is(err, db.ErrNotFound):
		writeError(w, http.StatusNotFound, codeNotFound, "Not found", nil)
	case errors.Is(err, db.ErrPlannerConflict):
		writeError(w, http.StatusConflict, codePlannerConflict,
			"A planner task with this id already exists.", map[string]string{
				"id":           task.ID,
				"name":         task.Name,
				"position_key": task.PositionKey,
				"revision":     strconv.FormatInt(task.Revision, 10),
				"completed_on": completedOnDetail(task.CompletedOn),
				// The iOS details decoder only represents strings, so the
				// ordered set travels comma-joined (UUIDs never contain a
				// comma) and parses back losslessly.
				"category_ids": strings.Join(task.CategoryIDs, ","),
				// Notes travel verbatim (the details map is strings-only
				// and notes are already text); empty stays empty.
				"notes":      task.Notes,
				"deleted":    strconv.FormatBool(task.Deleted),
				"created_at": task.CreatedAt.UTC().Format(time.RFC3339Nano),
				"updated_at": task.UpdatedAt.UTC().Format(time.RFC3339Nano),
			})
	case errors.Is(err, db.ErrPlannerGone):
		writeError(w, http.StatusGone, codePlannerGone,
			"This planner task was deleted.", map[string]string{"id": taskID})
	default:
		h.writeInternalError(w, r, action+" failed", err)
	}
}

type plannerOperationReq struct {
	OperationID string    `json:"operation_id"`
	TaskID      string    `json:"task_id"`
	Intent      string    `json:"intent"`
	Name        *string   `json:"name"`
	PositionKey *string   `json:"position_key"`
	CompletedOn *string   `json:"completed_on"`
	CategoryIDs *[]string `json:"category_ids"`
	Notes       *string   `json:"notes"`
}

// validatePlannerDate reports whether s is a real civil calendar date
// (YYYY-MM-DD), e.g. rejecting 2026-02-30 and non-dates alike.
func validatePlannerDate(s string) bool {
	if len(s) != len("2006-01-02") {
		return false
	}
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return false
	}
	return t.Format("2006-01-02") == s
}

// ApplyPlannerOperation handles POST /planner/operations (field-specific,
// idempotent on operation_id, terminal deletes).
func (h *Handler) ApplyPlannerOperation(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	var req plannerOperationReq
	if err := decodeJSON(r, &req); err != nil {
		h.logger.WarnContext(r.Context(), "invalid planner operation body", "error", err)
		writeError(w, http.StatusBadRequest, "invalid_body", "Invalid request body", nil)
		return
	}
	errs := validationErrs{}
	validatePlannerIDs(req, errs)
	switch req.Intent {
	case db.PlannerIntentCreate, db.PlannerIntentRename:
		if req.Name == nil {
			errs.add("name", "name is required")
		} else {
			n := strings.TrimSpace(*req.Name)
			validateName("name", n, errs)
			req.Name = &n
		}
		if req.Intent == db.PlannerIntentCreate && req.PositionKey == nil {
			errs.add("position_key", "position_key is required")
		}
	case db.PlannerIntentMove:
		if req.PositionKey == nil {
			errs.add("position_key", "position_key is required")
		}
	case db.PlannerIntentComplete:
		if req.CompletedOn == nil || *req.CompletedOn == "" {
			errs.add("completed_on", "completed_on is required")
		} else if !validatePlannerDate(*req.CompletedOn) {
			errs.add("completed_on", "completed_on must be a valid civil date (YYYY-MM-DD)")
		}
	case db.PlannerIntentRetag:
		if req.CategoryIDs == nil {
			errs.add("category_ids", "category_ids is required")
		} else {
			validatePlannerCategoryIDs(*req.CategoryIDs, errs)
		}
	case db.PlannerIntentNotes:
		if req.Notes == nil {
			errs.add("notes", "notes is required")
		} else {
			// The shared 2000-trimmed-rune bound with entry notes
			// (entries-owned-fields F1/U1): the relay trims only to
			// gate, storing the text verbatim.
			validateNotes(*req.Notes, errs)
		}
	case db.PlannerIntentReopen, db.PlannerIntentDelete:
		// No fields required; extras are ignored.
	default:
		errs.add("intent", "intent must be one of create, rename, move, complete, reopen, delete, retag, notes")
	}
	if req.PositionKey != nil && (req.Intent == db.PlannerIntentCreate || req.Intent == db.PlannerIntentMove) {
		k := strings.TrimSpace(*req.PositionKey)
		if len(k) > plannerKeyMaxLen || !plannerKeyPattern.MatchString(k) {
			errs.add("position_key", "position_key must be an exact decimal like 500000 or 500000.5")
		} else {
			req.PositionKey = &k
		}
	}
	// `create` accepts an optional initial category set and optional
	// initial notes (the repush path re-posts the live task with both);
	// `retag`/`notes` already validated their required fields above.
	// Anything else ignores extras.
	if req.Intent == db.PlannerIntentCreate && req.CategoryIDs != nil {
		validatePlannerCategoryIDs(*req.CategoryIDs, errs)
	}
	if req.Intent == db.PlannerIntentCreate && req.Notes != nil {
		validateNotes(*req.Notes, errs)
	}
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}

	var categories []string
	if req.CategoryIDs != nil {
		categories = *req.CategoryIDs
	}
	op := db.PlannerOperation{
		OperationID: strings.ToLower(req.OperationID),
		TaskID:      strings.ToLower(req.TaskID),
		Intent:      req.Intent,
		Name:        req.Name,
		PositionKey: req.PositionKey,
		CompletedOn: req.CompletedOn,
		CategoryIDs: categories,
		Notes:       req.Notes,
	}
	task, isNew, err := h.store.ApplyPlannerOperation(r.Context(), userID, op)
	if err != nil {
		h.writePlannerStoreErr(w, r, err, op.TaskID, task, "apply planner operation")
		return
	}
	status := http.StatusCreated
	if !isNew {
		status = http.StatusOK
	}
	h.logger.InfoContext(r.Context(), "planner operation applied", "userID", userID,
		"taskID", task.ID, "intent", op.Intent, "revision", task.Revision, "created", isNew)
	writeJSON(w, status, task)
}

// completedOnDetail renders the nullable civil completion date for the
// string-only 409 details map (the iOS details decoder only represents
// strings — numeric/bool values would decode as null).
func completedOnDetail(completedOn *string) string {
	if completedOn == nil {
		return ""
	}
	return *completedOn
}

// validatePlannerCategoryIDs validates one ordered category set: every id
// must be a UUID (the loose planner set keeps unknown ids — unlike entry
// `category_ids`, no catalog existence check; Stop prunes dead tags).
func validatePlannerCategoryIDs(ids []string, errs validationErrs) {
	for _, id := range ids {
		if strings.TrimSpace(id) == "" || !validateUUIDv7(id) {
			errs.add("category_ids", "category_ids must be valid UUIDs")
			return
		}
	}
}

// validatePlannerIDs validates the two UUID fields under their own names
// (validateID reports to "id", which fits neither field here).
func validatePlannerIDs(req plannerOperationReq, errs validationErrs) {
	if !validateUUIDv7(req.OperationID) {
		errs.add("operation_id", "operation_id must be a valid UUID v7")
	}
	if !validateUUIDv7(req.TaskID) {
		errs.add("task_id", "task_id must be a valid UUID v7")
	}
}

// ListPlannerFeed handles GET /planner/feed (revision-ordered pages with a
// committed watermark).
func (h *Handler) ListPlannerFeed(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.requireUserID(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	errs := validationErrs{}
	var after int64
	if v := q.Get("after_revision"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil || n < 0 {
			errs.add("after_revision", "after_revision must be a non-negative integer")
		} else {
			after = n
		}
	}
	limit := 50
	if v := q.Get("limit"); v != "" {
		n, ok := parseLimitParam(v, 200, errs)
		if ok {
			limit = n
		}
	}
	if !errs.ok() {
		writeValidation(w, errs)
		return
	}
	tasks, watermark, hasMore, err := h.store.ListPlannerFeed(r.Context(), userID, after, limit)
	if err != nil {
		h.writeInternalError(w, r, "list planner feed failed", err)
		return
	}
	if tasks == nil {
		tasks = []db.PlannerTask{}
	}
	resp := map[string]any{
		"changes":            tasks,
		"watermark_revision": watermark,
	}
	if hasMore {
		resp["has_more"] = true
	}
	writeJSON(w, http.StatusOK, resp)
}
