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

// listMigrationFiles returns the embedded *.sql file names in apply order.
// File names are zero-padded sequence numbers (001_..., 002_...), so lexical
// order is apply order.
func listMigrationFiles() ([]string, error) {
	files, err := fs.Glob(migrationFiles, "*.sql")
	if err != nil {
		return nil, fmt.Errorf("list migration files: %w", err)
	}
	sort.Strings(files)
	return files, nil
}

// RunPostgres applies all embedded SQL migrations against a Postgres pool.
// Applied files are recorded in the schema_migrations table and skipped on
// later boots, so each file runs exactly once.
func RunPostgres(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		filename TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}

	files, err := listMigrationFiles()
	if err != nil {
		return err
	}

	for _, file := range files {
		var applied bool
		if err := pool.QueryRow(ctx, `SELECT true FROM schema_migrations WHERE filename = $1`, file).Scan(&applied); err == nil && applied {
			continue
		}

		content, err := migrationFiles.ReadFile(file)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", file, err)
		}

		if _, err := pool.Exec(ctx, string(content)); err != nil {
			return fmt.Errorf("apply migration %s: %w", file, err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO schema_migrations (filename) VALUES ($1) ON CONFLICT DO NOTHING`, file); err != nil {
			return fmt.Errorf("record migration %s: %w", file, err)
		}
	}

	return nil
}

// RunSQLite applies all embedded SQL migrations against a SQLite database.
// Applied files are recorded in the schema_migrations table and skipped on
// later calls, so each file runs exactly once.
func RunSQLite(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		filename TEXT PRIMARY KEY,
		applied_at TEXT NOT NULL DEFAULT (datetime('now'))
	)`); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}

	files, err := listMigrationFiles()
	if err != nil {
		return err
	}

	for _, file := range files {
		var applied bool
		if err := db.QueryRowContext(ctx, `SELECT true FROM schema_migrations WHERE filename = ?`, file).Scan(&applied); err == nil && applied {
			continue
		}

		content, err := migrationFiles.ReadFile(file)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", file, err)
		}

		// Adapt Postgres SQL to SQLite
		adapted := adaptToSQLite(string(content))

		if _, err := db.ExecContext(ctx, adapted); err != nil {
			return fmt.Errorf("apply migration %s: %w", file, err)
		}
		if _, err := db.ExecContext(ctx, `INSERT OR IGNORE INTO schema_migrations (filename) VALUES (?)`, file); err != nil {
			return fmt.Errorf("record migration %s: %w", file, err)
		}
	}

	return nil
}

// sqliteReplacements maps Postgres dialect fragments to their SQLite
// equivalents. Each entry is applied in order with strings.ReplaceAll.
var sqliteReplacements = [][2]string{
	{"TIMESTAMPTZ", "TEXT"},
	{"UUID", "TEXT"},
	{"NOW()", "(datetime('now'))"},
	{"DEFAULT false", "DEFAULT 0"},
	{"DEFAULT true", "DEFAULT 1"},
	{"CONCURRENTLY", ""},
}

// dropIndexExistsGuard is the DROP INDEX guard SQLite supports and the
// blanket IF EXISTS strip below must not eat.
const dropIndexExistsGuard = "DROP INDEX IF EXISTS"

// adaptToSQLite converts Postgres-specific SQL syntax to SQLite-compatible
// syntax. SQLite supports IF NOT EXISTS on CREATE but not on ADD COLUMN or
// CREATE INDEX, and it supports neither IF EXISTS on DROP COLUMN; the fresh
// in-memory test DB applies each file once, so the guards are stripped.
// DROP INDEX keeps its guard (an index may legitimately be absent there).
func adaptToSQLite(sql string) string {
	const guardPlaceholder = "DROP INDEX %%KEEP_EXISTS%%"
	sql = strings.ReplaceAll(sql, dropIndexExistsGuard, guardPlaceholder)
	for _, r := range sqliteReplacements {
		sql = strings.ReplaceAll(sql, r[0], r[1])
	}
	// Remove IF NOT EXISTS for ADD COLUMN / CREATE INDEX (SQLite doesn't
	// support it there; each file applies once).
	sql = strings.ReplaceAll(sql, "IF NOT EXISTS", "")
	// Remove IF EXISTS for DROP COLUMN (SQLite doesn't support it).
	sql = strings.ReplaceAll(sql, "IF EXISTS", "")
	sql = strings.ReplaceAll(sql, guardPlaceholder, dropIndexExistsGuard)
	return sql
}
