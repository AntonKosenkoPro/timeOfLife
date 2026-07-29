package handlers

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// Epic 1 introduces the catalog/entries endpoints. Unlike the auth handlers
// (inline boolean validators → 400 invalid_body), these use a field→message
// accumulator that returns 422 validation_error with details = {field: message},
// matching the OpenAPI ValidationError response. Error codes are declared as
// constants to keep the string literals in one place.

const (
	codeValidation      = "validation_error"
	codeNotFound        = "not_found"
	codeConflict        = "conflict"
	codeActivityExists  = "activity_exists"
	codeCategoryExists  = "category_exists"
	codeActivityMissing = "activity_not_found"
)

// validColors is the fixed color palette. iOS Theme.* must use these keys.
var validColors = map[string]bool{
	"blue": true, "green": true, "orange": true, "pink": true,
	"purple": true, "red": true, "teal": true, "yellow": true,
	"indigo": true, "mint": true, "brown": true, "gray": true,
}

// validIcons is the allowed SF Symbol set for activities. iOS must align.
var validIcons = map[string]bool{
	"figure.walk": true, "figure.run": true, "figure.strengthtraining": true,
	"figure.yoga": true, "figure.cycling": true, "figure.swimming": true,
	"figure.soccer": true, "figure.basketball": true, "figure.tennis": true,
	"figure.gymnastics": true, "figure.mindandbody": true, "figure.core.training": true,
	"book": true, "books": true, "graduationcap": true,
	"laptopcomputer": true, "desktopcomputer": true, "keyboard": true,
	"gamecontroller": true, "tv": true, "musicalnotes": true,
	"paintbrush": true, "briefcase": true, "house": true,
	"fork.knife": true, "cup.and.saucer": true, "moon.zzz": true,
	"car.fill": true, "airplane": true, "cart": true, "phone": true,
}

const (
	maxNameLen  = 60
	maxNotesLen = 280
)

var uuidV7Regex = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

// validateUUIDv7 reports whether id is a canonical lowercase UUID v7.
func validateUUIDv7(id string) bool {
	return uuidV7Regex.MatchString(strings.ToLower(id))
}

// validationErrs accumulates field→message pairs; the first message per field wins.
type validationErrs map[string]string

func (v validationErrs) add(field, msg string) {
	if _, ok := v[field]; !ok {
		v[field] = msg
	}
}
func (v validationErrs) ok() bool { return len(v) == 0 }

// writeValidation writes a 422 validation_error response with the field map.
func writeValidation(w http.ResponseWriter, errs validationErrs) {
	writeError(w, http.StatusUnprocessableEntity, codeValidation, "Validation failed", errs)
}

// parseRFC3339 parses an RFC 3339 timestamp.
func parseRFC3339(s string) (time.Time, bool) {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		// Fall back to the non-nano layout for whole-second inputs.
		t, err = time.Parse(time.RFC3339, s)
		if err != nil {
			return time.Time{}, false
		}
	}
	return t, true
}

// optTime is an optional, nullable timestamp: Set=false leaves it unchanged,
// Set=true with Valid=false sets NULL, Set=true with Valid=true sets Value.
// Bad=true marks a present-but-unparseable value so the validator can emit a
// 422 (UnmarshalJSON deliberately never errors, so a bad timestamp does not
// surface as a 400 invalid_body). It maps directly onto db.NullableTime.
type optTime struct {
	Set   bool
	Valid bool
	Bad   bool
	Value time.Time
}

// UnmarshalJSON is only called when the field is present in the JSON. It
// deliberately never returns an error: a present-but-unparseable value is
// recorded as Bad so the validator can emit a 422 (rather than surfacing as a
// 400 invalid_body from decodeJSON).
func (o *optTime) UnmarshalJSON(b []byte) error {
	o.Set = true
	if string(b) == "null" {
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		if t, ok := parseRFC3339(s); ok {
			o.Valid = true
			o.Value = t
			return nil
		}
	}
	o.Bad = true
	return nil
}

// requireUserID writes a 401 and returns false when the request is not authed.
func (h *Handler) requireUserID(w http.ResponseWriter, r *http.Request) (string, bool) {
	userID, ok := UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized", "Not authenticated", nil)
	}
	return userID, ok
}

// ---------- request structs ----------

type activityCreateReq struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Color       string   `json:"color"`
	Icon        string   `json:"icon"`
	Notes       string   `json:"notes"`
	CategoryIDs []string `json:"category_ids"`
}

type activityUpdateReq struct {
	Name        *string   `json:"name"`
	Color       *string   `json:"color"`
	Icon        *string   `json:"icon"`
	Notes       *string   `json:"notes"`
	CategoryIDs *[]string `json:"category_ids"`
	UpdatedAt   string    `json:"updated_at"`
}

type categoryCreateReq struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
}

type categoryUpdateReq struct {
	Name      *string `json:"name"`
	Color     *string `json:"color"`
	UpdatedAt string  `json:"updated_at"`
}

type entryCreateReq struct {
	ID         string  `json:"id"`
	ActivityID *string `json:"activity_id"`
	StartedAt  string  `json:"started_at"`
	EndedAt    *string `json:"ended_at"`
}

type entryUpdateReq struct {
	StartedAt *string `json:"started_at"`
	EndedAt   optTime `json:"ended_at"`
	UpdatedAt string  `json:"updated_at"`
}

// ---------- field validators ----------

func validateName(field, name string, errs validationErrs) {
	n := strings.TrimSpace(name)
	if n == "" {
		errs.add(field, "Name must not be empty")
	} else if len(n) > maxNameLen {
		errs.add(field, "Name must be 60 characters or fewer")
	}
}

func validateNotes(n string, errs validationErrs) {
	if len(n) > maxNotesLen {
		errs.add("notes", "Notes must be 280 characters or fewer")
	}
}

func validateColor(c string, errs validationErrs) {
	if !validColors[c] {
		errs.add("color", "Color is not in the allowed palette")
	}
}

func validateIcon(i string, errs validationErrs) {
	if !validIcons[i] {
		errs.add("icon", "Icon is not in the allowed set")
	}
}

func validateID(id string, errs validationErrs) {
	if !validateUUIDv7(id) {
		errs.add("id", "id must be a valid UUID v7")
	}
}

func validateTimestamp(field, s string, required bool, errs validationErrs) {
	if s == "" {
		if required {
			errs.add(field, field+" is required")
		}
		return
	}
	if _, ok := parseRFC3339(s); !ok {
		errs.add(field, field+" must be a valid RFC 3339 timestamp")
	}
}
