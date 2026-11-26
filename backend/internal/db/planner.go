package db

import (
	"encoding/json"
	"fmt"
	"math/big"
	"regexp"
	"strings"
	"time"
)

// ---------- Planner (day planner) ----------

// Planner task intents. Each operation carries only its intent's field: a
// rename sends no position or completion, and a Stop-driven completion sends
// only the completion date. `create` sets the initial name, position, and
// optional categories; `retag` replaces the ordered category set.
const (
	PlannerIntentCreate   = "create"
	PlannerIntentRename   = "rename"
	PlannerIntentMove     = "move"
	PlannerIntentComplete = "complete"
	PlannerIntentReopen   = "reopen"
	PlannerIntentDelete   = "delete"
	PlannerIntentRetag    = "retag"
)

// PlannerTask is the latest accepted state of one planner task. CompletedOn
// is the civil date (YYYY-MM-DD) recorded by the completing device, or nil
// when open. CategoryIDs is the optional ordered set of category ids used
// at Start (empty when the task carries none — Recents fallback applies).
// Revision is the commit-ordered per-account sequence number of
// the last accepted operation on this task. Deleted marks the terminal
// deletion marker — it never clears.
type PlannerTask struct {
	ID          string    `json:"id"`
	UserID      string    `json:"-"`
	Name        string    `json:"name"`
	PositionKey string    `json:"position_key"`
	CompletedOn *string   `json:"completed_on"`
	CategoryIDs []string  `json:"category_ids"`
	Revision    int64     `json:"revision"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Deleted     bool      `json:"deleted"`
}

// PlannerOperation is one field-specific planner mutation. Only the intent's
// field is read; other populated fields are ignored.
type PlannerOperation struct {
	OperationID string
	TaskID      string
	Intent      string
	Name        *string
	PositionKey *string
	CompletedOn *string
	CategoryIDs []string
}

// ---------- Planner category set ----------

// encodePlannerCategoryIDs renders the ordered category set for storage (a
// JSON array TEXT column on both dialects). Nil and empty both store as
// `[]`, so reads never meet NULL.
func encodePlannerCategoryIDs(ids []string) string {
	if len(ids) == 0 {
		return "[]"
	}
	raw, err := json.Marshal(ids)
	if err != nil {
		return "[]"
	}
	return string(raw)
}

// parsePlannerCategoryIDs decodes a stored category set. Blank, `[]`, and
// malformed payloads all decode to an empty set — a corrupt set must never
// fail the task read (the feed re-converges it).
func parsePlannerCategoryIDs(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "[]" {
		return []string{}
	}
	var ids []string
	if err := json.Unmarshal([]byte(raw), &ids); err != nil {
		return []string{}
	}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if id != "" {
			out = append(out, id)
		}
	}
	return out
}

// ---------- Position keys ----------

// Position keys are exact decimals: a zero-padded 6-digit integer part with
// an optional fraction of up to 32 digits and no trailing zeros. Display
// order is (position_key, id) compared byte-wise, which equals numeric order
// for canonical keys — so ORDER BY position_key works directly and every
// device resolves ties identically. Clients allocate keys without rewriting
// the list; see the shared fixtures in backend/api/openapi.yaml.
var plannerKeyRegex = regexp.MustCompile(`^[0-9]{6}(\.[0-9]*[1-9])?$`)

const (
	plannerKeyIntWidth = 6
	plannerKeyFracMax  = 32
	plannerKeyMaxLen   = plannerKeyIntWidth + 1 + plannerKeyFracMax
	plannerKeyInitial  = "500000"
)

// ValidatePositionKey reports whether key is a canonical position key.
func ValidatePositionKey(key string) bool {
	if len(key) == 0 || len(key) > plannerKeyMaxLen {
		return false
	}
	return plannerKeyRegex.MatchString(key)
}

// splitPlannerKey splits a validated key into its integer part (exactly 6
// digits) and its fraction digits (possibly empty).
func splitPlannerKey(key string) (intPart, frac string) {
	if i := strings.IndexByte(key, '.'); i >= 0 {
		return key[:i], key[i+1:]
	}
	return key, ""
}

// plannerKeyValue parses a validated key into its exact scaled-integer
// value: intPart concatenated with frac padded right to scale digits.
func plannerKeyValue(key string, scale int) *big.Int {
	intPart, frac := splitPlannerKey(key)
	digits := intPart + frac + strings.Repeat("0", scale-len(frac))
	v, _ := new(big.Int).SetString(digits, 10)
	return v
}

// formatPlannerKey renders a scaled-integer magnitude (value * 10^scale)
// back into canonical key form: 6-digit zero-padded integer, fraction
// without trailing zeros (or no fraction when it is all zeros).
func formatPlannerKey(mag *big.Int, scale int) string {
	digits := mag.String()
	if len(digits) <= scale {
		digits = strings.Repeat("0", scale-len(digits)+1) + digits
	}
	intDigits := digits[:len(digits)-scale]
	fracDigits := ""
	if scale > 0 {
		fracDigits = strings.TrimRight(digits[len(digits)-scale:], "0")
	}
	for len(intDigits) < plannerKeyIntWidth {
		intDigits = "0" + intDigits
	}
	if fracDigits == "" {
		return intDigits
	}
	return intDigits + "." + fracDigits
}

// midpointPlannerKey returns the exact decimal midpoint of two validated
// keys (before < after). The average of two terminating decimals always
// terminates, so the result is exact — never floating-point.
func midpointPlannerKey(before, after string) (string, error) {
	if before >= after {
		return "", fmt.Errorf("planner midpoint: before %q must be less than after %q", before, after)
	}
	_, fracA := splitPlannerKey(before)
	_, fracB := splitPlannerKey(after)
	scale := len(fracA)
	if len(fracB) > scale {
		scale = len(fracB)
	}
	sum := new(big.Int).Add(plannerKeyValue(before, scale), plannerKeyValue(after, scale))
	if sum.Bit(0) == 0 {
		return formatPlannerKey(new(big.Int).Rsh(sum, 1), scale), nil
	}
	// Odd sum: one more decimal digit (5 * sum is always even).
	return formatPlannerKey(new(big.Int).Mul(sum, big.NewInt(5)), scale+1), nil
}

// incrementPlannerKey returns intPart(before)+1 for an append after the last
// row. The fraction never survives an append: the result stays short.
func incrementPlannerKey(before string) (string, error) {
	intPart, _ := splitPlannerKey(before)
	v, _ := new(big.Int).SetString(intPart, 10)
	v.Add(v, big.NewInt(1))
	if len(v.String()) > plannerKeyIntWidth {
		return "", fmt.Errorf("planner position space exhausted above %q", before)
	}
	out := v.String()
	for len(out) < plannerKeyIntWidth {
		out = "0" + out
	}
	return out, nil
}

// decrementPlannerKey returns intPart(after)-1 for a prepend before the
// first row.
func decrementPlannerKey(after string) (string, error) {
	intPart, _ := splitPlannerKey(after)
	v, _ := new(big.Int).SetString(intPart, 10)
	if v.Sign() == 0 {
		return "", fmt.Errorf("planner position space exhausted below %q", after)
	}
	v.Sub(v, big.NewInt(1))
	out := v.String()
	for len(out) < plannerKeyIntWidth {
		out = "0" + out
	}
	return out, nil
}

// AllocatePositionKey returns a key strictly between before and after (nil
// either side for an unbounded end), following the shared fixtures:
// empty → "500000"; append → integer +1; prepend → integer −1; otherwise
// the exact decimal midpoint. before/after must be canonical keys with
// before < after when both are present.
func AllocatePositionKey(before, after *string) (string, error) {
	switch {
	case before == nil && after == nil:
		return plannerKeyInitial, nil
	case after == nil:
		if !ValidatePositionKey(*before) {
			return "", fmt.Errorf("planner allocate: invalid before key %q", *before)
		}
		return incrementPlannerKey(*before)
	case before == nil:
		if !ValidatePositionKey(*after) {
			return "", fmt.Errorf("planner allocate: invalid after key %q", *after)
		}
		return decrementPlannerKey(*after)
	default:
		if !ValidatePositionKey(*before) {
			return "", fmt.Errorf("planner allocate: invalid before key %q", *before)
		}
		if !ValidatePositionKey(*after) {
			return "", fmt.Errorf("planner allocate: invalid after key %q", *after)
		}
		return midpointPlannerKey(*before, *after)
	}
}
