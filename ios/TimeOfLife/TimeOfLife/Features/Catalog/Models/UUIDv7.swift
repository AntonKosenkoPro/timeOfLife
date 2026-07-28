import Foundation

/// Minimal UUID v7 generator (RFC 9562) implemented inline — no new dependency.
///
/// Layout: 48-bit unix-ms timestamp | version nibble (0x7) | 12-bit rand_a |
/// variant nibble (0b10) | 62-bit rand_b. The randomness uses
/// `SystemRandomNumberGenerator`. v7 ids are time-ordered-ish, which gives the
/// catalog client monotonic-ish ids and is the format the backend validates on
/// POST (S2 / "Sync & ids").
enum UUIDv7 {
    /// Generates a new UUID v7 from the current time + randomness.
    static func generate(using rng: inout SystemRandomNumberGenerator, now: Date = Date()) -> UUID {
        let ms = UInt64(now.timeIntervalSince1970 * 1000)

        // 74 random bits: 12 bits (rand_a) + 62 bits (rand_b).
        let r1 = rng.next() // UInt64
        let r2 = rng.next() // UInt64

        let randA = UInt16(r1 & 0x0FFF)            // 12 bits
        let randB = UInt64(r2 & 0x3FFFFFFFFFFFFFFF) // 62 bits

        // uuid_t is 16 bytes laid out (RFC 9562 §6):
        //  [0..5]  unix_ts_ms (big-endian, 48 bits)
        //  [6]     ver_and_rand_a_hi: 0x70 | randA high 4 bits
        //  [7]     rand_a_lo (low 8 bits)
        //  [8]     variant (0b10xxxxxx)
        //  [9..15] rand_b low 56 bits
        var bytes = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

        bytes.0 = UInt8((ms >> 40) & 0xFF)
        bytes.1 = UInt8((ms >> 32) & 0xFF)
        bytes.2 = UInt8((ms >> 24) & 0xFF)
        bytes.3 = UInt8((ms >> 16) & 0xFF)
        bytes.4 = UInt8((ms >> 8) & 0xFF)
        bytes.5 = UInt8(ms & 0xFF)

        bytes.6 = 0x70 | UInt8((randA >> 8) & 0x0F)
        bytes.7 = UInt8(randA & 0xFF)

        bytes.8 = 0x80 | UInt8((randB >> 56) & 0x3F)
        bytes.9 = UInt8((randB >> 48) & 0xFF)
        bytes.10 = UInt8((randB >> 40) & 0xFF)
        bytes.11 = UInt8((randB >> 32) & 0xFF)
        bytes.12 = UInt8((randB >> 24) & 0xFF)
        bytes.13 = UInt8((randB >> 16) & 0xFF)
        bytes.14 = UInt8((randB >> 8) & 0xFF)
        bytes.15 = UInt8(randB & 0xFF)

        return UUID(uuid: bytes)
    }

    /// Convenience using the system RNG.
    static func generate(now: Date = Date()) -> UUID {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng, now: now)
    }
}

extension UUID {
    /// A freshly generated UUID v7 (RFC 9562).
    static func v7() -> UUID { UUIDv7.generate() }
}
