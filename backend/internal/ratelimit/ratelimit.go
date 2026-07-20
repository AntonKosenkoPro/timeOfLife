// Package ratelimit provides in-memory token bucket rate limiting.
package ratelimit

import (
	"sync"
	"time"
)

// TokenBucket implements a per-key token bucket rate limiter.
type TokenBucket struct {
	mu       sync.Mutex
	rate     float64       // tokens added per interval
	burst    int           // maximum accumulated tokens
	interval time.Duration // time between refills
	tokens   map[string]*bucketEntry
}

type bucketEntry struct {
	tokens    float64
	lastCheck time.Time
}

// NewTokenBucket creates a new TokenBucket.
// rate is the number of tokens added per interval.
// burst is the maximum number of tokens a key can accumulate.
// interval is the duration between refills.
func NewTokenBucket(rate float64, burst int, interval time.Duration) *TokenBucket {
	return &TokenBucket{
		rate:     rate,
		burst:    burst,
		interval: interval,
		tokens:   make(map[string]*bucketEntry),
	}
}

// Allow checks if a request for the given key is allowed.
// It returns true if the request should be permitted.
func (tb *TokenBucket) Allow(key string) bool {
	tb.mu.Lock()
	defer tb.mu.Unlock()

	now := time.Now()
	entry, ok := tb.tokens[key]
	if !ok {
		// First request for this key — start with burst-1 tokens remaining.
		tb.tokens[key] = &bucketEntry{
			tokens:    float64(tb.burst - 1),
			lastCheck: now,
		}
		return true
	}

	// Refill tokens based on elapsed time.
	elapsed := now.Sub(entry.lastCheck)
	refill := tb.rate * elapsed.Seconds() / tb.interval.Seconds()
	entry.tokens = minFloat(entry.tokens+refill, float64(tb.burst))
	entry.lastCheck = now

	if entry.tokens >= 1 {
		entry.tokens--
		return true
	}

	return false
}

// Cleanup removes stale entries that have not been accessed for longer than
// the given duration. This prevents unbounded memory growth.
func (tb *TokenBucket) Cleanup(maxAge time.Duration) {
	tb.mu.Lock()
	defer tb.mu.Unlock()

	now := time.Now()
	for key, entry := range tb.tokens {
		if now.Sub(entry.lastCheck) > maxAge {
			delete(tb.tokens, key)
		}
	}
}

func minFloat(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// Common rate limit configurations.
var (
	// OTPRequestLimit limits OTP request attempts: 3 per minute per key.
	OTPRequestLimit = NewTokenBucket(3, 3, time.Minute)

	// OTPVerifyLimit limits OTP verification attempts: 5 per minute per key.
	OTPVerifyLimit = NewTokenBucket(5, 5, time.Minute)
)
