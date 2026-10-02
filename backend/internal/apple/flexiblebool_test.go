package apple

import (
	"encoding/json"
	"testing"
)

// NOTE (fix #96): AppleSignIn (handlers/auth.go:461-462) currently issues
// sessions with emailVerified=true regardless of the parsed claim, so the
// stakes of this fail-closed parsing are availability (reject vs. accept the
// token), not trust escalation. It future-proofs the flag for when the
// verified bit gates something.
func TestFlexibleBool_AcceptsKnownWireShapes(t *testing.T) {
	for _, tc := range []struct {
		name string
		raw  string
		want bool
	}{
		{"bool true", `true`, true},
		{"string true", `"true"`, true},
		{"number 1", `1`, true},
		{"bool false", `false`, false},
		{"string false", `"false"`, false},
		{"number 0", `0`, false},
		{"null", `null`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var b flexibleBool
			if err := json.Unmarshal([]byte(tc.raw), &b); err != nil {
				t.Fatalf("UnmarshalJSON(%s): unexpected error: %v", tc.raw, err)
			}
			if bool(b) != tc.want {
				t.Errorf("UnmarshalJSON(%s) = %v, want %v", tc.raw, bool(b), tc.want)
			}
		})
	}
}

// Unknown email_verified shapes must fail verification loudly (ErrInvalidToken
// → 401 invalid_apple_token) instead of silently downgrading to false.
func TestFlexibleBool_RejectsGarbageShapes(t *testing.T) {
	for _, tc := range []struct {
		name string
		raw  string
	}{
		{"unknown string", `"yes"`},
		{"unknown number", `2`},
		{"object", `{}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var b flexibleBool
			if err := json.Unmarshal([]byte(tc.raw), &b); err == nil {
				t.Errorf("UnmarshalJSON(%s): expected error, got value %v", tc.raw, bool(b))
			}
		})
	}
}

// A garbage email_verified shape must fail the whole claims parse, which is
// what turns into ErrInvalidToken at Verify time.
func TestClaims_RejectsGarbageEmailVerified(t *testing.T) {
	var c Claims
	raw := `{"sub":"sub-1","email":"x@example.com","email_verified":"yes"}`
	if err := json.Unmarshal([]byte(raw), &c); err == nil {
		t.Error("expected claims unmarshal to fail for garbage email_verified, got nil")
	}
}
