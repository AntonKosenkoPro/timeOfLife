package config

import (
	"crypto/subtle"
	"encoding/hex"
	"os"
	"strconv"
	"strings"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
)

// ReviewAccess carries the disabled-by-default App Review exception binding
// (demo-account-access). When Enabled, exactly one existing verified
// email-created account — identified by its immutable lowercase UUID AND
// canonical lowercase email — may authenticate with a reusable keyed
// six-digit code through the ordinary otp/request + otp/verify endpoints.
// Verifier is the 32-byte HMAC-SHA256 digest over the binding (hex in
// REVIEW_CODE_VERIFIER); Key is the independent dedicated 32-byte secret
// (hex in REVIEW_CODE_KEY). No plaintext code ever enters configuration.
// Case is significant everywhere: the binding is stored verbatim and matched
// byte-exactly, so non-lowercase values are rejected at load instead of
// locking review login out silently.
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
		return invalidFieldError("REVIEW_ACCOUNT_ID", "lowercase UUID of the existing verified review account")
	}
	accountEmail := strings.TrimSpace(os.Getenv("REVIEW_ACCOUNT_EMAIL"))
	// ValidEmail accepts mixed case (the ordinary OTP path needs that), but
	// runtime matching is byte-exact on the canonical lowercase address, so
	// a non-lowercase binding would pass validation yet never match. Reject
	// it here with a startup error, consistent with the operator CLI.
	if !auth.ValidEmail(accountEmail) || accountEmail != strings.ToLower(accountEmail) {
		return invalidFieldError("REVIEW_ACCOUNT_EMAIL", "canonical lowercase email of the existing verified review account")
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
	// The dedicated key must be independent of every other configured
	// secret (design): rotation of JWT, account-status, refresh-recovery,
	// or Apple token material must never change review login, and a
	// pasted duplicate must not couple them. JWTSecret, AccountStatusSecret,
	// and both keyrings are loaded before this point, so the comparison is
	// against the live values, not copies.
	// JWT_SECRET/ACCOUNT_STATUS_SECRET are raw strings (usually 64 hex
	// chars) while key is decoded bytes: check both the configured
	// REVIEW_CODE_KEY text and its decoded form, so a pasted duplicate is
	// actually caught by the independence guarantee. The text comparison
	// is case-sensitive because both values are consumed verbatim (the
	// server secrets as raw HMAC bytes, the review key decoded) — hex that
	// differs only in case is distinct key material there, not a coupling.
	if subtleCompare(key, []byte(cfg.JWTSecret)) ||
		subtleCompare(key, []byte(cfg.AccountStatusSecret)) ||
		subtleCompare([]byte(keyHex), []byte(cfg.JWTSecret)) ||
		subtleCompare([]byte(keyHex), []byte(cfg.AccountStatusSecret)) {
		return invalidFieldError("REVIEW_CODE_KEY", "dedicated key independent of JWT_SECRET and ACCOUNT_STATUS_SECRET")
	}
	for _, ring := range []struct {
		name string
		keys [][]byte
	}{
		{"REFRESH_RECOVERY_KEYS", cfg.RecoveryKeys},
		{"APPLE_TOKEN_KEYS", cfg.AppleTokenKeys},
	} {
		for _, other := range ring.keys {
			if subtleCompare(key, other) {
				return invalidFieldError("REVIEW_CODE_KEY", "dedicated key independent of "+ring.name)
			}
		}
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
	return isZeroKey(secret)
}

// subtleCompare reports byte equality in constant time. It delegates to the
// vetted standard-library primitive (the same construction the request path
// uses), keeping security-sensitive comparison logic in one form. It is a
// startup-time guard only, not a request-path comparison.
func subtleCompare(a, b []byte) bool {
	return subtle.ConstantTimeCompare(a, b) == 1
}
