// Package db provides the Store interface and Postgres/SQLite implementations.
package db

import "errors"

var (
	// ErrNotFound is returned when a requested resource is not found.
	ErrNotFound = errors.New("not found")

	// ErrDuplicateToken is returned when a refresh token hash already exists.
	ErrDuplicateToken = errors.New("duplicate token")

	// ErrConflict is returned on a last-write-wins stale write: the client's
	// updated_at is older than the stored updated_at.
	ErrConflict = errors.New("conflict")

	// ErrActivityExists is returned when creating an activity whose name
	// (case-insensitive) already exists for the user.
	ErrActivityExists = errors.New("activity exists")

	// ErrCategoryExists is returned when creating a category whose name
	// (case-insensitive) already exists for the user.
	ErrCategoryExists = errors.New("category exists")

	// ErrActivityNotFound is returned when an entry references an activity_id
	// that does not belong to the user.
	ErrActivityNotFound = errors.New("activity not found")

	// ErrInvalidCategoryID is returned when an activity is linked to a
	// category_id that does not exist or belong to the user. It is a
	// validation error (422), not a missing-resource error (404).
	ErrInvalidCategoryID = errors.New("invalid category id")

	// ErrEndBeforeStart is returned when an entry's ended_at is not after its
	// started_at. Because a partial PATCH can move only one side, the check is
	// performed in the store against the merged value; it is a validation error
	// (422), not a persistence error.
	ErrEndBeforeStart = errors.New("ended_at must be after started_at")
)
