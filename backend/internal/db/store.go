package db

import (
	"context"
	"time"
)

// User represents a registered user.
type User struct {
	ID            string    `json:"id"`
	Email         string    `json:"email"`
	EmailVerified bool      `json:"email_verified"`
	CreatedAt     time.Time `json:"created_at"`
}

// OTP represents a one-time password code.
type OTP struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	CodeHash    string    `json:"-"`
	ExpiresAt   time.Time `json:"expires_at"`
	Attempts    int       `json:"attempts"`
	MaxAttempts int       `json:"max_attempts"`
}

// RefreshToken represents a stored refresh token.
type RefreshToken struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	TokenHash string    `json:"-"`
	DeviceID  string    `json:"device_id,omitempty"`
	Revoked   bool      `json:"revoked"`
	CreatedAt time.Time `json:"created_at"`
}

// Store defines the interface for all database operations.
type Store interface {
	// GetUserByEmail returns a user by their email.
	GetUserByEmail(ctx context.Context, email string) (User, error)

	// UpsertUser creates a user if not exists, returns the user.
	UpsertUser(ctx context.Context, email string) (User, error)

	// SetUserVerified marks a user's email as verified.
	SetUserVerified(ctx context.Context, userID string) error

	// SaveOTP stores a new OTP code for a user.
	SaveOTP(ctx context.Context, userID string, codeHash string, expiresAt time.Time) error

	// GetValidOTP returns the latest non-expired, non-exhausted OTP for a user.
	GetValidOTP(ctx context.Context, userID string) (OTP, error)

	// IncrementOTPAttempts increments the attempt counter for an OTP.
	IncrementOTPAttempts(ctx context.Context, otpID string) error

	// MarkOTPExhausted marks an OTP as exhausted (max attempts reached).
	MarkOTPExhausted(ctx context.Context, otpID string) error

	// SaveRefreshToken stores a new refresh token.
	SaveRefreshToken(ctx context.Context, userID string, tokenHash string, deviceID string, expiresAt time.Time) error

	// GetRefreshToken returns a refresh token by its hash, including user info.
	GetRefreshToken(ctx context.Context, tokenHash string) (RefreshToken, error)

	// RevokeRefreshToken marks a refresh token as revoked.
	RevokeRefreshToken(ctx context.Context, tokenID string) error

	// RevokeAllUserSessions revokes all refresh tokens for a user.
	RevokeAllUserSessions(ctx context.Context, userID string) error

	// GetUserByID returns a user by their ID.
	GetUserByID(ctx context.Context, userID string) (User, error)

	// UpsertUserByAppleSubject upserts a user keyed by Apple's stable `sub`
	// identifier. Apple users are considered email-verified. The email is
	// persisted on first sign-in and left untouched on later sign-ins (Apple
	// may omit it after the first authorization). May return an error if the
	// email collides with an existing email-only account (account linking is a
	// follow-up).
	UpsertUserByAppleSubject(ctx context.Context, appleSubject, email string) (User, error)

	// Close closes the database connection.
	Close() error
}
