package ratelimit

import (
	"testing"
	"time"
)

// TestBurst_Isolation pins per-key and per-bucket isolation with fresh
// buckets. The production globals (OTPRequestLimit/OTPVerifyLimit/AppleLimit)
// are deliberately NOT used here: they are process-wide, so any test that
// spends their tokens would flake against other tests running in the same
// binary. Isolation of the globals themselves is covered by construction
// (three separate buckets); what matters is the mechanism, pinned below.
func TestBurst_Isolation(t *testing.T) {
	t.Run("exhausting one key leaves other keys live", func(t *testing.T) {
		b := NewTokenBucket(3, 3, time.Minute)
		for i := 0; i < 3; i++ {
			if !b.Allow("victim") {
				t.Fatalf("victim request %d: expected allow", i)
			}
		}
		if b.Allow("victim") {
			t.Error("expected victim bucket exhausted (429)")
		}
		if !b.Allow("neighbor") {
			t.Error("expected neighbor key unaffected by victim burst")
		}
	})

	t.Run("exhausting one bucket leaves a sibling bucket live", func(t *testing.T) {
		otp := NewTokenBucket(3, 3, time.Minute)
		apple := NewTokenBucket(5, 5, time.Minute)
		for i := 0; i < 3; i++ {
			otp.Allow("same-ip:same-email")
		}
		if otp.Allow("same-ip:same-email") {
			t.Error("expected OTP bucket exhausted")
		}
		// Same client, different feature bucket: unaffected (cross-feature
		// isolation — Apple traffic cannot starve or be starved by OTP).
		for i := 0; i < 5; i++ {
			if !apple.Allow("same-ip") {
				t.Fatalf("apple request %d: expected allow despite OTP exhaustion", i)
			}
		}
	})

	t.Run("burst cap bounds immediate spend", func(t *testing.T) {
		b := NewTokenBucket(100, 2, time.Minute)
		for i := 0; i < 2; i++ {
			if !b.Allow("k") {
				t.Fatalf("burst request %d: expected allow", i)
			}
		}
		if b.Allow("k") {
			t.Error("expected third immediate request denied (burst=2)")
		}
	})
}
