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
	// 007 re-adds entries.activity_id so its backfill stays a no-op when
	// Postgres migrations re-apply on every server start (the column was
	// dropped in a previous pass). The fresh in-memory SQLite test DB created
	// by 003 already has the column — NOT NULL — so re-adding it would fail;
	// SQLite stores are never re-migrated, so strip the re-add entirely.
	// Must run BEFORE the UUID→TEXT replacement, which would rewrite the
	// statement past recognition.
	sql = strings.ReplaceAll(sql,
		"ALTER TABLE entries ADD COLUMN IF NOT EXISTS activity_id UUID;\n", "")
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
	// Remove IF NOT EXISTS for indexes (SQLite doesn't support it), except on
	// DROP statements, which must stay guarded (SQLite supports IF NOT
	// EXISTS/IF EXISTS on DROP, and 007's DROP INDEX IF EXISTS runs against
	// DBs where the index may not exist — 003 stopped creating it).
	//
	// Note the DROP guard must be restored BEFORE the blanket strips below
	// would eat it: swap it out, strip, swap back.
	sql = strings.ReplaceAll(sql, "DROP INDEX IF EXISTS", "DROP INDEX %%KEEP_EXISTS%%")
	// Remove IF NOT EXISTS for indexes (SQLite doesn't support it)
	sql = strings.ReplaceAll(sql, "IF NOT EXISTS", "")
	// Remove IF EXISTS for DROP COLUMN (SQLite doesn't support it; the column
	// always exists on the fresh in-memory DB used by tests)
	sql = strings.ReplaceAll(sql, "IF EXISTS", "")
	sql = strings.ReplaceAll(sql, "%%KEEP_EXISTS%%", "IF EXISTS")
	// Remove CONCURRENTLY if present
	sql = strings.ReplaceAll(sql, "CONCURRENTLY", "")
	return sql
}
