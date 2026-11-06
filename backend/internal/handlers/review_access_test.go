package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/antonkosenko/time-of-life/backend/internal/auth"
	"github.com/antonkosenko/time-of-life/backend/internal/db"
	"github.com/antonkosenko/time-of-life/backend/internal/email"
	"github.com/antonkosenko/time-of-life/backend/internal/ratelimit"
	"github.com/antonkosenko/time-of-life/backend/internal/recovery"
)

// reviewFixture builds a synthetic review binding for user: a random key, a
// fixed-shape code, and the matching verifier. No production material.
func reviewFixture(t *testing.T, user db.User) (ReviewAccessConfig, string) {
	t.Helper()
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatalf("rand.Read: %v", err)
	}
	const code = "482916"
	verifierHex, err := auth.ComputeReviewVerifier(key, user.ID, user.Email, code)
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	verifier, err := hex.DecodeString(verifierHex)
	if err != nil {
		t.Fatalf("decode verifier: %v", err)
	}
	return ReviewAccessConfig{
		Enabled:      true,
		AccountID:    user.ID,
		AccountEmail: user.Email,
		Verifier:     verifier,
		Key:          key,
	}, code
}

func newReviewHandler(t *testing.T, store db.Store, sender email.Sender, cfg ReviewAccessConfig) *Handler {
	t.Helper()
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelWarn}))
	tokenService := auth.NewTokenService("test-secret-key-at-least-32-bytes!!", 15*time.Minute, 7*24*time.Hour)
	otpService := auth.NewOTPService(10*time.Minute, 5)
	if sender == nil {
		sender = email.NewConsoleSender(logger)
	}
	rateLimiter := &RateLimiterGroup{
		OTPRequest: ratelimit.NewTokenBucket(100, 100, time.Minute),
		OTPVerify:  ratelimit.NewTokenBucket(100, 100, time.Minute),
		Apple:      ratelimit.NewTokenBucket(100, 100, time.Minute),
		Status:     ratelimit.NewTokenBucket(100, 100, time.Minute),
	}
	return NewHandler(store, tokenService, otpService, sender, rateLimiter, nil, HandlerConfig{},
		logger, recovery.NewKeyring([][]byte{bytes.Repeat([]byte{0x07}, recovery.KeySize)}),
		WithReviewAccess(cfg))
}

func mustCreateVerifiedUser(t *testing.T, store db.Store, em string) db.User {
	t.Helper()
	user, err := store.UpsertUser(context.Background(), em)
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	if err := store.SetUserVerified(context.Background(), user.ID); err != nil {
		t.Fatalf("SetUserVerified: %v", err)
	}
	user.EmailVerified = true
	return user
}

func decodeAuthResponse(t *testing.T, w *httptest.ResponseRecorder) authResponse {
	t.Helper()
	var resp authResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode auth response: %v", err)
	}
	return resp
}

// TestReview_RequestReturns202WithoutSideEffects pins the request branch: the
// configured address gets the ordinary 202 with no OTP row, no email, no
// account creation, and no attempt-budget consumption.
func TestReview_RequestReturns202WithoutSideEffects(t *testing.T) {
	store := newTestStore(t)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, ReviewAccessConfig{
		Enabled:      true,
		AccountID:    "b2ea21ec-6b4b-4da7-8668-a3a598a59711",
		AccountEmail: "review-synthetic@example.com",
		Verifier:     bytes.Repeat([]byte{0x01}, 32),
		Key:          bytes.Repeat([]byte{0x02}, 32),
	})

	w := requestOTP(t, h, "review-synthetic@example.com")
	if w.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", w.Code)
	}
	if len(sender.messages) != 0 {
		t.Fatalf("expected no email for review address, got %d", len(sender.messages))
	}
	if _, err := store.GetUserByEmail(context.Background(), "review-synthetic@example.com"); err == nil {
		t.Fatal("review request must not create an account")
	}
}

// TestReview_VerifyWithoutRequestSucceedsRepeatedly pins the reusable-code
// contract: no prior request needed, and repeated success never expires or
// consumes the code.
func TestReview_VerifyWithoutRequestSucceedsRepeatedly(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-repeat@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	for i := 0; i < 2; i++ {
		w := verifyOTPWithDevice(t, h, user.Email, code, fmt.Sprintf("device-%d", i))
		if w.Code != http.StatusOK {
			t.Fatalf("verify %d: expected 200, got %d: %s", i, w.Code, w.Body.String())
		}
		resp := decodeAuthResponse(t, w)
		if resp.User.ID != user.ID {
			t.Fatalf("expected session for review user, got %q", resp.User.ID)
		}
		if resp.AccessToken == "" || resp.RefreshToken == "" {
			t.Fatal("expected token pair")
		}
	}
}

// TestReview_WrongCodeRejected pins 401 invalid_otp for an incorrect code
// with the ordinary error envelope.
func TestReview_WrongCodeRejected(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-wrong@example.com")
	cfg, _ := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	w := verifyOTP(t, h, user.Email, "000000")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), "invalid_otp") {
		t.Fatalf("expected invalid_otp envelope, got %s", w.Body.String())
	}
}

// TestReview_StaleOTPNotAccepted pins no ordinary-OTP fallback: an OTP
// issued for the review address never authorizes while the exception is on.
func TestReview_StaleOTPNotAccepted(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-stale@example.com")
	cfg, code := reviewFixture(t, user)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, cfg)

	// Plant a stale ordinary OTP directly (the request path suppresses it).
	otpSvc := auth.NewOTPService(10*time.Minute, 5)
	plain, hash, err := otpSvc.GenerateOTP()
	if err != nil {
		t.Fatalf("GenerateOTP: %v", err)
	}
	if err := store.SaveOTP(context.Background(), user.ID, hash, time.Now().Add(10*time.Minute), 5); err != nil {
		t.Fatalf("SaveOTP: %v", err)
	}
	w := verifyOTP(t, h, user.Email, plain)
	if w.Code != http.StatusUnauthorized || !strings.Contains(w.Body.String(), "invalid_otp") {
		t.Fatalf("expected stale OTP rejected with invalid_otp, got %d %s", w.Code, w.Body.String())
	}
	w = verifyOTP(t, h, user.Email, code)
	if w.Code != http.StatusOK {
		t.Fatalf("expected review code accepted, got %d %s", w.Code, w.Body.String())
	}
}

// TestReview_ResendPreservesVerifierAndBudgets pins that requests/resends for
// the enabled address never rotate the code or reset attempt history.
func TestReview_ResendPreservesVerifierAndBudgets(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-resend@example.com")
	cfg, code := reviewFixture(t, user)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, cfg)

	if w := verifyOTP(t, h, user.Email, "000000"); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected first wrong code 401, got %d", w.Code)
	}
	if w := requestOTP(t, h, user.Email); w.Code != http.StatusAccepted {
		t.Fatalf("expected resend 202, got %d", w.Code)
	}
	if len(sender.messages) != 0 {
		t.Fatal("resend must not email the review address")
	}
	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusOK {
		t.Fatalf("expected code still valid after resend, got %d %s", w.Code, w.Body.String())
	}
	// One wrong + one correct consumed 2 of 5; three more wrong exhaust it.
	for i := 0; i < 3; i++ {
		verifyOTP(t, h, user.Email, "000000")
	}
	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected budget exhausted after resend-preserving history, got %d", w.Code)
	}
}

// TestReview_AliasAddressUsesOrdinaryFlow pins exact-address selection: a
// different address (even a plus-alias) follows the ordinary OTP flow.
func TestReview_AliasAddressUsesOrdinaryFlow(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-exact@example.com")
	cfg, _ := reviewFixture(t, user)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, cfg)

	w := requestOTP(t, h, "review-exact+tag@example.com")
	if w.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", w.Code)
	}
	if len(sender.messages) != 1 {
		t.Fatalf("expected ordinary OTP email for alias, got %d", len(sender.messages))
	}
	w = verifyOTP(t, h, "review-exact+tag@example.com", "482916")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("review code must not authorize another address, got %d", w.Code)
	}
}

// TestReview_UUIDMismatchDenied pins the dual binding: the same email under
// a different configured UUID never authenticates via the exception.
func TestReview_UUIDMismatchDenied(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-uuid@example.com")
	cfg, code := reviewFixture(t, user)
	cfg.AccountID = "c3fb32fd-7c5c-5eb8-9779-b4a699b60822"
	h := newReviewHandler(t, store, nil, cfg)

	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected UUID mismatch denied, got %d", w.Code)
	}
	if _, err := store.GetUserByEmail(context.Background(), user.Email); err != nil {
		t.Fatalf("denial must not mutate the account: %v", err)
	}
}

// TestReview_AppleAccountDenied pins the provider fence: an Apple-created
// account at the configured address cannot use the review exception.
func TestReview_AppleAccountDenied(t *testing.T) {
	store := newTestStore(t)
	appleUser, err := store.UpsertUserByAppleSubject(context.Background(), "apple-sub-review", "review-apple@example.com")
	if err != nil {
		t.Fatalf("UpsertAppleUser: %v", err)
	}
	cfg, code := reviewFixture(t, appleUser)
	h := newReviewHandler(t, store, nil, cfg)

	if w := verifyOTP(t, h, appleUser.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected Apple account denied, got %d", w.Code)
	}
}

// cutoffReviewStore wraps a Store to inject an Apple consent cutoff on the
// lifecycle re-read. Production can never produce this state on the review
// path (ApplyAppleConsentCutoff selects by apple_subject, and review
// accounts are email-created with a nil subject — Apple-linked accounts are
// rejected by the binding check), but the wrapper pins that the removed dead
// Apple fence stays gone: a cutoff-bearing re-read must not deny review
// login with invalid_apple_token.
type cutoffReviewStore struct {
	db.Store
	cutoff time.Time
}

func (s cutoffReviewStore) GetUserByID(ctx context.Context, id string) (db.User, error) {
	u, err := s.Store.GetUserByID(ctx, id)
	if err != nil {
		return u, err
	}
	u.AppleConsentCutoff = &s.cutoff
	return u, nil
}

// TestReview_CutoffOnRereadDoesNotFence pins that the lifecycle re-check
// guards only the deletion race: even a cutoff-bearing re-read still issues
// the ordinary session, so review login can only ever fail with
// invalid_otp, matching the documented 401 contract.
func TestReview_CutoffOnRereadDoesNotFence(t *testing.T) {
	inner := newTestStore(t)
	user := mustCreateVerifiedUser(t, inner, "review-nofence@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, cutoffReviewStore{Store: inner, cutoff: time.Now()}, nil, cfg)

	w := verifyOTPWithDevice(t, h, user.Email, code, "device-nofence")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if resp := decodeAuthResponse(t, w); resp.User.ID != user.ID {
		t.Fatalf("expected session for review user, got %q", resp.User.ID)
	}
}

// TestReview_UnverifiedOrMissingDenied pins eligibility: unverified and
// missing accounts fail without issuing credentials or creating accounts.
func TestReview_UnverifiedOrMissingDenied(t *testing.T) {
	store := newTestStore(t)
	unverified, err := store.UpsertUser(context.Background(), "review-unverified@example.com")
	if err != nil {
		t.Fatalf("UpsertUser: %v", err)
	}
	cfg, code := reviewFixture(t, unverified)
	h := newReviewHandler(t, store, nil, cfg)

	if w := verifyOTP(t, h, unverified.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected unverified denied, got %d", w.Code)
	}

	missingCfg := ReviewAccessConfig{
		Enabled:      true,
		AccountID:    "b2ea21ec-6b4b-4da7-8668-a3a598a59711",
		AccountEmail: "review-missing@example.com",
		Verifier:     bytes.Repeat([]byte{0x01}, 32),
		Key:          bytes.Repeat([]byte{0x02}, 32),
	}
	hMissing := newReviewHandler(t, store, nil, missingCfg)
	if w := requestOTP(t, hMissing, "review-missing@example.com"); w.Code != http.StatusAccepted {
		t.Fatalf("expected missing-account request 202, got %d", w.Code)
	}
	if w := verifyOTP(t, hMissing, "review-missing@example.com", "482916"); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected missing-account verify 401, got %d", w.Code)
	}
	if _, err := store.GetUserByEmail(context.Background(), "review-missing@example.com"); err == nil {
		t.Fatal("failed review verify must not create an account")
	}
}

// TestReview_BudgetExhaustion429WithRetryAfter pins the durable budgets
// through the HTTP contract: the 6th evaluation gets 429 rate_limited with
// a Retry-After header, and the code never bypasses it.
func TestReview_BudgetExhaustion429WithRetryAfter(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-budget@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	for i := 0; i < 5; i++ {
		w := verifyOTPWithDevice(t, h, user.Email, code, fmt.Sprintf("d-%d", i))
		if w.Code != http.StatusOK {
			t.Fatalf("verify %d: expected 200, got %d %s", i, w.Code, w.Body.String())
		}
	}
	w := verifyOTP(t, h, user.Email, code)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "rate_limited") {
		t.Fatalf("expected rate_limited envelope, got %s", w.Body.String())
	}
	if w.Header().Get("Retry-After") == "" {
		t.Fatal("expected Retry-After header on review throttling")
	}
}

// TestReview_DisableRestoresOrdinaryFlow pins the shutdown direction:
// disabling removes the exception and restores mailed OTP for the address.
func TestReview_DisableRestoresOrdinaryFlow(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-disable@example.com")
	cfg, code := reviewFixture(t, user)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, cfg)

	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusOK {
		t.Fatalf("expected enabled verify 200, got %d", w.Code)
	}
	hDisabled := newReviewHandler(t, store, sender, ReviewAccessConfig{})
	if w := verifyOTP(t, hDisabled, user.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected disabled review code rejected, got %d", w.Code)
	}
	if w := requestOTP(t, hDisabled, user.Email); w.Code != http.StatusAccepted {
		t.Fatalf("expected disabled request 202, got %d", w.Code)
	}
	if len(sender.messages) != 1 {
		t.Fatalf("expected ordinary OTP email after disable, got %d", len(sender.messages))
	}
}

// TestReview_RotationInvalidatesOldCode pins verifier rotation: recomputing
// the binding with a new key/code invalidates the old code.
func TestReview_RotationInvalidatesOldCode(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-rotate@example.com")
	_, oldCode := reviewFixture(t, user)

	newKey := bytes.Repeat([]byte{0x09}, 32)
	newVerifierHex, err := auth.ComputeReviewVerifier(newKey, user.ID, user.Email, "770031")
	if err != nil {
		t.Fatalf("ComputeReviewVerifier: %v", err)
	}
	newVerifier, err := hex.DecodeString(newVerifierHex)
	if err != nil {
		t.Fatalf("decode verifier: %v", err)
	}
	rotated := ReviewAccessConfig{Enabled: true, AccountID: user.ID, AccountEmail: user.Email, Verifier: newVerifier, Key: newKey}
	hRotated := newReviewHandler(t, store, nil, rotated)

	if w := verifyOTP(t, hRotated, user.Email, oldCode); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected old code rejected after rotation, got %d", w.Code)
	}
	if w := verifyOTP(t, hRotated, user.Email, "770031"); w.Code != http.StatusOK {
		t.Fatalf("expected new code accepted, got %d %s", w.Code, w.Body.String())
	}
}

// TestReview_DeletionPurgesAndBlocks pins the lifecycle end: deleting the
// review account removes attempt history and the code cannot recreate or
// access it; ordinary re-registration under the same email inherits nothing.
func TestReview_DeletionPurgesAndBlocks(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-delete@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusOK {
		t.Fatalf("expected pre-delete verify 200, got %d", w.Code)
	}
	digestFn := func(subject string) string { return "digest:" + subject }
	if _, err := store.PurgeUser(context.Background(), user.ID, "", digestFn); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected post-delete verify 401, got %d", w.Code)
	}
	// Ordinary re-registration creates a different UUID: no inherited exception.
	replacement, err := store.UpsertUser(context.Background(), user.Email)
	if err != nil {
		t.Fatalf("UpsertUser replacement: %v", err)
	}
	if replacement.ID == user.ID {
		t.Fatal("expected replacement account to carry a new UUID")
	}
	if err := store.SetUserVerified(context.Background(), replacement.ID); err != nil {
		t.Fatalf("SetUserVerified: %v", err)
	}
	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected replacement UUID denied, got %d", w.Code)
	}
}

// TestReview_TwoDevicesIndependent pins ordinary per-device sessions: two
// review logins own independent refresh families and one logout keeps the
// other alive.
func TestReview_TwoDevicesIndependent(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-devices@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	wa := verifyOTPWithDevice(t, h, user.Email, code, "device-a")
	wb := verifyOTPWithDevice(t, h, user.Email, code, "device-b")
	if wa.Code != http.StatusOK || wb.Code != http.StatusOK {
		t.Fatalf("expected both devices 200, got %d/%d", wa.Code, wb.Code)
	}
	ra, rb := decodeAuthResponse(t, wa), decodeAuthResponse(t, wb)
	if ra.RefreshToken == rb.RefreshToken {
		t.Fatal("expected independent refresh tokens per device")
	}

	if w := logoutCall(h, ra, "device-a"); w.Code != http.StatusNoContent {
		t.Fatalf("expected logout 204, got %d %s", w.Code, w.Body.String())
	}
	// Device B refreshes unaffected.
	if w := refreshCall(h, rb.RefreshToken, "device-b"); w.Code != http.StatusOK {
		t.Fatalf("expected device-b refresh 200 after device-a logout, got %d %s", w.Code, w.Body.String())
	}
}

// TestReview_OrdinaryOTPRegression pins that the enabled exception changes
// nothing for other addresses: ordinary request/verify still works.
func TestReview_OrdinaryOTPRegression(t *testing.T) {
	store := newTestStore(t)
	reviewUser := mustCreateVerifiedUser(t, store, "review-other-cfg@example.com")
	cfg, _ := reviewFixture(t, reviewUser)
	sender := &captureSender{}
	h := newReviewHandler(t, store, sender, cfg)

	if w := requestOTP(t, h, "ordinary@example.com"); w.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", w.Code)
	}
	if len(sender.messages) != 1 {
		t.Fatalf("expected one OTP email, got %d", len(sender.messages))
	}
	var code string
	for _, line := range strings.Split(sender.messages[0].Text, "\n") {
		if c := strings.TrimSpace(line); len(c) == 6 {
			code = c
		}
	}
	if code == "" {
		t.Fatal("OTP email carried no code")
	}
	if w := verifyOTP(t, h, "ordinary@example.com", code); w.Code != http.StatusOK {
		t.Fatalf("expected ordinary verify 200, got %d %s", w.Code, w.Body.String())
	}
}

// TestReview_ResponsesLeakNoSecrets pins the telemetry/redaction contract:
// no error or success body carries the code, key, verifier, or email.
func TestReview_ResponsesLeakNoSecrets(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-leak@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	bodies := []string{}
	bodies = append(bodies, requestOTP(t, h, user.Email).Body.String())
	bodies = append(bodies, verifyOTP(t, h, user.Email, code).Body.String())
	bodies = append(bodies, verifyOTP(t, h, user.Email, "000000").Body.String())
	for _, b := range bodies {
		// The code, key, and verifier must never appear in any response.
		// (The success envelope carries the account's own profile email by
		// existing contract; error envelopes must not name the address.)
		for _, secret := range []string{code, string(cfg.Key), hex.EncodeToString(cfg.Verifier)} {
			if secret != "" && strings.Contains(b, secret) {
				t.Fatalf("response leaks secret material: %s", b)
			}
		}
	}
	errBody := verifyOTP(t, h, user.Email, "000000").Body.String()
	if strings.Contains(errBody, user.Email) {
		t.Fatalf("error response names the address: %s", errBody)
	}
}

// TestReview_DiagnosticsLeakNoSecrets pins the telemetry contract: bounded
// review-auth outcome logs carry no submitted code, key, verifier, token,
// email, or request body.
func TestReview_DiagnosticsLeakNoSecrets(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-diag@example.com")
	cfg, code := reviewFixture(t, user)

	var logs bytes.Buffer
	rateLimiter := &RateLimiterGroup{
		OTPRequest: ratelimit.NewTokenBucket(100, 100, time.Minute),
		OTPVerify:  ratelimit.NewTokenBucket(100, 100, time.Minute),
		Apple:      ratelimit.NewTokenBucket(100, 100, time.Minute),
		Status:     ratelimit.NewTokenBucket(100, 100, time.Minute),
	}
	h := NewHandler(store,
		auth.NewTokenService("test-secret-key-at-least-32-bytes!!", 15*time.Minute, 7*24*time.Hour),
		auth.NewOTPService(10*time.Minute, 5),
		email.NewConsoleSender(slog.New(slog.NewTextHandler(&logs, nil))),
		rateLimiter, nil, HandlerConfig{},
		slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug})),
		testRecoveryKeyring(),
		WithReviewAccess(cfg))

	requestOTP(t, h, user.Email)
	verifyOTP(t, h, user.Email, code)
	verifyOTP(t, h, user.Email, "000000")
	for i := 0; i < 5; i++ {
		verifyOTP(t, h, user.Email, "000000")
	}
	out := logs.String()
	if !strings.Contains(out, "review auth outcome") {
		t.Fatal("expected bounded review outcome diagnostics")
	}
	for _, secret := range []string{code, user.Email, user.ID, string(cfg.Key), hex.EncodeToString(cfg.Verifier)} {
		if secret != "" && strings.Contains(out, secret) {
			t.Fatalf("diagnostics leak secret material: %q", secret)
		}
	}
}

// TestReview_DisabledByDefaultHandler pins that a zero ReviewAccessConfig
// leaves both endpoints on ordinary behavior (missing account verify 401).
func TestReview_DisabledByDefaultHandler(t *testing.T) {
	store := newTestStore(t)
	h := newTestHandler(t, store)

	if w := requestOTP(t, h, "nobody@example.com"); w.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d", w.Code)
	}
	if w := verifyOTP(t, h, "nobody@example.com", "482916"); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

// TestReview_SessionIsOrdinaryAccountBound pins that a review login issues
// ordinary account-scoped credentials: the session reads its own account's
// data, cannot touch another account, and dies with the account — refresh
// after purge is an ordinary authentication failure, never resurrection.
func TestReview_SessionIsOrdinaryAccountBound(t *testing.T) {
	store := newTestStore(t)
	user := mustCreateVerifiedUser(t, store, "review-bound@example.com")
	other := mustCreateVerifiedUser(t, store, "review-bound-other@example.com")
	cfg, code := reviewFixture(t, user)
	h := newReviewHandler(t, store, nil, cfg)

	w := verifyOTP(t, h, user.Email, code)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", w.Code, w.Body.String())
	}
	sess := decodeAuthResponse(t, w)

	entry, created, err := store.CreateEntry(context.Background(), db.Entry{
		ID: v7(), UserID: user.ID, ActivityText: "Review entry",
		StartedAt: time.Now().Add(-time.Hour),
	})
	if err != nil || !created {
		t.Fatalf("CreateEntry: created=%v err=%v", created, err)
	}
	if _, err := store.GetEntry(context.Background(), other.ID, entry.ID); err == nil {
		t.Fatal("other account must not read the review account's entry")
	}

	digestFn := func(subject string) string { return "digest:" + subject }
	if _, err := store.PurgeUser(context.Background(), user.ID, "", digestFn); err != nil {
		t.Fatalf("PurgeUser: %v", err)
	}
	if w := refreshCall(h, sess.RefreshToken, "device-x"); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected post-purge refresh 401, got %d %s", w.Code, w.Body.String())
	}
	if w := verifyOTP(t, h, user.Email, code); w.Code != http.StatusUnauthorized {
		t.Fatalf("expected post-purge verify 401 (no resurrection), got %d", w.Code)
	}
}
