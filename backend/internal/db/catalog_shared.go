package db

import (
	"encoding/base64"
	"strings"
	"time"
)

// encodeCursor builds an opaque pagination cursor for entries (ordered by
// started_at DESC, then id DESC for a stable tiebreak). It encodes the last
// item's (started_at, id) so the next page can resume strictly below it.
func encodeCursor(t time.Time, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(t.UTC().Format(time.RFC3339Nano) + "|" + id))
}

// decodeCursor reverses encodeCursor. Returns ok=false on any malformed input.
func decodeCursor(s string) (time.Time, string, bool) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return time.Time{}, "", false
	}
	parts := strings.SplitN(string(b), "|", 2)
	if len(parts) != 2 || parts[1] == "" {
		return time.Time{}, "", false
	}
	t, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", false
	}
	return t, parts[1], true
}

// defaultEntryLimit is the page size used when a caller does not set one.
const defaultEntryLimit = 50

// maxEntryLimit caps an oversized limit to bound query cost.
const maxEntryLimit = 200

// clampLimit returns a sane page size for EntryFilter.Limit.
func clampLimit(n int) int {
	if n <= 0 {
		return defaultEntryLimit
	}
	if n > maxEntryLimit {
		return maxEntryLimit
	}
	return n
}

// ensureCategories returns a non-nil slice so categories serializes as [] not
// null when a record has no tags.
func ensureCategories(s []CategoryTag) []CategoryTag {
	if s == nil {
		return []CategoryTag{}
	}
	return s
}
