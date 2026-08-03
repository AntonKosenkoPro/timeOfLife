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

// CategoryTag is a denormalized category (id + name + icon) attached to an
// activity or entry in API responses. It is never written on its own.
type CategoryTag struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Icon string `json:"icon"`
}

// Activity is a saved, reusable time-tracking target (Epic 1).
type Activity struct {
	ID         string        `json:"id"`
	UserID     string        `json:"-"`
	Name       string        `json:"name"`
	Notes      string        `json:"notes"`
	LastUsedAt *time.Time    `json:"last_used_at"`
	Categories []CategoryTag `json:"categories"`
	CreatedAt  time.Time     `json:"created_at"`
	UpdatedAt  time.Time     `json:"updated_at"`
}

// Category is a many-to-many tag that an activity may carry (Epic 1).
type Category struct {
	ID        string    `json:"id"`
	UserID    string    `json:"-"`
	Name      string    `json:"name"`
	Icon      string    `json:"icon"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Entry is one timed interval (Epic 1). Every entry references exactly one
// activity (ActivityID is always set). Categories are inferred from the
// activity's tags at read time; ActivityName is the activity's current name,
// resolved at read time.
type Entry struct {
	ID              string        `json:"id"`
	UserID          string        `json:"-"`
	ActivityID      *string       `json:"activity_id"`
	ActivityName    string        `json:"activity_name"`
	StartedAt       time.Time     `json:"started_at"`
	EndedAt         *time.Time    `json:"ended_at"`
	DurationSeconds *int          `json:"duration_seconds"`
	Categories      []CategoryTag `json:"categories"`
	CreatedAt       time.Time     `json:"created_at"`
	UpdatedAt       time.Time     `json:"updated_at"`
}

// EntryFilter carries the optional GET /entries query parameters.
type EntryFilter struct {
	From       *time.Time // include entries with started_at >= From
	To         *time.Time // include entries with started_at <= To (inclusive upper bound)
	ActivityID string     // restrict to a single activity
	CategoryID string     // restrict to entries whose activity is tagged
	Limit      int        // page size; 0 → default
	Cursor     string     // opaque pagination cursor from a previous response
}

// NullableTime represents an optional timestamp on a partial update: Set=false
// leaves the column unchanged; Set=true with Valid=false sets it to NULL;
// Set=true with Valid=true sets it to Value.
type NullableTime struct {
	Set   bool
	Valid bool
	Value time.Time
}

// ActivityPatch is a partial update for an activity (PATCH /activities/{id}).
// Nil pointer fields are left unchanged. CategoryIDs nil leaves tags; a non-nil
// slice replaces them (an empty slice clears). UpdatedAt is the LWW version
// (required): the write applies only if newer than the stored updated_at.
type ActivityPatch struct {
	Name        *string
	Notes       *string
	CategoryIDs *[]string
	UpdatedAt   time.Time
}

// EntryPatch is a partial update for an entry (PATCH /entries/{id}). Nil/zero
// fields are left unchanged. UpdatedAt is the LWW version (required).
type EntryPatch struct {
	StartedAt *time.Time
	EndedAt   NullableTime // Set=false leaves ended_at unchanged
	UpdatedAt time.Time
}

// CategoryPatch is a partial update for a category (PATCH /categories/{id}).
// Nil pointer fields are left unchanged. UpdatedAt is the LWW version (required).
type CategoryPatch struct {
	Name      *string
	Icon      *string
	UpdatedAt time.Time
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
	SaveRefreshToken(ctx context.Context, userID string, tokenHash string, deviceID string) error

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

	// --- Activities (Epic 1) ---

	// ListActivities returns the user's activities ordered by last_used_at DESC
	// (most-recently-used first). A non-empty q applies a case-insensitive
	// name LIKE typeahead filter.
	ListActivities(ctx context.Context, userID, q string) ([]Activity, error)

	// GetActivity returns one activity (with its category tags) by id, scoped to
	// the user. Returns ErrNotFound if missing or owned by another user.
	GetActivity(ctx context.Context, userID, id string) (Activity, error)

	// CreateActivity inserts a new activity using its client-generated id. It is
	// idempotent on id: a replay of the same id returns the existing record with
	// created=false. A case-insensitive name collision with a different id
	// returns ErrActivityExists carrying the existing activity. categoryIDs
	// (nil/empty = no tags) are linked to the new activity. The returned bool is
	// true when a new row was created.
	CreateActivity(ctx context.Context, a Activity, categoryIDs []string) (Activity, bool, error)

	// UpdateActivity applies a partial LWW update (only if p.UpdatedAt is newer
	// than the stored updated_at). p.CategoryIDs non-nil replaces the activity's
	// tags (an empty non-nil slice clears them); nil leaves tags untouched.
	// Returns ErrNotFound if missing, ErrConflict on a stale updated_at, or
	// ErrActivityExists on a name collision. ErrInvalidCategoryID if a linked
	// category_id does not belong to the user.
	UpdateActivity(ctx context.Context, userID, id string, p ActivityPatch) (Activity, error)

	// DeleteActivity hard-deletes an activity and its child rows (entries and
	// join rows). Returns ErrNotFound if missing.
	DeleteActivity(ctx context.Context, userID, id string) error

	// --- Categories (Epic 1) ---

	// ListCategories returns the user's categories ordered by name.
	ListCategories(ctx context.Context, userID string) ([]Category, error)

	// GetCategory returns one category by id, scoped to the user. Returns
	// ErrNotFound if missing or owned by another user.
	GetCategory(ctx context.Context, userID, id string) (Category, error)

	// CreateCategory inserts a new category using its client-generated id,
	// idempotent on id (replay → created=false). A case-insensitive name
	// collision returns ErrCategoryExists.
	CreateCategory(ctx context.Context, c Category) (Category, bool, error)

	// UpdateCategory applies a partial LWW update on name/icon. Returns
	// ErrNotFound, ErrConflict, or ErrCategoryExists.
	UpdateCategory(ctx context.Context, userID, id string, p CategoryPatch) (Category, error)

	// DeleteCategory hard-deletes a category and its join rows (entries are
	// unaffected). Returns ErrNotFound if missing.
	DeleteCategory(ctx context.Context, userID, id string) error

	// --- Entries (Epic 1) ---

	// ListEntries returns one page of the user's entries ordered by started_at
	// DESC, filtered by EntryFilter. nextCursor is the opaque cursor for the
	// next page, or empty when the page is the last.
	ListEntries(ctx context.Context, userID string, f EntryFilter) (items []Entry, nextCursor string, err error)

	// GetEntry returns one entry by id with its categories (inferred from the
	// activity) and activity name. Returns ErrNotFound if missing/foreign.
	GetEntry(ctx context.Context, userID, id string) (Entry, error)

	// CreateEntry inserts a new entry using its client-generated id, idempotent
	// on id (replay → created=false). ActivityID must belong to the user (else
	// ErrActivityNotFound). duration_seconds is computed from ended_at -
	// started_at when ended_at is present.
	CreateEntry(ctx context.Context, e Entry) (Entry, bool, error)

	// UpdateEntry applies a partial LWW update on started_at/ended_at and
	// recomputes duration_seconds. Returns ErrNotFound or ErrConflict.
	UpdateEntry(ctx context.Context, userID, id string, p EntryPatch) (Entry, error)

	// DeleteEntry hard-deletes an entry. Returns ErrNotFound if missing.
	DeleteEntry(ctx context.Context, userID, id string) error

	// Close closes the database connection.
	Close() error
}
