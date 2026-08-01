import Testing
import Foundation
@testable import TimeOfLife

@Suite("UUIDv7")
struct UUIDv7Tests {

    /// Backend validation regex (catalog_validators.go): canonical lowercase v7.
    /// `UUID().uuidString` is uppercase, so match case-insensitively (the
    /// backend lowercases before validating).
    private let v7Regex = #"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#

    private func matchesV7(_ s: String) -> Bool {
        s.range(of: v7Regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @Test("v7 format: version nibble 7, variant 0b10xx")
    func format() {
        for _ in 0..<256 {
            let s = UUID.v7().uuidString
            #expect(matchesV7(s), "Bad v7 format: \(s)")
        }
    }

    @Test("v7 embeds the unix-ms timestamp in the leading 48 bits")
    func timestampPrefix() {
        let now = Date(timeIntervalSince1970: 1_785_142_800) // 2026-07-27T09:00:00Z
        let uuid = UUIDv7.generate(now: now)
        let s = uuid.uuidString
        let hex = String(s.prefix(8)) + String(s.dropFirst(9).prefix(4))
        let ms = UInt64(hex, radix: 16)
        #expect(ms == UInt64(now.timeIntervalSince1970 * 1000))
    }

    @Test("v7 is unique across 10_000 generations")
    func uniqueness() {
        var seen = Set<UUID>()
        for _ in 0..<10_000 {
            seen.insert(UUID.v7())
        }
        #expect(seen.count == 10_000)
    }

    @Test("UUID.v7() convenience matches the generator")
    func convenience() {
        let a = UUID.v7()
        #expect(matchesV7(a.uuidString))
    }
}
