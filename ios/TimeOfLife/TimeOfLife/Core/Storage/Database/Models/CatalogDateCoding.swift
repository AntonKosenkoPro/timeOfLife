import Foundation

/// ISO 8601 date coding that preserves fractional seconds, matching the
/// backend's RFC 3339 output.
///
/// The standard `ISO8601DateFormatter` without `.withFractionalSeconds`
/// silently truncates sub-second precision, which corrupts short entries
/// (e.g. a 0.3-second entry whose `started_at == ended_at` after rounding).
/// This helper ensures every network DTO round-trips with full precision.
enum CatalogDateCoding {

    /// Creates a new formatter configured for fractional-second ISO 8601.
    /// `ISO8601DateFormatter` is not `Sendable`, so we create one per call
    /// rather than sharing a static instance under strict concurrency.
    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// Parses an ISO 8601 string with optional fractional seconds.
    ///
    /// The backend emits `RFC3339Nano`, which omits the fractional part
    /// entirely when sub-second is zero (e.g. `2026-07-27T09:00:00Z`).
    /// `ISO8601DateFormatter` with `.withFractionalSeconds` rejects
    /// fraction-less input, so fall back to the non-fractional formatter
    /// (which also accepts non-Zulu offsets like `+00:00`).
    static func decode(_ string: String) -> Date? {
        if let date = makeFormatter().date(from: string) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: string)
    }

    /// Formats a `Date` as an ISO 8601 string with fractional seconds.
    static func encode(_ date: Date) -> String {
        makeFormatter().string(from: date)
    }
}

// MARK: - Codable helpers

/// A `JSONDecoder` pre-configured to preserve fractional seconds for the
/// catalog DTOs.
extension JSONDecoder {
    static var catalogDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = CatalogDateCoding.decode(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

/// A `JSONEncoder` pre-configured to emit fractional seconds for the
/// catalog DTOs.
extension JSONEncoder {
    static var catalogEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CatalogDateCoding.encode(date))
        }
        return encoder
    }
}
