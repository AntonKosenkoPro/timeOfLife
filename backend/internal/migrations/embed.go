// Package migrations provides embedded SQL migrations for the database.
package migrations

import (
	"context"
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed *.sql
var migrationFiles embed.FS

// RunPostgres applies all embedded SQL migrations against a Postgres pool.
func RunPostgres(ctx context.Context, pool *pgxpool.Pool) error {
	files, err := fs.Glob(migrationFiles, "*.sql")
	if err != nil {
		return fmt.Errorf("list migration files: %w", err)
	}
	sort.Strings(files)

	for _, file := range files {
		content, err := migrationFiles.ReadFile(file)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", file, err)
		}

		_, err = pool.Exec(ctx, string(content))
		if err != nil {
			return fmt.Errorf("apply migration %s: %w", file, err)
		}
	}

	return nil
}

// RunSQLite applies all embedded SQL migrations against a SQLite database.
func RunSQLite(ctx context.Context, db *sql.DB) error {
	files, err := fs.Glob(migrationFiles, "*.sql")
	if err != nil {
		return fmt.Errorf("list migration files: %w", err)
	}
	sort.Strings(files)

	for _, file := range files {
		content, err := migrationFiles.ReadFile(file)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", file, err)
		}

		// Adapt Postgres SQL to SQLite
		sql := adaptToSQLite(string(content))

		_, err = db.ExecContext(ctx, sql)
		if err != nil {
			return fmt.Errorf("apply migration %s: %w", file, err)
		}
	}

	return nil
}

// adaptToSQLite converts Postgres-specific SQL syntax to SQLite-compatible syntax.
func adaptToSQLite(sql string) string {
	// Replace TIMESTAMPTZ with TEXT (SQLite has no native datetime type)
	sql = strings.ReplaceAll(sql, "TIMESTAMPTZ", "TEXT")
	// Replace UUID with TEXT
	sql = strings.ReplaceAll(sql, "UUID", "TEXT")
	// Replace NOW() with (datetime('now')) — parens required for SQLite DEFAULT
	sql = strings.ReplaceAll(sql, "NOW()", "(datetime('now'))")
	// Replace DEFAULT false with DEFAULT 0
	sql = strings.ReplaceAll(sql, "DEFAULT false", "DEFAULT 0")
	// Replace DEFAULT true with DEFAULT 1
	sql = strings.ReplaceAll(sql, "DEFAULT true", "DEFAULT 1")
	// Remove IF NOT EXISTS for indexes (SQLite doesn't support it)
	sql = strings.ReplaceAll(sql, "IF NOT EXISTS", "")
	// Remove CONCURRENTLY if present
	sql = strings.ReplaceAll(sql, "CONCURRENTLY", "")
	return sql
}
