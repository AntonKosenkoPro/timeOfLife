// Package auth provides JWT access token and OTP code services.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"math/big"
	"time"
)

const (
	// DefaultOTPExpiry is the default duration before an OTP code expires.
	DefaultOTPExpiry = 10 * time.Minute
	// DefaultOTPMaxAttempts is the default number of failed attempts before an OTP is exhausted.
	DefaultOTPMaxAttempts = 5
	otpCodeLength         = 6
)

// OTPService handles one-time password generation and verification.
type OTPService struct {
	expiry      time.Duration
	maxAttempts int
}

// NewOTPService creates a new OTPService with the given expiry and max attempts.
// If expiry is zero, DefaultOTPExpiry is used.
// If maxAttempts is zero, DefaultOTPMaxAttempts is used.
func NewOTPService(expiry time.Duration, maxAttempts int) *OTPService {
	if expiry <= 0 {
		expiry = DefaultOTPExpiry
	}
	if maxAttempts <= 0 {
		maxAttempts = DefaultOTPMaxAttempts
	}
	return &OTPService{
		expiry:      expiry,
		maxAttempts: maxAttempts,
	}
}

// GenerateOTP creates a random 6-digit code and returns the plaintext code
// together with its SHA-256 hex hash.
func (s *OTPService) GenerateOTP() (code, hash string, err error) {
	maxVal := big.NewInt(1_000_000)
	n, err := rand.Int(rand.Reader, maxVal)
	if err != nil {
		return "", "", fmt.Errorf("generate OTP: %w", err)
	}
	code = fmt.Sprintf("%06d", n.Int64())
	hash = otpHash(code)
	return code, hash, nil
}

// VerifyCode compares a plaintext code against a stored SHA-256 hash using
// constant-time comparison. It returns true if they match.
func (s *OTPService) VerifyCode(plainCode, hash string) bool {
	computed := otpHash(plainCode)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(hash)) == 1
}

// Expiry returns the configured OTP expiry duration.
func (s *OTPService) Expiry() time.Duration {
	return s.expiry
}

// MaxAttempts returns the configured maximum number of OTP verification attempts.
func (s *OTPService) MaxAttempts() int {
	return s.maxAttempts
}

func otpHash(code string) string {
	h := sha256.Sum256([]byte(code))
	return hex.EncodeToString(h[:])
}
