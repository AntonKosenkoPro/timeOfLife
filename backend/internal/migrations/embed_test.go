package migrations

import (
	"context"
	"database/sql"
	"strings"
	"testing"

	_ "modernc.org/sqlite" // pure-Go SQLite driver for migration tests
)

// TestMigrations_FilesOrderedSequential pins the migration file contract:
// zero-padded sequence numbers, no duplicates (the old duplicate 004), no
// gaps, and lexical order == apply order.
func TestMigrations_FilesOrderedSequential(t *testing.T) {
	files, err := listMigrationFiles()
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	if len(files) == 0 {
		t.Fatal("expected embedded migration files, got none")
	}
	seen := map[string]bool{}
	for i, f := range files {
		if len(f) < 8 || f[3] != '_' || !strings.HasSuffix(f, ".sql") {
			t.Errorf("file %q does not match NNN_name.sql", f)
			continue
		}
		num := f[:3]
		if seen[num] {
			t.Errorf("duplicate migration number %q (%s)", num, f)
		}
		seen[num] = true
		if i > 0 && files[i-1] >= f {
			t.Errorf("files not in lexical order: %q before %q", files[i-1], f)
		}
	}
	// Sequential from 001 with no gaps.
	if len(files) >= 10 {
		t.Fatalf("test only supports <10 migrations, got %d", len(files))
	}
	for i := range files {
		wantNum := [3]byte{'0', '0', byte('0' + i + 1)}
		if got := files[i][:3]; got != string(wantNum[:]) {
			t.Errorf("gap in sequence: position %d holds %q, want %q", i, files[i], string(wantNum[:]))
		}
	}
}

// TestMigrations_AdaptToSQLite pins the minimal dialect surgery: the named
// replacements apply, the DROP INDEX guard survives the blanket strips, and
// ADD COLUMN / DROP COLUMN guards are stripped (SQLite cannot parse them).
func TestMigrations_AdaptToSQLite(t *testing.T) {
	in := "CREATE TABLE t (id UUID PRIMARY KEY, at TIMESTAMPTZ NOT NULL DEFAULT NOW(), f BOOLEAN DEFAULT false, g BOOLEAN DEFAULT true);\n" +
		"ALTER TABLE t ADD COLUMN IF NOT EXISTS c TEXT;\n" +
		"ALTER TABLE t DROP COLUMN IF EXISTS c;\n" +
		"DROP INDEX IF EXISTS idx_t;\n" +
		"CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_t ON t (c);\n"
	out := adaptToSQLite(in)

	for _, want := range []string{
		"TEXT PRIMARY KEY",
		"TEXT NOT NULL DEFAULT (datetime('now'))",
		"DEFAULT 0",
		"DEFAULT 1",
		"DROP INDEX IF EXISTS idx_t",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("expected adapted SQL to contain %q, got:\n%s", want, out)
		}
	}
	for _, gone := range []string{"UUID", "TIMESTAMPTZ", "NOW()", "IF NOT EXISTS", "CONCURRENTLY"} {
		stripped := strings.ReplaceAll(out, "DROP INDEX IF EXISTS", "")
		if strings.Contains(stripped, gone) {
			t.Errorf("expected adapted SQL to drop %q, got:\n%s", gone, out)
		}
	}
	if strings.Contains(out, "%%KEEP_EXISTS%%") {
		t.Error("guard placeholder leaked into adapted SQL")
	}
}

// TestMigrations_RunSQLite_Idempotent pins boot idempotency: applying twice
// succeeds, runs each file once, and records every file in schema_migrations.
func TestMigrations_RunSQLite_Idempotent(t *testing.T) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer func() { _ = db.Close() }()
	db.SetMaxOpenConns(1)

	ctx := context.Background()
	for round := 1; round <= 2; round++ {
		if err := RunSQLite(ctx, db); err != nil {
			t.Fatalf("RunSQLite round %d: %v", round, err)
		}
	}

	files, err := listMigrationFiles()
	if err != nil {
		t.Fatalf("listMigrationFiles: %v", err)
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM schema_migrations`).Scan(&count); err != nil {
		t.Fatalf("count schema_migrations: %v", err)
	}
	if count != len(files) {
		t.Errorf("expected %d tracked migrations, got %d", len(files), count)
	}
	for _, f := range files {
		var applied bool
		if err := db.QueryRowContext(ctx, `SELECT true FROM schema_migrations WHERE filename = ?`, f).Scan(&applied); err != nil || !applied {
			t.Errorf("expected %s tracked as applied (err=%v)", f, err)
		}
	}

	// The squashed schema carries the final shape directly: no activities
	// layer, entries own their text/notes, categories carry icon.
	for _, table := range []string{"users", "otp_codes", "refresh_tokens", "categories", "entries", "entry_categories", "tombstones", "schema_migrations"} {
		var name string
		if err := db.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name=?`, table).Scan(&name); err != nil {
			t.Errorf("expected table %s: %v", table, err)
		}
	}
	for _, dropped := range []string{"activities", "activity_categories"} {
		var name string
		if err := db.QueryRowContext(ctx, `SELECT name FROM sqlite_master WHERE type='table' AND name=?`, dropped).Scan(&name); err == nil {
			t.Errorf("legacy table %s must not exist, found %q", dropped, name)
		}
	}
}
