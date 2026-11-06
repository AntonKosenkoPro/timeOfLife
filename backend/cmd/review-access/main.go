// Command review-access is the private operator utility for the
// disabled-by-default App Review exception (demo-account-access). It never
// touches production on its own: the verifier subcommand computes the
// REVIEW_CODE_VERIFIER from private stdin input, and the revoke subcommand
// reuses the store's atomic RevokeAllUserSessions primitive against an
// explicitly confirmed review UUID.
//
// No code, key, verifier, token, or email is ever echoed to stdout, stderr,
// or logs; the code enters only via stdin (never argv/env), and the verifier
// leaves only through an explicitly protected output file.
package main

import (
	"bufio"
	"context"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) < 1 {
		usage()
		return 2
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	switch args[0] {
	case "verifier":
		return runVerifier(args[1:], os.Stdin)
	case "revoke":
		return runRevoke(ctx, args[1:])
	default:
		fmt.Fprintf(os.Stderr, "unknown subcommand %q\n", args[0])
		usage()
		return 2
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `review-access: private operator utility for App Review access (demo-account-access).

Subcommands (no predictable defaults; secrets never enter argv/env/output):
  verifier --account-id UUID --email EMAIL --out FILE
      Read the six-digit code from stdin, compute REVIEW_CODE_VERIFIER with
      REVIEW_CODE_KEY from the environment, and write the verifier hex to
      FILE (created 0600, never printed). The code and key are never echoed.
  revoke --account-id UUID --confirm-account-id UUID
      Revoke all refresh/recovery sessions for exactly the review UUID
      (atomic store primitive). The two UUID flags must match. Erases no
      data and clears no attempt history.
`)
}

// runVerifier computes the verifier from the binding, the dedicated key from
// REVIEW_CODE_KEY, and a privately supplied stdin code, writing only the
// verifier hex to the protected --out destination.
func runVerifier(args []string, stdin io.Reader) int {
	var accountID, email, out string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--account-id":
			accountID = flagValue(args, &i, "--account-id")
		case "--email":
			email = flagValue(args, &i, "--email")
		case "--out":
			out = flagValue(args, &i, "--out")
		default:
			fmt.Fprintf(os.Stderr, "unknown flag %q\n", args[i])
			return 2
		}
	}
	if !auth.ValidUUIDShape(accountID) {
		fmt.Fprintln(os.Stderr, "invalid --account-id: want lowercase UUID of the existing verified review account")
		return 2
	}
	// ValidEmail accepts mixed case, but the binding is stored verbatim and
	// matched byte-exactly (config rejects non-lowercase too): fail fast
	// here so the CLI cannot mint a verifier the server would never match.
	if !auth.ValidEmail(email) || email != strings.ToLower(email) {
		fmt.Fprintln(os.Stderr, "invalid --email: want canonical lowercase email of the existing verified review account")
		return 2
	}
	if out == "" {
		fmt.Fprintln(os.Stderr, "missing --out: verifier writes only to an explicitly protected file")
		return 2
	}
	keyHex := strings.TrimSpace(os.Getenv("REVIEW_CODE_KEY"))
	key, err := hex.DecodeString(keyHex)
	if err != nil || len(key) != auth.ReviewAccessKeySize {
		fmt.Fprintln(os.Stderr, "invalid REVIEW_CODE_KEY: want 64 hex chars in the environment, never argv")
		return 2
	}
	code, err := readCode(stdin)
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid code input: want exactly six ASCII digits on stdin")
		return 2
	}
	verifier, err := auth.ComputeReviewVerifier(key, accountID, email, code)
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot compute verifier for this binding")
		return 2
	}
	if err := writeProtected(out, verifier+"\n"); err != nil {
		fmt.Fprintln(os.Stderr, "cannot write verifier output")
		return 2
	}
	return 0
}

// runRevoke revokes all refresh/recovery sessions for exactly the confirmed
// review UUID using the existing atomic store primitive. It deletes no data,
// resets no attempt history, and touches no other account. DATABASE_URL
// selects the database (local/test only unless the operator points it
// elsewhere — this tool never activates production review access by itself).
func runRevoke(ctx context.Context, args []string) int {
	var accountID, confirm string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--account-id":
			accountID = flagValue(args, &i, "--account-id")
		case "--confirm-account-id":
			confirm = flagValue(args, &i, "--confirm-account-id")
		default:
			fmt.Fprintf(os.Stderr, "unknown flag %q\n", args[i])
			return 2
		}
	}
	if !auth.ValidUUIDShape(accountID) || !auth.ValidUUIDShape(confirm) {
		fmt.Fprintln(os.Stderr, "invalid UUID: both --account-id and --confirm-account-id must be UUIDs")
		return 2
	}
	if subtle.ConstantTimeCompare([]byte(accountID), []byte(confirm)) != 1 {
		fmt.Fprintln(os.Stderr, "refusing: --confirm-account-id must exactly match --account-id")
		return 2
	}
	dsn := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if dsn == "" {
		fmt.Fprintln(os.Stderr, "missing DATABASE_URL")
		return 2
	}
	store, err := db.NewPostgresStore(ctx, dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot connect to database")
		return 2
	}
	defer func() { _ = store.Close() }()
	if err := store.RevokeAllUserSessions(ctx, accountID); err != nil {
		fmt.Fprintln(os.Stderr, "revocation failed")
		return 1
	}
	fmt.Fprintln(os.Stderr, "revoked all sessions for the confirmed review account")
	return 0
}

func flagValue(args []string, i *int, name string) string {
	if *i+1 >= len(args) {
		fmt.Fprintf(os.Stderr, "missing value for %s\n", name)
		return ""
	}
	*i++
	return strings.TrimSpace(args[*i])
}

// readCode reads the six-digit code from r without echoing it back.
// Only the first line is consumed; surrounding whitespace is trimmed and the
// shape is validated before use.
func readCode(r io.Reader) (string, error) {
	line, err := bufio.NewReader(r).ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	code := strings.TrimSpace(line)
	if !auth.ValidReviewCodeShape(code) {
		return "", errors.New("bad code shape")
	}
	return code, nil
}

// writeProtected writes content to path with owner-only permissions. A
// pre-existing symlink (or any other non-regular file: device, fifo,
// socket, directory) is refused before opening, so --out can never clobber
// an arbitrary file through a link. The open additionally carries O_NOFOLLOW
// where the platform supports it to close the check-then-open race on the
// final component, and f.Chmod follows because the 0o600 creation mode only
// applies to newly created files — a pre-existing world-readable file keeps
// its old mode without it. The verifier is file content only — never
// printed, never logged.
func writeProtected(path, content string) error {
	if info, statErr := os.Lstat(path); statErr == nil {
		if !info.Mode().IsRegular() {
			return errors.New("out path must be a regular file (symlinks/devices are refused)")
		}
	} else if !os.IsNotExist(statErr) {
		return statErr
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC|oNofollow, 0o600)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	// The 0o600 mode argument only applies to newly created files: an
	// existing file keeps its previous (possibly world-readable) mode.
	if err := f.Chmod(0o600); err != nil {
		return err
	}
	if _, err := f.WriteString(content); err != nil {
		return err
	}
	return f.Close()
}
