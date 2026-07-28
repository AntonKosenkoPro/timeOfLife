import Foundation
@testable import TimeOfLife

/// `Category` collides with `ObjectiveC.Category` (an opaque-pointer typealias
/// surfaced via `import Foundation`) in this test target — the app target is
/// the defining module so its own `Category` shadows it, but here both are
/// imported. Pin the name to the catalog domain model so test code reads
/// naturally. Module-wide (internal) typealias.
typealias Category = TimeOfLife.Category
