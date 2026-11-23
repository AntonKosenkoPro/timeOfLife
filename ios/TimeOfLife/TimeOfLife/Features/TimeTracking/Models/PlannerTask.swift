import Foundation
import GRDB

/// One Stage 1 day-planner task (day-planner spec): plain-text checklist state
/// only — no categories, no schedule, no link to any time entry. Identity is
/// the UUID; duplicate text is allowed as independent rows. Completion is
/// derived from the nullable `completedAt` timestamp (no redundant done flag).
/// Rows sort oldest-created first with the id tie-breaker; checking never
/// reorders them.
struct PlannerTask: Identifiable, Codable, Equatable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "planner_tasks"

    let id: String
    var text: String
    var createdAt: Date
    var completedAt: Date?

    init(id: String, text: String, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    /// Manual completion state (no color-only reliance at the UI layer).
    var isCompleted: Bool { completedAt != nil }
}

/// Validation failures for planner task creation (day-planner spec: trimmed,
/// non-empty, at most 60 characters — the shared `ActivityName` rules).
enum PlannerTaskValidationError: Error, Equatable, Sendable {
    /// The trimmed text is empty.
    case empty
    /// The trimmed text exceeds `ActivityName.maxLength` characters.
    case tooLong
}

/// Pure day-cutoff helper (day-planner spec D4): the start of the current
/// device-local day. Cleanup eligibility is a strict `completedAt < cutoff`
/// comparison — never a fixed 24-hour interval.
enum PlannerDayCutoff {
    /// The start of the local day containing `now` in `calendar`.
    static func startOfLocalDay(containing now: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: now)
    }
}
