package auth

import (
	"crypto/rand"
	"encoding/hex"
	"strings"
	"testing"
)

func testReviewKey(t *testing.T) []byte {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	return key
}

// TestReviewVerifier_RoundTrip pins the happy path: a verifier computed from
// a synthetic binding verifies the same code.
func TestReviewVerifier_RoundTrip(t *testing.T) {
	key := testReviewKey(t)
	verifier, err := ComputeReviewVerifier(key, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", "004200")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	if len(verifier) != 64 {
		t.Fatalf("expected 64 hex chars, got %d", len(verifier))
	}
	if !VerifyReviewCode(key, verifier, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", "004200") {
		t.Fatal("expected correct code to verify")
	}
}

// TestReviewVerifier_WrongCodeFails covers an incorrect code, including a
// neighbour of the configured code.
func TestReviewVerifier_WrongCodeFails(t *testing.T) {
	key := testReviewKey(t)
	verifier, err := ComputeReviewVerifier(key, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", "004200")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	for _, wrong := range []string{"004201", "000000", "999999"} {
		if VerifyReviewCode(key, verifier, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", wrong) {
			t.Fatalf("expected wrong code %q to fail", wrong)
		}
	}
}

// TestReviewVerifier_LeadingZeroCodes pins that codes with leading zeros
// survive the round trip (no integer normalization anywhere).
func TestReviewVerifier_LeadingZeroCodes(t *testing.T) {
	key := testReviewKey(t)
	for _, code := range []string{"000001", "001234", "012345"} {
		verifier, err := ComputeReviewVerifier(key, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", code)
		if err != nil {
			t.Fatalf("ComputeReviewVerifier(%q): %v", code, err)
		}
		if !VerifyReviewCode(key, verifier, "b2ea21ec-6b4b-4da7-8668-a3a598a59711", "review-synthetic@example.com", code) {
			t.Fatalf("expected leading-zero code %q to verify", code)
		}
	}
}

// TestReviewVerifier_SixASCIIDigitShape pins the exact code shape: six ASCII
// digits, nothing else (no unicode digits, no whitespace, no short/long).
func TestReviewVerifier_SixASCIIDigitShape(t *testing.T) {
	for _, bad := range []string{"", "12345", "1234567", "12345a", " 12345", "12345 ", "１２３４５６", "+12345", "12 345"} {
		if ValidReviewCodeShape(bad) {
			t.Errorf("expected shape %q to be invalid", bad)
		}
		if _, err := ComputeReviewVerifier(testReviewKey(t), "id", "e@example.com", bad); err == nil {
			t.Errorf("expected ComputeReviewVerifier(%q) to fail", bad)
		}
	}
	if !ValidReviewCodeShape("123456") {
		t.Error("expected 123456 to be a valid shape")
	}
}

// TestReviewVerifier_BoundToAllFields pins domain separation: changing any
// single bound field (key, UUID, email, purpose material) breaks verification.
func TestReviewVerifier_BoundToAllFields(t *testing.T) {
	key := testReviewKey(t)
	id := "b2ea21ec-6b4b-4da7-8668-a3a598a59711"
	email := "review-synthetic@example.com"
	code := "482916"
	verifier, err := ComputeReviewVerifier(key, id, email, code)
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	otherKey := testReviewKey(t)
	cases := []struct {
		name      string
		key       []byte
		verifier  string
		id, email string
		code      string
	}{
		{"other key", otherKey, verifier, id, email, code},
		{"other uuid", key, verifier, "c3fb32fd-7c5c-5eb8-9779-b4a699b60822", email, code},
		{"other email", key, verifier, id, "other-synthetic@example.com", code},
		{"other code", key, verifier, id, email, "482917"},
	}
	for _, tc := range cases {
		if VerifyReviewCode(tc.key, tc.verifier, tc.id, tc.email, tc.code) {
			t.Errorf("expected %s to break verification", tc.name)
		}
	}
	// Case-sensitive email: the ordinary email path never folds case, and the
	// verifier must not either.
	if VerifyReviewCode(key, verifier, id, strings.ToUpper(email), code) {
		t.Error("expected uppercased email to break verification")
	}
}

// TestReviewVerifier_MalformedInputsFailClosed pins fail-closed behavior:
// short/all-zero keys, malformed verifiers, and empty bindings never verify.
func TestReviewVerifier_MalformedInputsFailClosed(t *testing.T) {
	key := testReviewKey(t)
	verifier, err := ComputeReviewVerifier(key, "id", "e@example.com", "123456")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	if VerifyReviewCode(make([]byte, 32), verifier, "id", "e@example.com", "123456") {
		t.Error("expected all-zero key to fail")
	}
	if VerifyReviewCode(key[:16], verifier, "id", "e@example.com", "123456") {
		t.Error("expected short key to fail")
	}
	for _, bad := range []string{"", "zz", strings.Repeat("0", 63), strings.Repeat("0", 65), strings.Repeat("0", 64)} {
		if VerifyReviewCode(key, bad, "id", "e@example.com", "123456") {
			t.Errorf("expected malformed verifier %q to fail", bad)
		}
	}
	if _, err := ComputeReviewVerifier(nil, "id", "e@example.com", "123456"); err == nil {
		t.Error("expected nil key to fail")
	}
	if _, err := ComputeReviewVerifier(make([]byte, 32), "id", "e@example.com", "123456"); err == nil {
		t.Error("expected all-zero key to fail at compute time")
	}
}

// TestReviewVerifier_NoPlaintextMaterial pins that the verifier discloses
// nothing usable: it is not the code, carries no code substring, and two
// independent keys produce unrelated verifiers.
func TestReviewVerifier_NoPlaintextMaterial(t *testing.T) {
	code := "482916"
	v1, err := ComputeReviewVerifier(testReviewKey(t), "id", "e@example.com", code)
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	v2, err := ComputeReviewVerifier(testReviewKey(t), "id", "e@example.com", code)
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	if strings.Contains(v1, code) {
		t.Error("verifier must not embed the plaintext code")
	}
	if v1 == v2 {
		t.Error("independent keys must produce unrelated verifiers")
	}
	if _, err := hex.DecodeString(v1); err != nil {
		t.Errorf("verifier must be hex: %v", err)
	}
}

// TestReviewVerifier_IndependentFromOTPHash pins that the review verifier is
// a different construction from the ordinary OTP SHA-256 hash: rotating the
// ordinary OTP material cannot affect review verification and vice versa.
func TestReviewVerifier_IndependentFromOTPHash(t *testing.T) {
	key := testReviewKey(t)
	verifier, err := ComputeReviewVerifier(key, "id", "e@example.com", "123456")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	ordinary := NewOTPService(0, 0)
	if ordinary.VerifyCode("123456", verifier) {
		t.Error("review verifier must not validate as an ordinary OTP hash")
	}
}
