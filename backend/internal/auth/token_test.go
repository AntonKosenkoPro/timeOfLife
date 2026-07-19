package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestTokenService_CreateAccessToken_ReturnsValidJWT(t *testing.T) {
	t.Parallel()

	s := NewTokenService("test-secret-that-is-at-least-32-bytes-long!!", 15*time.Minute, 7*24*time.Hour)

	userID := "user-123"
	email := "test@example.com"

	tokenStr, err := s.CreateAccessToken(userID, email)
	if err != nil {
		t.Fatalf("CreateAccessToken returned error: %v", err)
	}
	if tokenStr == "" {
		t.Fatal("CreateAccessToken returned empty token")
	}

	// Parse and verify the token
	claims := &AccessTokenClaims{}
	token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte("test-secret-that-is-at-least-32-bytes-long!!"), nil
	})
	if err != nil {
		t.Fatalf("failed to parse token: %v", err)
	}
	if !token.Valid {
		t.Fatal("token is not valid")
	}
	if claims.Subject != userID {
		t.Errorf("expected subject %q, got %q", userID, claims.Subject)
	}
	if claims.Email != email {
		t.Errorf("expected email %q, got %q", email, claims.Email)
	}
}

func TestTokenService_ValidateAccessToken_ReturnsCorrectUserIDAndEmail(t *testing.T) {
	t.Parallel()

	s := NewTokenService("test-secret-that-is-at-least-32-bytes-long!!", 15*time.Minute, 7*24*time.Hour)

	userID := "user-456"
	email := "alice@example.com"

	tokenStr, err := s.CreateAccessToken(userID, email)
	if err != nil {
		t.Fatalf("CreateAccessToken returned error: %v", err)
	}

	gotUserID, gotEmail, err := s.ValidateAccessToken(tokenStr)
	if err != nil {
		t.Fatalf("ValidateAccessToken returned error: %v", err)
	}
	if gotUserID != userID {
		t.Errorf("expected userID %q, got %q", userID, gotUserID)
	}
	if gotEmail != email {
		t.Errorf("expected email %q, got %q", email, gotEmail)
	}
}

func TestTokenService_ValidateAccessToken_RejectsExpiredToken(t *testing.T) {
	t.Parallel()

	s := NewTokenService("test-secret-that-is-at-least-32-bytes-long!!", -1*time.Minute, 7*24*time.Hour)

	tokenStr, err := s.CreateAccessToken("user-789", "bob@example.com")
	if err != nil {
		t.Fatalf("CreateAccessToken returned error: %v", err)
	}

	_, _, err = s.ValidateAccessToken(tokenStr)
	if err == nil {
		t.Fatal("expected error for expired token, got nil")
	}
}

func TestTokenService_ValidateAccessToken_RejectsTokenWithWrongSecret(t *testing.T) {
	t.Parallel()

	signer := NewTokenService("correct-secret-that-is-at-least-32-bytes!!", 15*time.Minute, 7*24*time.Hour)
	validator := NewTokenService("wrong-secret-that-is-also-at-least-32-bytes!!", 15*time.Minute, 7*24*time.Hour)

	tokenStr, err := signer.CreateAccessToken("user-101", "carol@example.com")
	if err != nil {
		t.Fatalf("CreateAccessToken returned error: %v", err)
	}

	_, _, err = validator.ValidateAccessToken(tokenStr)
	if err == nil {
		t.Fatal("expected error for token signed with wrong secret, got nil")
	}
}

func TestTokenService_GenerateRefreshToken_Returns64CharHex(t *testing.T) {
	t.Parallel()

	s := NewTokenService("test-secret-that-is-at-least-32-bytes-long!!", 15*time.Minute, 7*24*time.Hour)

	raw, hash, err := s.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken returned error: %v", err)
	}
	if len(raw) != 64 {
		t.Errorf("expected raw token length 64, got %d", len(raw))
	}
	// Verify it's valid hex
	for _, c := range raw {
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			t.Errorf("unexpected character %c in raw token", c)
		}
	}
	if hash == "" {
		t.Fatal("hash should not be empty")
	}
}

func TestTokenService_HashToken_ReturnsConsistentSHA256(t *testing.T) {
	t.Parallel()

	token := "some-random-token-value-12345"
	hash := HashToken(token)

	if hash == "" {
		t.Fatal("HashToken returned empty string")
	}
	if len(hash) != 64 {
		t.Errorf("expected hash length 64, got %d", len(hash))
	}
}

func TestTokenService_HashToken_IsDeterministic(t *testing.T) {
	t.Parallel()

	token := "deterministic-test-token"
	h1 := HashToken(token)
	h2 := HashToken(token)

	if h1 != h2 {
		t.Errorf("HashToken is not deterministic: %q != %q", h1, h2)
	}
}

func TestTokenService_RefreshTokenTTL(t *testing.T) {
	t.Parallel()

	ttl := 7 * 24 * time.Hour
	s := NewTokenService("test-secret-that-is-at-least-32-bytes-long!!", 15*time.Minute, ttl)

	got := s.RefreshTokenTTL()
	if got != ttl {
		t.Errorf("expected TTL %v, got %v", ttl, got)
	}
}
