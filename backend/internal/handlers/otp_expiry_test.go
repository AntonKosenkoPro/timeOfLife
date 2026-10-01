package handlers

import (
	"context"
	"net/http"
	"testing"
	"time"
)

// TestOTP_ExpiryBoundary pins where expiry is enforced. The store filters
// expired rows (expires_at > NOW) before the handler ever sees them, so a
// store-expired OTP surfaces as invalid_otp — the handler's otp_expired
// branch is only reachable in a store-then-check race (documented, not
// simulated here).
func TestOTP_ExpiryBoundary(t *testing.T) {
	ctx := context.Background()

	t.Run("expired in store is invalid_otp, not otp_expired", func(t *testing.T) {
		store := newTestStore(t)
		sender := &captureSender{}
		h := newTestHandlerWithDependencies(t, store, nil, sender)

		user, err := store.UpsertUser(ctx, "expired-boundary@example.com")
		if err != nil {
			t.Fatalf("UpsertUser: %v", err)
		}
		code, hash, err := h.otpService.GenerateOTP()
		if err != nil {
			t.Fatalf("GenerateOTP: %v", err)
		}
		_ = code
		if err := store.SaveOTP(ctx, user.ID, hash, time.Now().Add(-time.Minute), 5); err != nil {
			t.Fatalf("SaveOTP: %v", err)
		}

		w := verifyOTPWithDevice(t, h, "expired-boundary@example.com", "000000", "device-1")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d (%s)", w.Code, w.Body.String())
		}
		if code := errCode(t, w); code != "invalid_otp" {
			t.Errorf("expected invalid_otp (store filters expired rows), got %q", code)
		}
	})

	t.Run("valid OTP verifies within expiry", func(t *testing.T) {
		store := newTestStore(t)
		sender := &captureSender{}
		h := newTestHandlerWithDependencies(t, store, nil, sender)

		email := "fresh-boundary@example.com"
		if w := requestOTP(t, h, email); w.Code != http.StatusAccepted {
			t.Fatalf("otp request: expected 202, got %d", w.Code)
		}
		w := verifyOTPWithDevice(t, h, email, capturedOTP(t, sender), "device-1")
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200 within expiry, got %d (%s)", w.Code, w.Body.String())
		}
	})

	t.Run("configured max attempts threads into stored OTP", func(t *testing.T) {
		store := newTestStore(t)

		user, err := store.UpsertUser(ctx, "attempts-budget@example.com")
		if err != nil {
			t.Fatalf("UpsertUser: %v", err)
		}
		if err := store.SaveOTP(ctx, user.ID, "hash", time.Now().Add(10*time.Minute), 1); err != nil {
			t.Fatalf("SaveOTP: %v", err)
		}
		otp, err := store.GetValidOTP(ctx, user.ID)
		if err != nil {
			t.Fatalf("GetValidOTP: %v", err)
		}
		if otp.MaxAttempts != 1 {
			t.Fatalf("expected stored budget 1, got %d", otp.MaxAttempts)
		}
		// One wrong attempt exhausts the budget: the row is no longer valid.
		if err := store.IncrementOTPAttempts(ctx, otp.ID); err != nil {
			t.Fatalf("IncrementOTPAttempts: %v", err)
		}
		if _, err := store.GetValidOTP(ctx, user.ID); err == nil {
			t.Error("expected exhausted OTP to be invisible, got nil error")
		}
	})
}
