// Package auth provides JWT access token and OTP code services.
package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"strings"
)

// reviewAccessDomainTag is the fixed purpose/version domain bound into the
// review-code MAC. It separates the review verifier from every other keyed or
// unkeyed digest in the system (ordinary OTP hashes, refresh hashes, Apple
// digests), so rotating those materials can never affect review login.
const reviewAccessDomainTag = "lifio-review-access/v1"

// ReviewAccessKeySize is the required size of the dedicated review-code key
// in bytes (32 bytes, rendered as 64 hex characters in configuration).
const ReviewAccessKeySize = 32

// reviewFieldSeparator delimits the MAC input fields. NUL cannot appear in a
// UUID, an email address, or a six-digit code, so the encoding is unambiguous.
const reviewFieldSeparator = "\x00"

// ValidReviewCodeShape reports whether code is exactly six ASCII digits —
// the only shape the shipping iOS code field can submit.
func ValidReviewCodeShape(code string) bool {
	if len(code) != 6 {
		return false
	}
	for i := 0; i < len(code); i++ {
		if code[i] < '0' || code[i] > '9' {
			return false
		}
	}
	return true
}

// ComputeReviewVerifier derives the stored verifier for a review binding:
// HMAC-SHA256 over the fixed domain tag followed by NUL-delimited canonical
// fields (immutable account UUID, canonical email, code). The result is a
// 64-character lowercase hex digest. The plaintext code never leaves the
// operator's private storage: configuration, databases, and logs hold only
// this verifier plus the dedicated key.
func ComputeReviewVerifier(key []byte, accountID, accountEmail, code string) (string, error) {
	if len(key) != ReviewAccessKeySize || isZeroReviewKey(key) {
		return "", errors.New("review verifier: key must be 32 non-trivial random bytes")
	}
	if accountID == "" || accountEmail == "" {
		return "", errors.New("review verifier: account binding must not be empty")
	}
	if !ValidReviewCodeShape(code) {
		return "", errors.New("review verifier: code must be exactly six ASCII digits")
	}
	mac := hmac.New(sha256.New, key)
	for _, field := range []string{reviewAccessDomainTag, accountID, accountEmail, code} {
		mac.Write([]byte(field))
		mac.Write([]byte(reviewFieldSeparator))
	}
	return hex.EncodeToString(mac.Sum(nil)), nil
}

// VerifyReviewCode checks a submitted code against the stored hex verifier
// using constant-time comparison. Any malformed input (short/trivial key,
// malformed verifier, wrong code shape) fails closed without distinguishing
// the cause.
func VerifyReviewCode(key []byte, verifierHex, accountID, accountEmail, code string) bool {
	if len(key) != ReviewAccessKeySize || isZeroReviewKey(key) {
		return false
	}
	verifier, err := hex.DecodeString(strings.TrimSpace(verifierHex))
	if err != nil || len(verifier) != sha256.Size {
		return false
	}
	if accountID == "" || accountEmail == "" || !ValidReviewCodeShape(code) {
		return false
	}
	mac := hmac.New(sha256.New, key)
	for _, field := range []string{reviewAccessDomainTag, accountID, accountEmail, code} {
		mac.Write([]byte(field))
		mac.Write([]byte(reviewFieldSeparator))
	}
	return subtle.ConstantTimeCompare(mac.Sum(nil), verifier) == 1
}

// isZeroReviewKey rejects the all-zero placeholder: a guessable key would
// defeat the keyed construction (generate with `openssl rand -hex 32`,
// which never emits it).
func isZeroReviewKey(key []byte) bool {
	for _, b := range key {
		if b != 0 {
			return false
		}
	}
	return true
}
