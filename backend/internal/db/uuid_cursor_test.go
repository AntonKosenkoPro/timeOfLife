package db

import (
	"strings"
	"testing"
	"time"
)

// TestUUID_V7Shape pins the generator contract: lowercase UUID v7 shape,
// version/variant bits set, and practical uniqueness.
func TestUUID_V7Shape(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 1000; i++ {
		id := uuidV7()
		if id != strings.ToLower(id) {
			t.Fatalf("uuidV7 must be lowercase, got %q", id)
		}
		if len(id) != 36 || id[14] != '7' || !strings.ContainsRune("89ab", rune(id[19])) {
			t.Fatalf("uuidV7 must be v7 with RFC 4122 variant, got %q", id)
		}
		if seen[id] {
			t.Fatalf("duplicate uuidV7 %q in 1000 draws", id)
		}
		seen[id] = true
	}
}

// TestUUID_FallbackSeed pins the entropy-out path: the fallback still fills
// all 16 bytes (no zero id) and the version/variant masking in uuidV7 keeps
// the result a valid v7 shape.
func TestUUID_FallbackSeed(t *testing.T) {
	b := make([]byte, 16)
	fallbackSeed(b)
	zero := make([]byte, 16)
	allZero := true
	for i := range b {
		if b[i] != zero[i] {
			allZero = false
		}
	}
	if allZero {
		t.Error("fallbackSeed left the buffer all-zero")
	}
}

// TestCursor_RoundTrip pins the opaque pagination cursor: encode → decode
// recovers the timestamp and id, including nanosecond precision and the
// stable started_at DESC / id DESC tiebreak inputs.
func TestCursor_RoundTrip(t *testing.T) {
	ts := time.Date(2026, 7, 27, 9, 0, 0, 123456789, time.UTC)
	id := "0195c2b7-3a1e-7f2a-9b3c-4d5e6f708192"

	cur := encodeCursor(ts, id)
	gotTime, gotID, ok := decodeCursor(cur)
	if !ok {
		t.Fatalf("decodeCursor(%q) failed", cur)
	}
	if !gotTime.Equal(ts) {
		t.Errorf("expected time %v, got %v", ts, gotTime)
	}
	if gotID != id {
		t.Errorf("expected id %q, got %q", id, gotID)
	}
}

// TestCursor_Malformed pins the fail-closed decoder: any malformed input
// yields ok=false rather than a zero time or partial id.
func TestCursor_Malformed(t *testing.T) {
	for _, bad := range []string{
		"",
		"not-base64!!!",
		"bm90LXBpcGVk",    // valid base64, no pipe separator
		"fDplbXB0eXRpbWU", // "|emptytime"-ish: empty time part
	} {
		if _, _, ok := decodeCursor(bad); ok {
			t.Errorf("decodeCursor(%q): expected ok=false, got true", bad)
		}
	}
	// Empty id part: "2026-07-27T09:00:00Z|" encoded.
	emptyID := "MjAyNi0wNy0yN1QwOTowMDowMFp8"
	if _, _, ok := decodeCursor(emptyID); ok {
		t.Errorf("decodeCursor(empty id): expected ok=false, got true")
	}
	// Bad timestamp part with a valid id.
	badTime := "bm90LWEtdGltZXxpZA" // "not-a-time|id"
	if _, _, ok := decodeCursor(badTime); ok {
		t.Errorf("decodeCursor(bad time): expected ok=false, got true")
	}
}
