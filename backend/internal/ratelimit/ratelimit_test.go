package ratelimit

import (
	"testing"
	"time"
)

func TestTokenBucket_Allow_ReturnsTrueForFirstRequest(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, time.Second)

	if !tb.Allow("key1") {
		t.Error("Allow returned false for first request")
	}
}

func TestTokenBucket_Allow_ReturnsFalseWhenRateLimited(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, time.Minute)

	// First request should succeed
	if !tb.Allow("key-limited") {
		t.Fatal("Allow returned false for first request")
	}

	// Second request should be rate limited (burst=1, rate=1/min)
	if tb.Allow("key-limited") {
		t.Error("Allow returned true when rate limited")
	}
}

func TestTokenBucket_Allow_RefillsTokensOverTime(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, 50*time.Millisecond)

	// First request succeeds
	if !tb.Allow("key-refill") {
		t.Fatal("Allow returned false for first request")
	}

	// Second request should be rate limited
	if tb.Allow("key-refill") {
		t.Fatal("Allow returned true when rate limited (should be false)")
	}

	// Wait for refill
	time.Sleep(60 * time.Millisecond)

	// Now it should succeed again
	if !tb.Allow("key-refill") {
		t.Error("Allow returned false after refill period")
	}
}

func TestTokenBucket_Allow_DifferentKeysAreIndependent(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, time.Minute)

	// Exhaust key-a
	if !tb.Allow("key-a") {
		t.Fatal("Allow returned false for first request on key-a")
	}
	if tb.Allow("key-a") {
		t.Fatal("Allow returned true for second request on key-a (should be false)")
	}

	// key-b should still work
	if !tb.Allow("key-b") {
		t.Error("Allow returned false for first request on key-b (should be true)")
	}
}

func TestTokenBucket_Allow_MultipleTokens(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(3, 3, time.Minute)

	// First 3 requests should succeed
	for i := 0; i < 3; i++ {
		if !tb.Allow("key-multi") {
			t.Fatalf("Allow returned false on request %d (should be true)", i+1)
		}
	}

	// 4th request should be rate limited
	if tb.Allow("key-multi") {
		t.Error("Allow returned true when burst exhausted")
	}
}

func TestTokenBucket_Cleanup_RemovesStaleEntries(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, time.Minute)

	// Create an entry
	tb.Allow("stale-key")

	// Verify entry exists
	tb.mu.Lock()
	_, exists := tb.tokens["stale-key"]
	tb.mu.Unlock()
	if !exists {
		t.Fatal("expected stale-key to exist in map")
	}

	// Cleanup with zero maxAge should remove it
	tb.Cleanup(0)

	tb.mu.Lock()
	_, exists = tb.tokens["stale-key"]
	tb.mu.Unlock()
	if exists {
		t.Error("expected stale-key to be removed after cleanup")
	}
}

func TestTokenBucket_Cleanup_KeepsRecentEntries(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 1, time.Minute)

	tb.Allow("recent-key")

	// Cleanup with large maxAge should keep it
	tb.Cleanup(time.Hour)

	tb.mu.Lock()
	_, exists := tb.tokens["recent-key"]
	tb.mu.Unlock()
	if !exists {
		t.Error("expected recent-key to still exist after cleanup with large maxAge")
	}
}

func TestTokenBucket_Allow_RefillWithHighRate(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(10, 5, time.Second)

	// Exhaust all 5 tokens
	for i := 0; i < 5; i++ {
		if !tb.Allow("key-high") {
			t.Fatalf("Allow returned false on request %d", i+1)
		}
	}

	// Should be rate limited now
	if tb.Allow("key-high") {
		t.Error("Allow returned true when burst exhausted")
	}
}

func TestTokenBucket_Allow_ConcurrentAccess(t *testing.T) {
	t.Parallel()

	tb := NewTokenBucket(1, 5, time.Minute)

	done := make(chan bool, 10)
	for i := 0; i < 10; i++ {
		go func() {
			tb.Allow("concurrent-key")
			done <- true
		}()
	}

	// Wait for all goroutines
	for i := 0; i < 10; i++ {
		<-done
	}

	// Verify no panic occurred (the test reaching here means no data race)
	tb.mu.Lock()
	entry, exists := tb.tokens["concurrent-key"]
	tb.mu.Unlock()
	if !exists {
		t.Error("expected concurrent-key to exist")
	}
	if entry.tokens < 0 {
		t.Errorf("tokens should not be negative, got %f", entry.tokens)
	}
}

func TestTokenBucket_OTPRequestLimit(t *testing.T) {
	t.Parallel()

	// OTPRequestLimit is 3 per minute
	tb := OTPRequestLimit

	// First 3 should succeed
	for i := 0; i < 3; i++ {
		if !tb.Allow("otp-req-test") {
			t.Fatalf("Allow returned false on request %d", i+1)
		}
	}

	// 4th should fail
	if tb.Allow("otp-req-test") {
		t.Error("Allow returned true when OTP request rate limited")
	}
}

func TestTokenBucket_OTPVerifyLimit(t *testing.T) {
	t.Parallel()

	// OTPVerifyLimit is 5 per minute
	tb := OTPVerifyLimit

	// First 5 should succeed
	for i := 0; i < 5; i++ {
		if !tb.Allow("otp-verify-test") {
			t.Fatalf("Allow returned false on request %d", i+1)
		}
	}

	// 6th should fail
	if tb.Allow("otp-verify-test") {
		t.Error("Allow returned true when OTP verify rate limited")
	}
}
