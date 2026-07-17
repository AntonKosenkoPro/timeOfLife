import Foundation

/// In-memory token-bucket rate limiter. Single-instance only (swap for Redis before scaling).
/// Keys are composite strings (e.g. "signin:127.0.0.1" or "signin:user@example.com").
actor RateLimiter {
    /// Per-key bucket state.
    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
    }

    private var buckets: [String: Bucket] = [:]
    let capacity: Int          // max burst
    let refillRatePerSecond: Double  // tokens added per second
    let retryAfterSeconds: Int

    init(capacity: Int = 5, refillRatePerSecond: Double = 0.5, retryAfterSeconds: Int = 30) {
        self.capacity = capacity
        self.refillRatePerSecond = refillRatePerSecond
        self.retryAfterSeconds = retryAfterSeconds
    }

    /// Try to consume one token for `key`. Returns nil if allowed, otherwise the
    /// seconds until the next token becomes available.
    func tryConsume(_ key: String) -> Int? {
        refill(key)
        guard let bucket = buckets[key], bucket.tokens >= 1.0 else {
            return retryAfterSeconds
        }
        buckets[key]?.tokens -= 1.0
        return nil
    }

    private func refill(_ key: String) {
        let now = Date()
        if var bucket = buckets[key] {
            let elapsed = now.timeIntervalSince(bucket.lastRefill)
            let refilled = elapsed * refillRatePerSecond
            bucket.tokens = min(Double(capacity), bucket.tokens + refilled)
            bucket.lastRefill = now
            buckets[key] = bucket
        } else {
            buckets[key] = Bucket(tokens: Double(capacity), lastRefill: now)
        }
    }

    /// Test helper: reset all buckets.
    func reset() {
        buckets.removeAll()
    }
}