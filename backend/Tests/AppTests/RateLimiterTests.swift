import XCTest
@testable import App

final class RateLimiterTests: XCTestCase {

    func testAllowsUpToCapacityThenThrottles() async {
        let limiter = RateLimiter(capacity: 3, refillRatePerSecond: 0.0, retryAfterSeconds: 5)
        let key = "k"
        // First 3 succeed.
        for _ in 0..<3 {
            let r = await limiter.tryConsume(key)
            XCTAssertNil(r)
        }
        // 4th throttled with retry-after.
        let r = await limiter.tryConsume(key)
        XCTAssertEqual(r, 5)
    }

    func testRefillRestoresTokens() async throws {
        let limiter = RateLimiter(capacity: 2, refillRatePerSecond: 100.0, retryAfterSeconds: 1)
        let key = "k"
        let a = await limiter.tryConsume(key)
        XCTAssertNil(a)
        let b = await limiter.tryConsume(key)
        XCTAssertNil(b)
        // Now empty; throttle.
        let c = await limiter.tryConsume(key)
        XCTAssertEqual(c, 1)
        // Wait ~50ms so refilled tokens >= 1.
        try await Task.sleep(nanoseconds: 60_000_000)
        let d = await limiter.tryConsume(key)
        XCTAssertNil(d)
    }

    func testIndependentKeys() async {
        let limiter = RateLimiter(capacity: 1, refillRatePerSecond: 0.0, retryAfterSeconds: 1)
        let a = await limiter.tryConsume("a")
        XCTAssertNil(a)
        let b = await limiter.tryConsume("b")
        XCTAssertNil(b)
        let c = await limiter.tryConsume("a")
        XCTAssertEqual(c, 1)
    }
}