import Foundation

// MARK: - Activity DTOs

/// `POST /activities` request body — `ActivityCreate`.
struct ActivityCreateRequest: Encodable, Equatable, Sendable {
    let id: String
    let name: String
    let notes: String?
    let categoryIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case categoryIds = "category_ids"
    }
}

/// `PATCH /activities/{id}` request body — `ActivityUpdate`.
struct ActivityUpdateRequest: Encodable, Equatable, Sendable {
    let updatedAt: Date
    let name: String?
    let notes: String?
    let categoryIds: [String]?

    enum CodingKeys: String, CodingKey {
        case name, notes
        case categoryIds = "category_ids"
        case updatedAt = "updated_at"
    }

    init(
        updatedAt: Date,
        name: String? = nil,
        notes: String? = nil,
        categoryIds: [String]? = nil
    ) {
        self.updatedAt = updatedAt
        self.name = name
        self.notes = notes
        self.categoryIds = categoryIds
    }
}

/// `Activity` response from the server.
struct ActivityDTO: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let notes: String?
    let lastUsedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let categories: [CategoryTag]

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case categories
    }
}

// MARK: - Category DTOs

/// `POST /categories` request body — `CategoryCreate`.
struct CategoryCreateRequest: Encodable, Equatable, Sendable {
    let id: String
    let name: String
    let icon: String
}

/// `PATCH /categories/{id}` request body — `CategoryUpdate`.
struct CategoryUpdateRequest: Encodable, Equatable, Sendable {
    let updatedAt: Date
    let name: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case name, icon
        case updatedAt = "updated_at"
    }

    init(
        updatedAt: Date,
        name: String? = nil,
        icon: String? = nil
    ) {
        self.updatedAt = updatedAt
        self.name = name
        self.icon = icon
    }
}

/// `Category` response from the server.
struct CategoryDTO: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let icon: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Entry DTOs

/// `POST /entries` request body — `EntryCreate`.
struct EntryCreateRequest: Encodable, Equatable, Sendable {
    let id: String
    let activityId: String
    let startedAt: Date
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

/// `PATCH /entries/{id}` request body — `EntryUpdate`.
struct EntryUpdateRequest: Encodable, Equatable, Sendable {
    let updatedAt: Date
    let startedAt: Date?
    let endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case updatedAt = "updated_at"
    }

    init(
        updatedAt: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

/// `Entry` response from the server.
struct EntryDTO: Decodable, Equatable, Sendable {
    let id: String
    let activityId: String
    let activityName: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Double?
    let createdAt: Date
    let updatedAt: Date
    let categories: [CategoryTag]

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case activityName = "activity_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case categories
    }
}

/// `GET /entries` paginated response — `EntryListResponse`.
struct EntryListResponseDTO: Decodable, Equatable, Sendable {
    let items: [EntryDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}
