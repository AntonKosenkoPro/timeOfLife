package auth

import (
	"net/mail"
	"regexp"
)

// accountEmailRegex is the legacy address shape applied on top of the
// RFC 5321 structure check: ASCII mailbox, dotted domain with a 2+ letter
// TLD, max 254 chars. The pair is an intersection — strictly narrower than
// the regex alone for inputs like ".a@example.com" or "a..b@example.com",
// which are rejected.
var accountEmailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// ValidEmail reports whether email is an acceptable account identifier using
// the canonical server email rule: total length ≤ 254, a parseable
// RFC 5322 address structure whose parsed address equals the input
// byte-for-byte, and the ASCII mailbox/dotted-domain shape above. Matching
// is exact — no case folding, no Gmail dot/plus collapsing — so the same
// predicate selects the configured review address and ordinary accounts.
func ValidEmail(email string) bool {
	if email == "" || len(email) > 254 {
		return false
	}
	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email {
		return false
	}
	return accountEmailRegex.MatchString(email)
}

// ValidUUIDShape reports whether id has the textual 8-4-4-4-12 hex UUID
// shape. It validates shape only, not version/variant.
func ValidUUIDShape(id string) bool {
	if len(id) != 36 {
		return false
	}
	for i := 0; i < 36; i++ {
		c := id[i]
		switch {
		case i == 8 || i == 13 || i == 18 || i == 23:
			if c != '-' {
				return false
			}
		case (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'):
		default:
			return false
		}
	}
	return true
}
