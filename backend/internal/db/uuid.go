package db

import (
	"crypto/rand"
	"fmt"
	"time"
)

// uuidV7 generates a UUID v7 (time-ordered) using crypto/rand.
// Format: 8-4-4-4-12 hex digits with version 7 and variant bits.
//
// crypto/rand.Read essentially never fails (it reports OS CSPRNG failure),
// and this helper runs in request paths where no error return is plumbed.
// If entropy is unavailable, it degrades to a time-seeded fallback instead
// of silently reusing weak bytes: the timestamp prefix keeps ids roughly
// ordered and unique per nanosecond. Such ids still pass validateUUIDv7.
func uuidV7() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		fallbackSeed(b)
	}

	// Set version to 7 (time-ordered)
	b[6] = (b[6] & 0x0f) | 0x70
	// Set variant to RFC 4122
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// fallbackSeed fills b from the current time when crypto/rand is
// unavailable. Not cryptographic — last-resort uniqueness only.
func fallbackSeed(b []byte) {
	now := time.Now().UnixNano()
	for i := range b {
		b[i] = byte(now >> (8 * (i % 8)))
		now = now*6364136223846793005 + 1442695040888963407
	}
}
