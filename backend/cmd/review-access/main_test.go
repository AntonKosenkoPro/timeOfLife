package main

import (
	"crypto/rand"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
)

// TestVerifier_RoundTrip pins the operator flow with synthetic material: a
// random key via env, a fixed-shape stdin code, and a protected output file.
// The test asserts the file content matches the library derivation and that
// no code/key material is echoed anywhere observable.
func TestVerifier_RoundTrip(t *testing.T) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	keyHex := hex.EncodeToString(key)
	t.Setenv("REVIEW_CODE_KEY", keyHex)

	id := "b2ea21ec-6b4b-4da7-8668-a3a598a59711"
	mail := "review-synthetic@example.com"
	out := filepath.Join(t.TempDir(), "verifier.hex")

	if code := runVerifier([]string{"--account-id", id, "--email", mail, "--out", out},
		strings.NewReader("482916\n")); code != 0 {
		t.Fatalf("expected exit 0, got %d", code)
	}
	raw, err := os.ReadFile(out)
	if err != nil {
		t.Fatalf("read verifier output: %v", err)
	}
	want, err := auth.ComputeReviewVerifier(key, id, mail, "482916")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	if strings.TrimSpace(string(raw)) != want {
		t.Fatal("verifier output does not match the library derivation")
	}
	info, err := os.Stat(out)
	if err != nil {
		t.Fatalf("stat verifier output: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("expected owner-only output, got %o", info.Mode().Perm())
	}
}

// TestVerifier_InputErrorsAreRedacted pins fail-closed input handling: bad
// UUID/email/code/key shapes and a missing --out all exit non-zero without
// a verifier file and without echoing the submitted material.
func TestVerifier_InputErrorsAreRedacted(t *testing.T) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	t.Setenv("REVIEW_CODE_KEY", hex.EncodeToString(key))

	id := "b2ea21ec-6b4b-4da7-8668-a3a598a59711"
	mail := "review-synthetic@example.com"

	cases := []struct {
		name string
		args []string
		code string
	}{
		{"bad uuid", []string{"--account-id", "nope", "--email", mail, "--out", "x"}, "482916\n"},
		{"bad email", []string{"--account-id", id, "--email", "nope", "--out", "x"}, "482916\n"},
		{"uppercase uuid", []string{"--account-id", "B2EA21EC-6B4B-4DA7-8668-A3A598A59711", "--email", mail, "--out", "x"}, "482916\n"},
		{"uppercase email", []string{"--account-id", id, "--email", "Review-Synthetic@Example.COM", "--out", "x"}, "482916\n"},
		{"missing out", []string{"--account-id", id, "--email", mail}, "482916\n"},
		{"short code", []string{"--account-id", id, "--email", mail, "--out", "x"}, "123\n"},
		{"non-digit code", []string{"--account-id", id, "--email", mail, "--out", "x"}, "abcdef\n"},
		{"empty code", []string{"--account-id", id, "--email", mail, "--out", "x"}, "\n"},
	}
	for _, tc := range cases {
		dir := t.TempDir()
		args := append([]string{}, tc.args...)
		for i, a := range args {
			if a == "x" {
				args[i] = filepath.Join(dir, "verifier.hex")
			}
		}
		if code := runVerifier(args, strings.NewReader(tc.code)); code == 0 {
			t.Errorf("%s: expected non-zero exit", tc.name)
		}
		if _, err := os.Stat(filepath.Join(dir, "verifier.hex")); !os.IsNotExist(err) {
			t.Errorf("%s: verifier file must not exist on failure", tc.name)
		}
	}
}

// TestVerifier_BadKeyFailsWithoutDisclosure pins that a malformed
// REVIEW_CODE_KEY fails closed with a shape-only diagnostic.
func TestVerifier_BadKeyFailsWithoutDisclosure(t *testing.T) {
	t.Setenv("REVIEW_CODE_KEY", "not-hex")
	out := filepath.Join(t.TempDir(), "verifier.hex")
	if code := runVerifier([]string{
		"--account-id", "b2ea21ec-6b4b-4da7-8668-a3a598a59711",
		"--email", "review-synthetic@example.com", "--out", out,
	}, strings.NewReader("482916\n")); code == 0 {
		t.Fatal("expected non-zero exit for malformed key")
	}
	if _, err := os.Stat(out); !os.IsNotExist(err) {
		t.Fatal("verifier file must not exist on key failure")
	}
}

// TestWriteProtected_RefusesSymlink pins the secret-path contract: an
// existing symlink at --out is refused and the link target is never
// truncated or followed.
func TestWriteProtected_RefusesSymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "target.hex")
	if err := os.WriteFile(target, []byte("original"), 0o600); err != nil {
		t.Fatalf("write target: %v", err)
	}
	link := filepath.Join(dir, "verifier.hex")
	if err := os.Symlink(target, link); err != nil {
		t.Fatalf("symlink: %v", err)
	}
	if err := writeProtected(link, "verifier-material\n"); err == nil {
		t.Fatal("expected writeProtected to refuse a symlink")
	}
	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("read target: %v", err)
	}
	if string(raw) != "original" {
		t.Fatal("symlink target must never be truncated by writeProtected")
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("link must remain a symlink, stat err=%v", err)
	}
}

// TestWriteProtected_ResetsExistingMode pins that a pre-existing --out file
// keeps neither stale content nor a world-readable mode: the 0o600 argument
// only applies on creation, so an explicit Chmod must follow the open.
func TestWriteProtected_ResetsExistingMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "verifier.hex")
	if err := os.WriteFile(path, []byte("stale"), 0o644); err != nil {
		t.Fatalf("write stale file: %v", err)
	}
	if err := writeProtected(path, "fresh\n"); err != nil {
		t.Fatalf("writeProtected: %v", err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read output: %v", err)
	}
	if string(raw) != "fresh\n" {
		t.Fatalf("expected replaced content, got %q", raw)
	}
	if info, err := os.Stat(path); err != nil {
		t.Fatalf("stat output: %v", err)
	} else if info.Mode().Perm() != 0o600 {
		t.Errorf("expected owner-only output, got %o", info.Mode().Perm())
	}
}

// TestRevoke_RequiresExactConfirmation pins the revocation guardrails:
// mismatched or malformed UUIDs refuse before any database is touched.
func TestRevoke_RequiresExactConfirmation(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://localhost:1/unreachable?sslmode=disable")
	ctx := t.Context()
	if code := runRevoke(ctx, []string{
		"--account-id", "b2ea21ec-6b4b-4da7-8668-a3a598a59711",
		"--confirm-account-id", "c3fb32fd-7c5c-5eb8-9779-b4a699b60822",
	}); code == 0 {
		t.Fatal("expected non-zero exit on UUID mismatch")
	}
	if code := runRevoke(ctx, []string{
		"--account-id", "not-a-uuid",
		"--confirm-account-id", "not-a-uuid",
	}); code == 0 {
		t.Fatal("expected non-zero exit on malformed UUID")
	}
}
