@preconcurrency import Foundation
import OSLog

// MARK: - Date coding

/// Shared RFC 3339 date coding for catalog network DTOs.
///
/// The shared `APIClient` uses a plain `JSONDecoder`/`JSONEncoder`
/// (deferred-to-date). Network DTOs therefore decode/encode dates as ISO 8601
/// strings explicitly, leaving the client unchanged. Local persistence
/// (`CatalogStore`) uses deferred-to-date `Double` — separate concern.
enum CatalogDateCoding {
    /// Decodes RFC 3339 with optional fractional seconds. `ISO8601DateFormatter`
    /// is thread-safe for formatting (unlike `DateFormatter`); the formatter is
    /// never mutated after construction.
    private static let fractionalDecoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDecoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let encoder: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses an RFC 3339 date string (with or without fractional seconds).
    static func decode(_ string: String) -> Date? {
        fractionalDecoder.date(from: string) ?? plainDecoder.date(from: string)
    }

    /// Formats a date as an RFC 3339 string.
    static func encode(_ date: Date) -> String {
        encoder.string(from: date)
    }

    /// Decodes a required date key from an RFC 3339 string.
    static func decodeDate<K: CodingKey>(_ container: KeyedDecodingContainer<K>,
                                         forKey key: K) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        guard let date = decode(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container,
                debugDescription: "Unparseable RFC 3339 date: \(raw)"
            )
        }
        return date
    }
}

// MARK: - Resource shapes

/// Category resource shape from `GET /categories` / `GET /activities` `categories[]`.
struct CategoryDTO: Decodable, Sendable, Equatable {
    let id: UUID
    let name: String
    let color: ActivityColor
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.color = try c.decode(ActivityColor.self, forKey: .color)
        self.createdAt = try CatalogDateCoding.decodeDate(c, forKey: .createdAt)
        self.updatedAt = try CatalogDateCoding.decodeDate(c, forKey: .updatedAt)
    }

    init(id: UUID, name: String, color: ActivityColor, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func toCategory() -> Category {
        Category(id: id, name: name, color: color, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Activity resource shape from `GET /activities` (list) and `GET /activities/{id}`.
/// Carries the resolved `categories[]` (F9 resolution at query time).
struct ActivityDTO: Decodable, Sendable, Equatable {
    let id: UUID
    let name: String
    let color: ActivityColor
    let icon: ActivityIcon
    let notes: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let categories: [CategoryDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, color, icon, notes, categories
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.color = try c.decode(ActivityColor.self, forKey: .color)
        self.icon = try c.decode(ActivityIcon.self, forKey: .icon)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        if let raw = try c.decodeIfPresent(String.self, forKey: .lastUsedAt) {
            if let date = CatalogDateCoding.decode(raw) {
                self.lastUsedAt = date
            } else {
                os_log(.error, "Unparseable last_used_at date: %{public}@", raw)
                self.lastUsedAt = nil
            }
        } else {
            self.lastUsedAt = nil
        }
        self.createdAt = try CatalogDateCoding.decodeDate(c, forKey: .createdAt)
        self.updatedAt = try CatalogDateCoding.decodeDate(c, forKey: .updatedAt)
        self.categories = try c.decodeIfPresent([CategoryDTO].self, forKey: .categories) ?? []
    }

    init(
        id: UUID,
        name: String,
        color: ActivityColor,
        icon: ActivityIcon,
        notes: String?,
        lastUsedAt: Date?,
        createdAt: Date,
        updatedAt: Date,
        categories: [CategoryDTO]
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.notes = notes
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.categories = categories
    }

    /// Maps to the domain `Activity`, deriving `categoryIds` from resolved categories.
    func toActivity() -> Activity {
        Activity(
            id: id,
            name: name,
            color: color,
            icon: icon,
            notes: notes,
            lastUsedAt: lastUsedAt,
            categoryIds: categories.map(\.id),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Request bodies

/// `POST /activities` body: `{id, name, color, icon, notes?, category_ids?}`.
struct ActivityCreateRequest: Encodable, Sendable {
    let id: UUID
    let name: String
    let color: ActivityColor
    let icon: ActivityIcon
    let notes: String?
    let categoryIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case id, name, color, icon, notes
        case categoryIds = "category_ids"
    }
}

/// `PATCH /activities/{id}` body. `updated_at` is always carried for LWW (R2);
/// other fields are optional and omitted when nil (replace-all tags when
/// `category_ids` is present).
struct ActivityPatchRequest: Encodable, Sendable {
    let name: String?
    let color: ActivityColor?
    let icon: ActivityIcon?
    let notes: String?
    let categoryIds: [UUID]?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, color, icon, notes
        case categoryIds = "category_ids"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(categoryIds, forKey: .categoryIds)
        try c.encode(CatalogDateCoding.encode(updatedAt), forKey: .updatedAt)
    }
}

/// `POST /categories` body: `{id, name, color}`.
struct CategoryCreateRequest: Encodable, Sendable {
    let id: UUID
    let name: String
    let color: ActivityColor

    enum CodingKeys: String, CodingKey {
        case id, name, color
    }
}

/// `PATCH /categories/{id}` body. `updated_at` always carried for LWW (R2).
struct CategoryPatchRequest: Encodable, Sendable {
    let name: String?
    let color: ActivityColor?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, color
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(CatalogDateCoding.encode(updatedAt), forKey: .updatedAt)
    }
}
