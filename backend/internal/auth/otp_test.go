package auth

import (
	"strings"
	"testing"
	"time"
)

func TestOTPService_GenerateOTP_Returns6DigitCode(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	code, hash, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP returned error: %v", err)
	}
	if len(code) != 6 {
		t.Errorf("expected code length 6, got %d", len(code))
	}
	for _, c := range code {
		if c < '0' || c > '9' {
			t.Errorf("unexpected non-digit character %c in code", c)
		}
	}
	if hash == "" {
		t.Fatal("hash should not be empty")
	}
}

func TestOTPService_GenerateOTP_ReturnsDifferentCodes(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	code1, _, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("first GenerateOTP returned error: %v", err)
	}

	code2, _, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("second GenerateOTP returned error: %v", err)
	}

	if code1 == code2 {
		t.Error("expected different codes on successive calls, but got the same")
	}
}

func TestOTPService_VerifyCode_MatchesCorrectCode(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	code, hash, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP returned error: %v", err)
	}

	if !s.VerifyCode(code, hash) {
		t.Error("VerifyCode returned false for correct code")
	}
}

func TestOTPService_VerifyCode_RejectsWrongCode(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	_, hash, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP returned error: %v", err)
	}

	if s.VerifyCode("000000", hash) {
		t.Error("VerifyCode returned true for wrong code")
	}
}

func TestOTPService_DefaultExpiry(t *testing.T) {
	t.Parallel()

	s := NewOTPService(0, 0)

	if s.Expiry() != DefaultOTPExpiry {
		t.Errorf("expected default expiry %v, got %v", DefaultOTPExpiry, s.Expiry())
	}
}

func TestOTPService_DefaultMaxAttempts(t *testing.T) {
	t.Parallel()

	s := NewOTPService(0, 0)

	if s.MaxAttempts() != DefaultOTPMaxAttempts {
		t.Errorf("expected default max attempts %d, got %d", DefaultOTPMaxAttempts, s.MaxAttempts())
	}
}

func TestOTPService_CustomExpiryAndMaxAttempts(t *testing.T) {
	t.Parallel()

	s := NewOTPService(5*time.Minute, 3)

	if s.Expiry() != 5*time.Minute {
		t.Errorf("expected expiry 5m, got %v", s.Expiry())
	}
	if s.MaxAttempts() != 3 {
		t.Errorf("expected max attempts 3, got %d", s.MaxAttempts())
	}
}

func TestOTPService_VerifyCode_ConstantTime(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	// Generate a known code and compute its hash
	code := "123456"
	hash := otpHash(code)

	if !s.VerifyCode(code, hash) {
		t.Error("VerifyCode returned false for correct code")
	}

	// Verify that different-length wrong codes don't panic
	if s.VerifyCode("12345", hash) {
		t.Error("VerifyCode returned true for short code")
	}
	if s.VerifyCode("1234567", hash) {
		t.Error("VerifyCode returned true for long code")
	}
}

func TestOTPService_GenerateOTP_LeadingZeros(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	// Generate many codes and verify they all have length 6 (including leading zeros)
	for i := 0; i < 100; i++ {
		code, _, err := s.GenerateOTP()
		if err != nil {
			t.Fatalf("GenerateOTP returned error: %v", err)
		}
		if len(code) != 6 {
			t.Errorf("expected code length 6, got %d: %q", len(code), code)
		}
		// Verify all characters are digits
		for _, c := range code {
			if c < '0' || c > '9' {
				t.Errorf("unexpected character %c in code %q", c, code)
			}
		}
	}
}

func TestOTPService_VerifyCode_EmptyCode(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	_, hash, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP returned error: %v", err)
	}

	if s.VerifyCode("", hash) {
		t.Error("VerifyCode returned true for empty code")
	}
}

func TestOTPService_VerifyCode_NonDigitCode(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	_, hash, err := s.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP returned error: %v", err)
	}

	if s.VerifyCode("abc123", hash) {
		t.Error("VerifyCode returned true for non-digit code")
	}
}

func TestOTPService_GenerateOTP_CodeInRange(t *testing.T) {
	t.Parallel()

	s := NewOTPService(10*time.Minute, 5)

	for i := 0; i < 50; i++ {
		code, _, err := s.GenerateOTP()
		if err != nil {
			t.Fatalf("GenerateOTP returned error: %v", err)
		}
		// Code should be between 000000 and 999999
		if strings.TrimLeft(code, "0") == "" {
			// code is all zeros, that's fine
			continue
		}
		if len(strings.TrimLeft(code, "0")) > 6 {
			t.Errorf("code %q seems out of range", code)
		}
	}
}
