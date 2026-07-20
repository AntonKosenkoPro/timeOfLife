// Package db provides the Store interface and Postgres/SQLite implementations.
package db

import "errors"

var (
	// ErrNotFound is returned when a requested resource is not found.
	ErrNotFound = errors.New("not found")

	// ErrDuplicateToken is returned when a refresh token hash already exists.
	ErrDuplicateToken = errors.New("duplicate token")
)
