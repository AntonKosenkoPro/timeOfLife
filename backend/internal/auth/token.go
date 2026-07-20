// Package auth provides JWT access token and OTP code services.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TokenService handles JWT access tokens and opaque refresh tokens.
type TokenService struct {
	jwtSecret       []byte
	accessTokenTTL  time.Duration
	refreshTokenTTL time.Duration
}

// NewTokenService creates a new TokenService.
func NewTokenService(jwtSecret string, accessTokenTTL, refreshTokenTTL time.Duration) *TokenService {
	return &TokenService{
		jwtSecret:       []byte(jwtSecret),
		accessTokenTTL:  accessTokenTTL,
		refreshTokenTTL: refreshTokenTTL,
	}
}

// AccessTokenClaims represents the JWT claims for an access token.
type AccessTokenClaims struct {
	Email string `json:"email"`
	jwt.RegisteredClaims
}

// CreateAccessToken creates a signed JWT access token for the given user.
func (s *TokenService) CreateAccessToken(userID, email string) (string, error) {
	now := time.Now()
	claims := AccessTokenClaims{
		Email: email,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.accessTokenTTL)),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(s.jwtSecret)
	if err != nil {
		return "", fmt.Errorf("sign access token: %w", err)
	}
	return signed, nil
}

// ValidateAccessToken validates a JWT access token string and returns the
// userID and email embedded in its claims.
func (s *TokenService) ValidateAccessToken(tokenStr string) (userID, email string, err error) {
	token, err := jwt.ParseWithClaims(tokenStr, &AccessTokenClaims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil {
		return "", "", fmt.Errorf("parse access token: %w", err)
	}

	claims, ok := token.Claims.(*AccessTokenClaims)
	if !ok || !token.Valid {
		return "", "", fmt.Errorf("invalid access token claims")
	}

	return claims.Subject, claims.Email, nil
}

// GenerateRefreshToken creates a new opaque refresh token.
// It returns the raw token (to give to the client) and its SHA-256 hash
// (to store in the database).
func (s *TokenService) GenerateRefreshToken() (rawToken, hash string, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate refresh token: %w", err)
	}
	rawToken = hex.EncodeToString(b)
	hash = HashToken(rawToken)
	return rawToken, hash, nil
}

// HashToken returns the SHA-256 hex digest of the given token string.
func HashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

// RefreshTokenTTL returns the configured refresh token TTL.
func (s *TokenService) RefreshTokenTTL() time.Duration {
	return s.refreshTokenTTL
}
