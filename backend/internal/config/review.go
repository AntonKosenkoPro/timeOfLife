package config

import (
	"encoding/hex"
	"os"
	"strconv"
	"strings"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
)

// ReviewAccess carries the disabled-by-default App Review exception binding
// (demo-account-access). When Enabled, exactly one existing verified
// email-created account — identified by its immutable UUID AND canonical
// email — may authenticate with a reusable keyed six-digit code through the
// ordinary otp/request + otp/verify endpoints. Verifier is the 32-byte
// HMAC-SHA256 digest over the binding (hex in REVIEW_CODE_VERIFIER); Key is
// the independent dedicated 32-byte secret (hex in REVIEW_CODE_KEY). No
// plaintext code ever enters configuration.
type ReviewAccess struct {
	Enabled      bool
	AccountID    string
	AccountEmail string
	Verifier     []byte
	Key          []byte
}

// loadReviewAccess reads the REVIEW_* variables into cfg. Disabled (the
// default, and any non-true spelling) requires and validates nothing, so
// ordinary deployments never touch review material. Enabled requires the
// full binding with strict shape validation; every failure names the field
// but never the value.
func loadReviewAccess(cfg *Config) error {
	raw := strings.TrimSpace(os.Getenv("REVIEW_ACCESS_ENABLED"))
	if raw == "" {
		return nil
	}
	enabled, err := strconv.ParseBool(raw)
	if err != nil {
		return invalidFieldError("REVIEW_ACCESS_ENABLED", "boolean (0/1, true/false)")
	}
	if !enabled {
		return nil
	}

	accountID := strings.TrimSpace(os.Getenv("REVIEW_ACCOUNT_ID"))
	if !auth.ValidUUIDShape(accountID) {
		return invalidFieldError("REVIEW_ACCOUNT_ID", "UUID of the existing verified review account")
	}
	accountEmail := strings.TrimSpace(os.Getenv("REVIEW_ACCOUNT_EMAIL"))
	if !auth.ValidEmail(accountEmail) {
		return invalidFieldError("REVIEW_ACCOUNT_EMAIL", "canonical email of the existing verified review account")
	}
	verifierHex := strings.TrimSpace(os.Getenv("REVIEW_CODE_VERIFIER"))
	verifier, err := decodeReviewSecret("REVIEW_CODE_VERIFIER", verifierHex)
	if err != nil {
		return err
	}
	keyHex := strings.TrimSpace(os.Getenv("REVIEW_CODE_KEY"))
	key, err := decodeReviewSecret("REVIEW_CODE_KEY", keyHex)
	if err != nil {
		return err
	}
	if subtleCompare(verifier, key) {
		return invalidFieldError("REVIEW_CODE_KEY", "dedicated key independent of the verifier")
	}

	cfg.Review = ReviewAccess{
		Enabled:      true,
		AccountID:    accountID,
		AccountEmail: accountEmail,
		Verifier:     verifier,
		Key:          key,
	}
	return nil
}

// decodeReviewSecret decodes one 64-hex-char review secret into 32 bytes,
// rejecting malformed, short, non-hex, and all-zero placeholder values
// without ever echoing the value.
func decodeReviewSecret(name, raw string) ([]byte, error) {
	if raw == "" {
		return nil, requiredFieldError(name)
	}
	secret, err := hex.DecodeString(raw)
	if err != nil || len(secret) != auth.ReviewAccessKeySize {
		return nil, invalidFieldError(name, "64 hex chars (32 bytes; generate with `openssl rand -hex 32`)")
	}
	if isZeroReviewSecret(secret) {
		return nil, invalidFieldError(name, "non-trivial 32-byte value (all-zero value rejected)")
	}
	return secret, nil
}

func isZeroReviewSecret(secret []byte) bool {
	for _, b := range secret {
		if b != 0 {
			return false
		}
	}
	return true
}

// subtleCompare reports byte equality without branching on content. It is a
// startup-time guard only (not a request-path comparison); using it keeps the
// verifier/key independence check free of value-dependent timing.
func subtleCompare(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}
