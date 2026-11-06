package config

import (
	"crypto/rand"
	"encoding/hex"
	"strings"
	"testing"
)

func testHexKey(t *testing.T) string {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	// crypto/rand never emits all-zero in practice; guard the rejection path.
	if isZeroKey(key) {
		key[0] = 1
	}
	return hex.EncodeToString(key)
}

// baseReviewEnv sets the required base config env plus a cleared review
// binding; callers override review vars afterwards.
func baseReviewEnv(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://localhost:5432/x?sslmode=disable")
	t.Setenv("JWT_SECRET", strings.Repeat("s", 32))
	t.Setenv("EMAIL_BACKEND", "console")
	t.Setenv("REFRESH_RECOVERY_KEYS", testHexKey(t))
	t.Setenv("ACCOUNT_STATUS_SECRET", strings.Repeat("a", 32))
	t.Setenv("REVIEW_ACCESS_ENABLED", "")
	t.Setenv("REVIEW_ACCOUNT_ID", "")
	t.Setenv("REVIEW_ACCOUNT_EMAIL", "")
	t.Setenv("REVIEW_CODE_VERIFIER", "")
	t.Setenv("REVIEW_CODE_KEY", "")
}

func enabledReviewEnv(t *testing.T, id, email, verifier, key string) {
	t.Helper()
	t.Setenv("REVIEW_ACCESS_ENABLED", "true")
	t.Setenv("REVIEW_ACCOUNT_ID", id)
	t.Setenv("REVIEW_ACCOUNT_EMAIL", email)
	t.Setenv("REVIEW_CODE_VERIFIER", verifier)
	t.Setenv("REVIEW_CODE_KEY", key)
}

// TestReviewAccess_DisabledByDefault pins the shipped posture: without
// explicit enablement no review exception is active and no review secrets
// are required.
func TestReviewAccess_DisabledByDefault(t *testing.T) {
	baseReviewEnv(t)
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Review.Enabled {
		t.Error("expected review access to be disabled by default")
	}
	if cfg.Review.AccountID != "" || cfg.Review.AccountEmail != "" {
		t.Error("expected no review binding when disabled")
	}
	if cfg.Review.Verifier != nil || cfg.Review.Key != nil {
		t.Error("expected no review verification material when disabled")
	}
}

// TestReviewAccess_ExplicitFalseLeavesDisabled pins that an explicit false
// (and empty/0 spellings) keeps the exception off.
func TestReviewAccess_ExplicitFalseLeavesDisabled(t *testing.T) {
	for _, val := range []string{"false", "0"} {
		baseReviewEnv(t)
		t.Setenv("REVIEW_ACCESS_ENABLED", val)
		cfg, err := Load()
		if err != nil {
			t.Fatalf("Load(%q): %v", val, err)
		}
		if cfg.Review.Enabled {
			t.Errorf("expected disabled for REVIEW_ACCESS_ENABLED=%q", val)
		}
	}
}

// TestReviewAccess_EnabledValidBinding pins the only accepted enabled shape:
// valid UUID, canonical valid email, 64-hex verifier, independent 64-hex key.
func TestReviewAccess_EnabledValidBinding(t *testing.T) {
	baseReviewEnv(t)
	id := "b2ea21ec-6b4b-4da7-8668-a3a598a59711"
	verifier := testHexKey(t)
	key := testHexKey(t)
	enabledReviewEnv(t, id, "review-synthetic@example.com", verifier, key)
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.Review.Enabled {
		t.Fatal("expected review access enabled")
	}
	if cfg.Review.AccountID != id {
		t.Errorf("expected account ID preserved, got %q", cfg.Review.AccountID)
	}
	if len(cfg.Review.Verifier) != 32 || len(cfg.Review.Key) != 32 {
		t.Error("expected decoded 32-byte verifier and key")
	}
}

// TestReviewAccess_MalformedEnabledFailsClosed pins startup failure for every
// malformed enabled shape, without disclosing the offending secret values.
func TestReviewAccess_MalformedEnabledFailsClosed(t *testing.T) {
	goodID := "b2ea21ec-6b4b-4da7-8668-a3a598a59711"
	goodEmail := "review-synthetic@example.com"
	goodVerifier := testHexKey(t)
	goodKey := testHexKey(t)

	cases := []struct {
		name          string
		id, email     string
		verifier, key string
	}{
		{"bad uuid", "not-a-uuid", goodEmail, goodVerifier, goodKey},
		{"empty uuid", "", goodEmail, goodVerifier, goodKey},
		{"bad email", goodID, "not-an-email", goodVerifier, goodKey},
		{"dot-edge email", goodID, ".a@example.com", goodVerifier, goodKey},
		{"short verifier", goodID, goodEmail, "abcd", goodKey},
		{"nonhex verifier", goodID, goodEmail, strings.Repeat("zz", 32), goodKey},
		{"zero verifier", goodID, goodEmail, strings.Repeat("00", 32), goodKey},
		{"short key", goodID, goodEmail, goodVerifier, "abcd"},
		{"nonhex key", goodID, goodEmail, goodVerifier, strings.Repeat("zz", 32)},
		{"zero key", goodID, goodEmail, goodVerifier, strings.Repeat("00", 32)},
		{"key equals verifier", goodID, goodEmail, goodVerifier, goodVerifier},
		{"missing verifier", goodID, goodEmail, "", goodKey},
		{"missing key", goodID, goodEmail, goodVerifier, ""},
	}
	for _, tc := range cases {
		baseReviewEnv(t)
		enabledReviewEnv(t, tc.id, tc.email, tc.verifier, tc.key)
		_, err := Load()
		if err == nil {
			t.Errorf("expected Load to fail for %s", tc.name)
			continue
		}
		for _, secret := range []string{tc.verifier, tc.key} {
			if secret != "" && strings.Contains(err.Error(), secret) {
				t.Errorf("error for %s discloses secret material", tc.name)
			}
		}
	}
}

// TestReviewAccess_PartialConfigFailsFast pins that a partial enabled
// binding (any field missing) fails startup instead of running half-bound.
func TestReviewAccess_PartialConfigFailsFast(t *testing.T) {
	baseReviewEnv(t)
	t.Setenv("REVIEW_ACCESS_ENABLED", "true")
	t.Setenv("REVIEW_ACCOUNT_ID", "b2ea21ec-6b4b-4da7-8668-a3a598a59711")
	// email/verifier/key absent
	if _, err := Load(); err == nil {
		t.Fatal("expected Load to fail on partial review config")
	}
}

// TestReviewAccess_DisabledIgnoresReviewSecrets pins that disabled
// deployments do not require (or validate) review secrets — operators can
// leave placeholders unset.
func TestReviewAccess_DisabledIgnoresReviewSecrets(t *testing.T) {
	baseReviewEnv(t)
	t.Setenv("REVIEW_ACCESS_ENABLED", "false")
	t.Setenv("REVIEW_CODE_VERIFIER", "garbage")
	t.Setenv("REVIEW_CODE_KEY", "garbage")
	if _, err := Load(); err != nil {
		t.Fatalf("disabled review must not validate secrets: %v", err)
	}
}
