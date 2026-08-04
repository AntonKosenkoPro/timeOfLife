import Foundation

/// UUID v7 generator (time-ordered, RFC 9562).
///
/// Produces a UUID whose first 48 bits encode the current Unix timestamp in
/// milliseconds, followed by 12 bits of random "rand_a" and 62 bits of random
/// "rand_b" (with the version and variant bits set correctly). This gives
/// monotonically sortable IDs suitable for client-generated primary keys.
enum UUIDv7 {

    /// Generates a new UUID v7 string.
    static func generate() -> String {
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)

        // 48-bit timestamp
        let t0 = UInt8((ms >> 40) & 0xFF)
        let t1 = UInt8((ms >> 32) & 0xFF)
        let t2 = UInt8((ms >> 24) & 0xFF)
        let t3 = UInt8((ms >> 16) & 0xFF)
        let t4 = UInt8((ms >> 8) & 0xFF)
        let t5 = UInt8(ms & 0xFF)

        // 12-bit rand_a (with version 7 in the top 4 bits)
        var randA = UInt16.random(in: 0..<0x1000)
        randA |= 0x7000
        let r0 = UInt8((randA >> 8) & 0xFF)
        let r1 = UInt8(randA & 0xFF)

        // 62-bit rand_b (with variant 10 in the top 2 bits)
        var randBHi = UInt8.random(in: 0..<0x40)
        randBHi |= 0x80
        let r2 = randBHi
        let r3 = UInt8.random(in: .min ... .max)
        let r4 = UInt8.random(in: .min ... .max)
        let r5 = UInt8.random(in: .min ... .max)
        let r6 = UInt8.random(in: .min ... .max)
        let r7 = UInt8.random(in: .min ... .max)

        let bytes: [UInt8] = [t0, t1, t2, t3, t4, t5, r0, r1, r2, r3, r4, r5, r6, r7, 0, 0]

        var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { ptr in
            for (index, byte) in bytes.enumerated() {
                ptr[index] = byte
            }
        }

        return UUID(uuid: uuid).uuidString.lowercased()
    }
}
