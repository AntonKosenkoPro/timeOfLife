package db

import (
	"crypto/rand"
	"fmt"
)

// uuidV7 generates a UUID v7 (time-ordered) using crypto/rand.
// Format: 8-4-4-4-12 hex digits with version 7 and variant bits.
func uuidV7() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)

	// Set version to 7 (time-ordered)
	b[6] = (b[6] & 0x0f) | 0x70
	// Set variant to RFC 4122
	b[8] = (b[8] & 0x3f) | 0x80

	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
