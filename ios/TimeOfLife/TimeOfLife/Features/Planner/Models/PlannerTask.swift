import Foundation

/// One day-planner task (day-planner spec): a checklist row with an
/// independent identity, a validated name, an optional ordered category set,
/// an order key shared across devices, and a nullable civil completion date.
/// Tasks with identical names have separate identities.
/// Planner rows never feed History, Insights, or Recents; they are not
/// entries, categories, or synced timer drafts.
struct PlannerTask: Codable, Equatable, Identifiable, Sendable {
    /// Client-generated UUID v7, stable across devices.
    let id: String
    /// Trimmed valid timer name (edited in the task editor sheet).
    var name: String
    /// Optional ordered category set (edited in the task editor sheet;
    /// empty when the task carries none — Start falls back to exact-text
    /// Recents inheritance). Synced as its own field intent.
    var categoryIDs: [String]
    /// Exact-decimal order key; display order is `(positionKey, id)`
    /// compared byte-wise (ASCII-only, so `String.<` agrees on all devices).
    var positionKey: String
    /// Civil completion date (`YYYY-MM-DD`) captured on the completing
    /// device, or nil when open. Synced as a date, never reinterpreted in
    /// another time zone.
    var completedOn: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case categoryIDs = "category_ids"
        case positionKey = "position_key"
        case completedOn = "completed_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        name: String,
        positionKey: String,
        completedOn: String? = nil,
        categoryIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.positionKey = positionKey
        self.completedOn = completedOn
        self.categoryIDs = categoryIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Pre-§14 relays omit the set: default to empty instead of failing
        // the feed decode (the retag intent re-converges it).
        categoryIDs = try container.decodeIfPresent([String].self, forKey: .categoryIDs) ?? []
        positionKey = try container.decode(String.self, forKey: .positionKey)
        completedOn = try container.decodeIfPresent(String.self, forKey: .completedOn)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// One queued planner mutation (the transactional outbox payload for
/// resource `planner_task`). Only the intent's field is read by the relay;
/// `operationID` is the immutable client operation id reused verbatim
/// across retries of a lost response.
struct PlannerOperationPayload: Codable, Equatable, Sendable {
    var operationID: String
    var taskID: String
    var intent: String
    var name: String?
    var positionKey: String?
    var completedOn: String?
    /// Ordered category set for `create` (initial) and `retag` (replace).
    var categoryIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case taskID = "task_id"
        case intent, name
        case positionKey = "position_key"
        case completedOn = "completed_on"
        case categoryIDs = "category_ids"
    }
}

/// Planner field intents (backend/api/openapi.yaml `PlannerIntent`).
enum PlannerIntent: String, Sendable {
    case create, rename, move, complete, reopen, delete, retag
}

/// Civil-date capture (day-planner spec D2): the writing device records the
/// local Gregorian civil date of the completion action; Today filters by
/// the viewing device's current local date.
enum PlannerCivilDate {
    /// The Gregorian civil date (`YYYY-MM-DD`) of `date` in the device's
    /// local time zone. Gregorian is fixed (never the user's preferred
    /// calendar) so the synced string means the same date everywhere.
    static func today(on date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Exact-decimal order keys (backend/api/openapi.yaml `position_key`):
/// a zero-padded 6-digit integer part with an optional fraction of up to 32
/// digits and no trailing zeros. Byte-wise comparison equals numeric
/// comparison, so `ORDER BY position_key` works directly and every device
/// resolves ties identically via the `(key, id)` total order.
///
/// Allocation mirrors the relay fixtures exactly (see the OpenAPI
/// description and the Go allocator parity tests): empty → `500000`;
/// append → integer +1; prepend → integer −1; otherwise the exact decimal
/// midpoint. Concurrent inserts in the same gap may allocate the same key;
/// the `(key, id)` tie-break keeps every device in the same order.
enum PlannerPositionKey {
    /// The key for the first task of an empty list.
    static let initial = "500000"

    private static let pattern = "^[0-9]{6}(\\.[0-9]*[1-9])?$"
    private static let maxLength = 6 + 1 + 32

    /// Whether `key` is a canonical position key.
    static func validate(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= maxLength else { return false }
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    /// Returns a key strictly between `before` and `after` (nil either side
    /// for an unbounded end), or nil when the inputs are invalid or the
    /// space is exhausted (practically unreachable: 500k appends/prepends
    /// from the initial key in either direction).
    static func allocate(before: String?, after: String?) -> String? {
        switch (before, after) {
        case (nil, nil):
            return initial
        case let (before?, nil):
            guard validate(before) else { return nil }
            return increment(before)
        case let (nil, after?):
            guard validate(after) else { return nil }
            return decrement(after)
        case let (before?, after?):
            guard validate(before), validate(after), before < after else { return nil }
            return midpoint(before: before, after: after)
        }
    }

    private static func split(_ key: String) -> (int: String, frac: String) {
        if let dot = key.firstIndex(of: ".") {
            return (String(key[..<dot]), String(key[key.index(after: dot)...]))
        }
        return (key, "")
    }

    /// Parses a validated key into its exact scaled-integer digit string:
    /// integer part concatenated with the fraction padded right to `scale`.
    private static func scaledValue(_ key: String, scale: Int) -> String {
        let parts = split(key)
        return parts.int + parts.frac + String(repeating: "0", count: scale - parts.frac.count)
    }

    /// Decimal-string addition (non-negative operands, no decimal points).
    private static func add(_ lhs: String, _ rhs: String) -> String {
        let a = Array(lhs.reversed()), b = Array(rhs.reversed())
        var result: [Character] = []
        var carry = 0
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i].wholeNumberValue ?? 0 : 0
            let y = i < b.count ? b[i].wholeNumberValue ?? 0 : 0
            let total = x + y + carry
            result.append(Character(String(total % 10)))
            carry = total / 10
        }
        if carry > 0 { result.append(Character(String(carry))) }
        return String(result.reversed())
    }

    /// Decimal-string doubling (×2). Used to test evenness via the last digit.
    private static func isEven(_ digits: String) -> Bool {
        guard let last = digits.last?.wholeNumberValue else { return true }
        // swiftlint:disable:next legacy_multiple
        return last % 2 == 0
    }

    /// Decimal-string halving (operand must be even).
    private static func halve(_ digits: String) -> String {
        var result = ""
        var carry = 0
        for ch in digits {
            let current = carry * 10 + (ch.wholeNumberValue ?? 0)
            let q = current / 2
            if !result.isEmpty || q > 0 { result.append(Character(String(q))) }
            carry = current % 2
        }
        return result.isEmpty ? "0" : result
    }

    /// Decimal-string ×5 (exact: 5 × sum is always even, so the following
    /// halve is exact too).
    private static func timesFive(_ digits: String) -> String {
        let doubled = add(digits, digits)
        let quadrupled = add(doubled, doubled)
        return add(quadrupled, digits)
    }

    /// Renders a scaled-integer digit string back to canonical key form:
    /// 6-digit zero-padded integer, fraction without trailing zeros.
    private static func format(digits: String, scale: Int) -> String {
        var padded = digits
        while padded.count <= scale { padded = "0" + padded }
        let intEnd = padded.index(padded.endIndex, offsetBy: -scale)
        var intPart = String(padded[..<intEnd])
        while intPart.count < 6 { intPart = "0" + intPart }
        guard scale > 0 else { return intPart }
        var frac = String(padded[intEnd...])
        while frac.hasSuffix("0") { frac.removeLast() }
        guard !frac.isEmpty else { return intPart }
        return intPart + "." + frac
    }

    private static func midpoint(before: String, after: String) -> String? {
        let beforeParts = split(before), afterParts = split(after)
        let scale = max(beforeParts.frac.count, afterParts.frac.count)
        let sum = add(scaledValue(before, scale: scale), scaledValue(after, scale: scale))
        if isEven(sum) {
            return format(digits: halve(sum), scale: scale)
        }
        // Odd sum: the value is sum / (2·10^scale) = (5·sum) / 10^(scale+1),
        // so 5·sum is the exact magnitude at one more digit — no halving.
        return format(digits: timesFive(sum), scale: scale + 1)
    }

    /// Append after the last row: integer +1, fraction dropped (stays short).
    private static func increment(_ before: String) -> String? {
        let int = add(split(before).int, "1")
        guard int.count <= 6 else { return nil }
        return String(repeating: "0", count: 6 - int.count) + int
    }

    /// Prepend before the first row: integer −1. Fails at zero (unreachable
    /// from the initial key in practice).
    private static func decrement(_ after: String) -> String? {
        var digits = Array(split(after).int)
        var i = digits.count - 1
        while i >= 0, digits[i] == "0" {
            digits[i] = "9"
            i -= 1
        }
        guard i >= 0 else { return nil }
        digits[i] = Character(String((digits[i].wholeNumberValue ?? 1) - 1))
        return String(digits)
    }
}

/// One revision-ordered change from the relay feed: the latest accepted
/// state of a task plus its terminal marker (markers are retained on the
/// relay and never clear) and the commit-ordered revision that carried it.
struct PlannerFeedChange: Equatable, Sendable {
    var task: PlannerTask
    var deleted: Bool
    var revision: Int64
}

/// Today's projection (day-planner spec D2): unfinished tasks plus tasks
/// completed on the viewing device's current local civil date, in the
/// shared `(positionKey, id)` order, with done/total counts from the same
/// snapshot. Pure derivation — recompute on date/time-zone change and on
/// foreground return; carry-forward needs no write.
///
/// The launch-gate preload bundle (timer-capture-experience 12.3):
/// everything `PlannerViewModel.load()` reads, resolved together before
/// first paint so Track counts never flash 0/0 on warm data.
enum PlannerToday {
    /// Launch-gate preload bundle (timer-capture-experience 12.3).
    struct Preloaded: Sendable {
        /// The civil date the snapshot was projected on.
        var today: String
        /// The full ordered backlog (feeds submit/move/delete coordinates).
        var tasks: [PlannerTask]
        /// The capped newest-first Recents pool backing the chips line.
        var recents: [RecentEntry]
        /// Whether a timer draft persisted (planner Start gating).
        var timerActive: Bool
        /// The projected Today snapshot Track paints.
        var snapshot: Snapshot
    }

    struct Snapshot: Equatable, Sendable {
        /// Visible rows in shared display order.
        var tasks: [PlannerTask]
        /// Rows completed on the viewed date.
        var done: Int
        /// All visible rows.
        var total: Int
    }

    /// Projects `tasks` onto `civilDate` (`YYYY-MM-DD` in the viewing
    /// device's local Gregorian calendar).
    static func project(tasks: [PlannerTask], on civilDate: String) -> Snapshot {
        let visible = tasks
            .filter { $0.completedOn == nil || $0.completedOn == civilDate }
            .sorted {
                if $0.positionKey != $1.positionKey { return $0.positionKey < $1.positionKey }
                return $0.id < $1.id
            }
        return Snapshot(
            tasks: visible,
            done: visible.filter { $0.completedOn == civilDate }.count,
            total: visible.count
        )
    }
}
